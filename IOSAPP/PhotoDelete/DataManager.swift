//
//  DataManager.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import SwiftUI
import Photos
import UIKit
import Combine
import CoreLocation
import OSLog

private let dataManagerLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "PhotoDelete",
    category: "DataManager"
)

struct SimilarPhotoAssetFingerprint: Equatable {
    let identifier: String
    let creationDate: Date?
    let mediaType: PHAssetMediaType
    let pixelWidth: Int
    let pixelHeight: Int
    let burstIdentifier: String?
    let isScreenshot: Bool

    init(
        identifier: String,
        creationDate: Date?,
        mediaType: PHAssetMediaType = .image,
        pixelWidth: Int,
        pixelHeight: Int,
        burstIdentifier: String? = nil,
        isScreenshot: Bool = false
    ) {
        self.identifier = identifier
        self.creationDate = creationDate
        self.mediaType = mediaType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.burstIdentifier = burstIdentifier
        self.isScreenshot = isScreenshot
    }

    init(asset: PHAsset, isScreenshot: Bool) {
        self.init(
            identifier: asset.localIdentifier,
            creationDate: asset.creationDate,
            mediaType: asset.mediaType,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            burstIdentifier: asset.burstIdentifier,
            isScreenshot: isScreenshot
        )
    }

    var isEligibleImage: Bool {
        mediaType == .image && creationDate != nil && !isScreenshot
    }
}

enum PhotoLibraryStartupRefreshTiming {
    static let restoredSnapshotProgressDelay: TimeInterval = 1.2
}

enum AlbumLoadNeededPolicy {
    static func shouldLoad(
        hasLoadedAlbums: Bool,
        hasLoadedAlbumMembership: Bool,
        isFetchingAlbums: Bool
    ) -> Bool {
        guard !isFetchingAlbums else { return false }
        return !hasLoadedAlbums || !hasLoadedAlbumMembership
    }
}

class DataManager: ObservableObject {
    @Published var organizeStats = OrganizeStats()

    // 真实照片管理器 (非 @Published，避免内部属性变化级联刷新所有视图)
    let photoLibraryManager = PhotoLibraryManager()
    @Published var authorizationRequested = false
    @Published var isPreparingLibrary = false

    // 删除候选库 - 用于批量删除（线程安全）
    @Published var deleteCandidates: Set<PHAsset> = []
    @Published var favoriteCandidates: Set<PHAsset> = []

    // 时间组和相册信息缓存
    @Published var timeGroups: [TimeGroupInfo] = []
    @Published var historicalTodayPhotoCount = 0
    @Published var locationGroups: [PhotoLocationGroupInfo] = []
    @Published var systemAlbums: [AlbumInfo] = []
    @Published var userAlbums: [AlbumInfo] = []
    @Published var isLoadingAlbums = false
    @Published var albumLoadingProgress: Double = 0
    @Published private(set) var albumMemberAssetIDs: Set<String> = []
    @Published private(set) var hasLoadedAlbumMembership = false
    @Published private(set) var cleanupStatsRevision = UUID()
    @Published private(set) var videoCompressionHistoryRevision = UUID()
    @Published private(set) var imageCompressionHistoryRevision = UUID()
    @Published private(set) var imageCompressionJob = AdvancedImageCompressionJobState()
    @Published private(set) var videoCompressionJob = AdvancedVideoCompressionJobState()
    @Published private(set) var reviewedAssetIDs: Set<String> = []
    @Published private(set) var periodSummariesByScope: [AdvancedTimeScope: [PhotoPeriodSummary]] = [:]
    @Published private(set) var isLoadingPeriodSummaries = false
    @Published private(set) var locationGroupsRevision = UUID()
    @Published private(set) var locationGroupCoordinatesByGroupID: [String: CLLocationCoordinate2D] = [:]
    @Published private(set) var isLoadingLocationGroups = false
    @Published private(set) var isResolvingLocationTitles = false
    @Published private(set) var unresolvedLocationGroupCount = 0
    @Published private(set) var locatedAssetCount = 0
    @Published private(set) var advancedCleanupQueues: [AdvancedCleanupQueue] = []
    @Published private(set) var advancedCleanupQueuesRevision = UUID()
    @Published private(set) var isLoadingAdvancedCleanupQueues = false
    @Published private(set) var isRestoringLibrarySnapshot = false
    let cleanupStatsStore: CleanupStatsStore
    let videoCompressionHistoryStore: VideoCompressionHistoryStore
    let imageCompressionHistoryStore: ImageCompressionHistoryStore
    private let locationTitleCacheStore: PhotoLocationTitleCacheStore
    private let userDefaults: UserDefaults
    private let albumSnapshotStore = AlbumListSnapshotStore()

    private var isReloadingLibrary = false
    private var hasLoadedAlbums = false
    private var isFetchingAlbums = false
    private var pendingAlbumRefresh = false
    private var pendingAlbumRefreshShouldShowLoading = false
    private var albumMembershipCountsByAssetID: [String: Int] = [:]
    private var timeGroupCache: [TimeGroup: [PHAsset]] = [:]
    private var historicalTodayCache: [PHAsset] = []
    private var historicalTodayCacheReferenceDay: Date?
    private var locationGroupCache: [String: [PHAsset]] = [:]
    private var locationGroupBuildGeneration = 0
    private var lastLocationGroupBuildSignature: LocationGroupBuildSignature?
    private var pendingLocationGroupRefresh = false
    private var locationProgressRefreshWorkItem: DispatchWorkItem?
    private var locationProgressRefreshGeneration = 0
    private var locationTitleResolutionTask: Task<Void, Never>?
    private var progressRefreshWorkItem: DispatchWorkItem?
    private var progressRefreshGeneration = 0
    private var periodSummaryRefreshGeneration = 0
    private var advancedCleanupQueueBuildGeneration = 0
    private var lastAdvancedCleanupQueueBuildSignature: AdvancedCleanupQueueBuildSignature?
    private var pendingAdvancedCleanupQueueRefresh = false
    private var libraryDataRefreshWorkItem: DispatchWorkItem?
    private var nextLibraryDataRefreshDelay: TimeInterval?
    private var suppressNextDerivedLibraryRefresh = false
    private var reviewedAssetIDsSaveWorkItem: DispatchWorkItem?
    private var pendingDeleteCandidateIDs: Set<String> = []
    private var pendingFavoriteCandidateIDs: Set<String> = []
    private var videoFileSizeEstimateCache: [String: VideoFileSizeEstimate] = [:]
    private var imageCompressionTask: Task<Void, Never>?
    private var videoCompressionTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private struct TimeGroupBuildResult {
        let cache: [TimeGroup: [PHAsset]]
        let timeGroups: [TimeGroupInfo]
        let historicalTodayPhotos: [PHAsset]
        let historicalTodayReferenceDay: Date
    }

    private struct LocationGroupBuildResult {
        let cache: [String: [PHAsset]]
        let locationGroups: [PhotoLocationGroupInfo]
        let representativeCoordinatesByGroupID: [String: CLLocationCoordinate2D]
        let unresolvedCoordinatesByGroupID: [String: CLLocationCoordinate2D]
        let resolvedGroupIDs: Set<String>
        let locatedAssetCount: Int
    }

    private struct LocationGroupBuildSignature: Equatable {
        let photoCount: Int
        let firstPhotoID: String?
        let lastPhotoID: String?
        let assetLocationSignature: UInt64
        let reviewedCount: Int
        let reviewedAssetSignature: UInt64
        let deleteCandidateCount: Int
        let deleteCandidateSignature: UInt64
        let favoriteCandidateCount: Int
        let favoriteCandidateSignature: UInt64
        let cachedTitleCount: Int
        let titleLocaleIdentifier: String
    }

    private struct AdvancedCleanupQueueBuildSignature: Equatable {
        let photoCount: Int
        let firstPhotoID: String?
        let lastPhotoID: String?
        let videoCount: Int
        let screenshotCount: Int
        let imageCompressionSessionCount: Int
        let imageCompressionItemCount: Int
    }

    private static let similarPhotoTemporalMaxGap: TimeInterval = 5
    private static let similarPhotoTemporalMaxClusterSpan: TimeInterval = 14
    private static let similarPhotoAspectTolerance = 0.008
    private static let similarPhotoDimensionRelativeTolerance = 0.025
    private static let similarPhotoMinimumTemporalGroupSize = 2

    private struct DaySummaryAccumulator {
        var photoCount = 0
        var screenshotCount = 0
        var videoCount = 0
        var reviewedCount = 0
        var estimatedSizeMB: Double = 0

        mutating func add(
            asset: PHAsset,
            isScreenshot: Bool,
            isReviewed: Bool,
            estimatedSizeMB: Double
        ) {
            photoCount += 1
            screenshotCount += isScreenshot ? 1 : 0
            videoCount += asset.mediaType == .video ? 1 : 0
            reviewedCount += isReviewed ? 1 : 0
            self.estimatedSizeMB += estimatedSizeMB
        }
    }

    init(
        cleanupStatsStore: CleanupStatsStore = CleanupStatsStore(),
        videoCompressionHistoryStore: VideoCompressionHistoryStore = VideoCompressionHistoryStore(),
        imageCompressionHistoryStore: ImageCompressionHistoryStore = ImageCompressionHistoryStore(),
        locationTitleCacheStore: PhotoLocationTitleCacheStore = PhotoLocationTitleCacheStore(),
        userDefaults: UserDefaults = .standard
    ) {
        self.cleanupStatsStore = cleanupStatsStore
        self.videoCompressionHistoryStore = videoCompressionHistoryStore
        self.imageCompressionHistoryStore = imageCompressionHistoryStore
        self.locationTitleCacheStore = locationTitleCacheStore
        self.userDefaults = userDefaults
        loadReviewedAssetIDs()
        loadPendingCandidateIDs()
        setupPhotoLibraryManager()
    }

    private func setupPhotoLibraryManager() {
        photoLibraryManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(120), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        photoLibraryManager.onLibraryDataChanged = { [weak self] in
            guard let self else { return }
            let shouldRefreshDerivedData = !self.suppressNextDerivedLibraryRefresh
            self.suppressNextDerivedLibraryRefresh = false
            self.scheduleLibraryDataRefresh(refreshDerivedData: shouldRefreshDerivedData)
        }

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveReviewedAssetIDsNow()
            }
            .store(in: &cancellables)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncPhotoLibraryAuthorization()
        }
    }

    // MARK: - 照片权限管理
    func requestPhotoLibraryAccess() {
        if photoLibraryManager.hasPhotoLibraryAccess {
            reloadLibraryData(showPreparing: true)
            return
        }

        if photoLibraryManager.authorizationStatus == .denied ||
            photoLibraryManager.authorizationStatus == .restricted {
            openPhotoLibrarySettings()
            return
        }

        guard photoLibraryManager.authorizationStatus == .notDetermined, !authorizationRequested else { return }

        authorizationRequested = true
        photoLibraryManager.requestAuthorization { [weak self] _ in
            guard let self else { return }
            self.authorizationRequested = false
            self.syncPhotoLibraryAuthorization(showPreparing: true)
        }
    }

    func syncPhotoLibraryAuthorization(showPreparing: Bool = false) {
        let hadAccess = photoLibraryManager.hasPhotoLibraryAccess
        let previousStatus = photoLibraryManager.authorizationStatus
        photoLibraryManager.checkAuthorizationStatus()

        guard photoLibraryManager.hasPhotoLibraryAccess else {
            clearLibraryStateAfterAccessLoss()
            updateStats()
            return
        }

        let needsInitialLoad = !photoLibraryManager.hasLoadedPhotoLibrary && !photoLibraryManager.isLoading
        if !hadAccess || previousStatus != photoLibraryManager.authorizationStatus || needsInitialLoad {
            if needsInitialLoad, photoLibraryManager.hasCachedPhotoLibrarySnapshot {
                restoreCachedLibraryThenRefreshIfNeeded()
            } else {
                reloadLibraryData(showPreparing: showPreparing || needsInitialLoad)
            }
        }
    }

    func openPhotoLibrarySettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(settingsURL) else { return }

        UIApplication.shared.open(settingsURL)
    }

    func managePhotoLibraryAccessSettings() {
        if photoLibraryManager.hasLimitedPhotoLibraryAccess {
            photoLibraryManager.presentLimitedLibraryPicker()
        } else {
            openPhotoLibrarySettings()
        }
    }

    func reloadLibraryData(showPreparing: Bool = true) {
        guard photoLibraryManager.hasPhotoLibraryAccess else {
            isPreparingLibrary = false
            isReloadingLibrary = false
            return
        }

        guard !isReloadingLibrary else { return }
        isPreparingLibrary = showPreparing
        isReloadingLibrary = true

        photoLibraryManager.loadPhotos(preserveExistingData: !showPreparing) { [weak self] in
            guard let self else { return }
            self.refreshDerivedLibraryData()
            self.suppressNextDerivedLibraryRefresh = true
            self.isPreparingLibrary = false
            self.isReloadingLibrary = false
        }
    }

    private func restoreCachedLibraryThenRefreshIfNeeded() {
        guard !isRestoringLibrarySnapshot else { return }
        isRestoringLibrarySnapshot = true
        isPreparingLibrary = false

        photoLibraryManager.restoreCachedPhotoLibrary { [weak self] restored in
            guard let self else { return }
            self.isRestoringLibrarySnapshot = false

            guard restored else {
                self.reloadLibraryData(showPreparing: true)
                return
            }

            self.refreshDerivedLibraryData(
                progressRefreshDelay: PhotoLibraryStartupRefreshTiming.restoredSnapshotProgressDelay
            )
            _ = self.restoreCachedAlbums()
            self.loadAlbums(showLoading: false)

            self.photoLibraryManager.refreshPhotoLibraryIfNeeded { [weak self] didRefreshLibrary in
                guard let self else { return }
                if didRefreshLibrary {
                    self.refreshDerivedLibraryData()
                    self.suppressNextDerivedLibraryRefresh = true
                    self.hasLoadedAlbums = false
                    self.loadAlbums(showLoading: false)
                } else {
                    self.updateStats()
                }
            }
        }
    }

    // MARK: - 真实照片操作
    // MARK: - 候选库操作（新的删除逻辑）- 线程安全版本
    func addToDeleteCandidates(_ asset: PHAsset) {
        favoriteCandidates.remove(asset)
        deleteCandidates.insert(asset)
        savePendingCandidateIDsNow()
        scheduleLocationGroupsRefreshIfLoaded()
        updateStats()
    }

    func removeFromDeleteCandidates(_ asset: PHAsset) {
        deleteCandidates.remove(asset)
        savePendingCandidateIDsNow()
        scheduleLocationGroupsRefreshIfLoaded()
        updateStats()
    }

    func addToFavoriteCandidates(_ asset: PHAsset) {
        deleteCandidates.remove(asset)
        favoriteCandidates.insert(asset)
        savePendingCandidateIDsNow()
        scheduleLocationGroupsRefreshIfLoaded()
        updateStats()
    }

    func removeFromFavoriteCandidates(_ asset: PHAsset) {
        favoriteCandidates.remove(asset)
        savePendingCandidateIDsNow()
        scheduleLocationGroupsRefreshIfLoaded()
        updateStats()
    }

    func isInDeleteCandidates(_ asset: PHAsset) -> Bool {
        deleteCandidates.contains(asset)
    }

    func isInFavoriteCandidates(_ asset: PHAsset) -> Bool {
        favoriteCandidates.contains(asset)
    }

    static func remainingCandidateIdentifiers(
        deleteIDs: Set<String>,
        favoriteIDs: Set<String>,
        committedDeleteIDs: Set<String>,
        committedFavoriteIDs: Set<String>
    ) -> (deleteIDs: Set<String>, favoriteIDs: Set<String>) {
        (
            deleteIDs: deleteIDs.subtracting(committedDeleteIDs),
            favoriteIDs: favoriteIDs.subtracting(committedFavoriteIDs.union(committedDeleteIDs))
        )
    }

    static func candidateIdentifiers(
        deleteIDs: Set<String>,
        favoriteIDs: Set<String>,
        keepingValidIDs validIDs: Set<String>
    ) -> (deleteIDs: Set<String>, favoriteIDs: Set<String>) {
        (
            deleteIDs: deleteIDs.intersection(validIDs),
            favoriteIDs: favoriteIDs.intersection(validIDs)
        )
    }

    // MARK: - 批量操作（离开页面时执行）
    func executeBatchOperations(completion: @escaping (Bool, Error?) -> Void) {
        executeBatchOperations { success, error, _ in
            completion(success, error)
        }
    }

    func executeBatchOperations(
        completion: @escaping (Bool, Error?, CleanupCelebration?) -> Void
    ) {
        executeBatchOperations(
            deleteAssets: Array(deleteCandidates),
            favoriteAssets: Array(favoriteCandidates),
            completion: completion
        )
    }

    func executeBatchOperations(
        deleteAssets selectedDeleteAssets: [PHAsset],
        favoriteAssets selectedFavoriteAssets: [PHAsset],
        completion: @escaping (Bool, Error?, CleanupCelebration?) -> Void
    ) {
        let selectedDeleteIDs = Set(selectedDeleteAssets.map(\.localIdentifier))
        let selectedFavoriteIDs = Set(selectedFavoriteAssets.map(\.localIdentifier))
        let committedDeleteCandidates = deleteCandidates.filter { selectedDeleteIDs.contains($0.localIdentifier) }
        let committedFavoriteCandidates = favoriteCandidates.filter { selectedFavoriteIDs.contains($0.localIdentifier) }

        guard !committedDeleteCandidates.isEmpty || !committedFavoriteCandidates.isEmpty else {
            completion(true, nil, nil)
            return
        }

        guard photoLibraryManager.hasPhotoLibraryAccess else {
            let error = NSError(domain: "PhotoDeleteError", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: L10n.string("当前照片权限不可用")
            ])
            completion(false, error, nil)
            return
        }

        // 保存操作前的状态用于回滚
        let originalDeleteCandidates = deleteCandidates
        let originalFavoriteCandidates = favoriteCandidates
        let estimatedSpaceSaved = committedDeleteCandidates.reduce(0) { partial, asset in
            partial + estimatedAssetSizeMB(asset)
        }

        nextLibraryDataRefreshDelay = 0.65
        photoLibraryManager.commitBatchChanges(
            deleteAssets: Array(committedDeleteCandidates),
            favoriteAssets: Array(committedFavoriteCandidates)
        ) { success, error in
            guard success else {
                self.nextLibraryDataRefreshDelay = nil
                self.deleteCandidates = originalDeleteCandidates
                self.favoriteCandidates = originalFavoriteCandidates
                self.savePendingCandidateIDsNow()
                self.updateStats()
                if let error {
                    dataManagerLogger.error("Batch operation failed: \(error.localizedDescription, privacy: .public)")
                }

                let enhancedError = NSError(domain: "PhotoDeleteError", code: 1002, userInfo: [
                    NSLocalizedDescriptionKey: L10n.string("操作失败，请稍后重试。"),
                    NSLocalizedFailureReasonErrorKey: L10n.string("真实照片库未完成这次批量操作，请稍后重试")
                ])
                completion(false, enhancedError, nil)
                return
            }

            // 操作成功后先做本地增量更新，避免重新跑整库索引。
            self.photoLibraryManager.applyCommittedBatchChanges(
                deletedAssets: Array(committedDeleteCandidates),
                favoritedAssets: Array(committedFavoriteCandidates)
            )
            let completedAt = Date()
            let newAchievements = self.cleanupStatsStore.recordSession(
                deletedPhotos: committedDeleteCandidates.count,
                favoritedPhotos: committedFavoriteCandidates.count,
                organizedPhotos: committedDeleteCandidates.count + committedFavoriteCandidates.count,
                estimatedSpaceSavedMB: estimatedSpaceSaved,
                date: completedAt
            )
            let summary = self.cleanupStatsStore.summary
            let currentStreakDays = self.cleanupStatsStore.streakDays(referenceDate: completedAt)
            let celebration = CleanupCelebration(
                deletedPhotos: committedDeleteCandidates.count,
                favoritedPhotos: committedFavoriteCandidates.count,
                organizedPhotos: committedDeleteCandidates.count + committedFavoriteCandidates.count,
                estimatedSpaceSavedMB: estimatedSpaceSaved,
                totalDeletedPhotos: summary.deletedPhotos,
                totalSpaceSavedMB: summary.estimatedSpaceSavedMB,
                currentStreakDays: currentStreakDays,
                newAchievements: newAchievements,
                nextAchievementProgress: CleanupAchievementEvaluator.nextProgress(
                    summary: summary,
                    streakDays: currentStreakDays
                ),
                date: completedAt
            )
            self.removeCommittedCandidates(
                deleteIDs: Set(committedDeleteCandidates.map(\.localIdentifier)),
                favoriteIDs: Set(committedFavoriteCandidates.map(\.localIdentifier))
            )
            self.updateStats()
            self.cleanupStatsRevision = UUID()
            completion(true, nil, celebration)
        }
    }

    private func removeCommittedCandidates(deleteIDs: Set<String>, favoriteIDs: Set<String>) {
        let remainingIDs = Self.remainingCandidateIdentifiers(
            deleteIDs: Set(deleteCandidates.map(\.localIdentifier)),
            favoriteIDs: Set(favoriteCandidates.map(\.localIdentifier)),
            committedDeleteIDs: deleteIDs,
            committedFavoriteIDs: favoriteIDs
        )
        deleteCandidates = Set(deleteCandidates.filter { remainingIDs.deleteIDs.contains($0.localIdentifier) })
        favoriteCandidates = Set(favoriteCandidates.filter { remainingIDs.favoriteIDs.contains($0.localIdentifier) })
        savePendingCandidateIDsNow()
    }

    func recordVideoCompressionSession(
        videoCount: Int,
        failedCount: Int,
        originalSizeMB: Double,
        compressedSizeMB: Double,
        date: Date = Date(),
        items: [VideoCompressionSessionItem] = []
    ) {
        guard videoCompressionHistoryStore.recordSession(
            videoCount: videoCount,
            failedCount: failedCount,
            originalSizeMB: originalSizeMB,
            compressedSizeMB: compressedSizeMB,
            date: date,
            items: items
        ) != nil else { return }

        videoCompressionHistoryRevision = UUID()
    }

    func recordImageCompressionSession(
        imageCount: Int,
        failedCount: Int,
        originalSizeMB: Double,
        compressedSizeMB: Double,
        date: Date = Date(),
        items: [ImageCompressionSessionItem] = []
    ) {
        guard imageCompressionHistoryStore.recordSession(
            imageCount: imageCount,
            failedCount: failedCount,
            originalSizeMB: originalSizeMB,
            compressedSizeMB: compressedSizeMB,
            date: date,
            items: items
        ) != nil else { return }

        imageCompressionHistoryRevision = UUID()
    }

    func markVideoCompressionOriginalsDeleted(assetIdentifiers: Set<String>) {
        guard videoCompressionHistoryStore.markOriginalsDeleted(assetIdentifiers: assetIdentifiers) else { return }
        videoCompressionHistoryRevision = UUID()
    }

    func markImageCompressionOriginalsDeleted(assetIdentifiers: Set<String>) {
        guard imageCompressionHistoryStore.markOriginalsDeleted(assetIdentifiers: assetIdentifiers) else { return }
        imageCompressionHistoryRevision = UUID()
    }

    func startImageCompression(images: [PHAsset], plan: ImageCompressionPlan) {
        guard !images.isEmpty, !imageCompressionJob.isCompressing else { return }

        imageCompressionTask?.cancel()
        imageCompressionJob = .running(totalCount: images.count)
        imageCompressionTask = Task { [weak self] in
            guard let self else { return }
            let backgroundTaskID = await MainActor.run {
                Self.beginAdvancedCompressionBackgroundTask(named: "PhotoDelete.ImageCompression")
            }
            var resultItems: [AdvancedImageCompressionResultItem] = []
            var failedCount = 0
            var firstErrorMessage: String?

            for (index, asset) in images.enumerated() {
                if Task.isCancelled {
                    break
                }

                await MainActor.run {
                    self.imageCompressionJob.processedCount = index
                    self.imageCompressionJob.currentProgress = 0
                    self.imageCompressionJob.message = String(format: L10n.string("正在处理第 %lld 张图片"), Int64(index + 1))
                }

                do {
                    let result = try await self.photoLibraryManager.compressImage(
                        asset,
                        plan: plan
                    ) { [weak self] progress, message in
                        guard let self else { return }
                        self.imageCompressionJob.currentProgress = progress
                        self.imageCompressionJob.message = message
                    }
                    resultItems.append(AdvancedImageCompressionResultItem(result: result))
                } catch is CancellationError {
                    break
                } catch {
                    failedCount += 1
                    if firstErrorMessage == nil {
                        firstErrorMessage = error.localizedDescription
                    }
                }

                await MainActor.run {
                    self.imageCompressionJob.processedCount = index + 1
                    self.imageCompressionJob.currentProgress = 0
                }
            }

            let completedResultItems = resultItems
            let completedFailedCount = failedCount
            let completedFirstErrorMessage = firstErrorMessage
            let wasCancelled = Task.isCancelled
            await MainActor.run {
                self.imageCompressionJob.isCompressing = false
                self.imageCompressionJob.currentProgress = 0
                self.imageCompressionJob.message = nil
                self.imageCompressionTask = nil

                if !completedResultItems.isEmpty {
                    let completedResult = AdvancedImageCompressionResult(
                        items: completedResultItems,
                        failedCount: completedFailedCount,
                        completedAt: Date(),
                        plan: plan
                    )
                    self.imageCompressionJob.result = completedResult
                    self.recordImageCompressionSession(
                        imageCount: completedResult.successCount,
                        failedCount: completedFailedCount,
                        originalSizeMB: completedResult.originalSizeMB,
                        compressedSizeMB: completedResult.compressedSizeMB,
                        date: completedResult.completedAt,
                        items: completedResult.historyItems
                    )
                    HapticManager.notify(.success)
                } else if !wasCancelled {
                    self.imageCompressionJob.errorMessage = completedFirstErrorMessage ?? L10n.string("图片压缩失败，请稍后再试。")
                    HapticManager.notify(.warning)
                }

                if completedFailedCount > 0 && !completedResultItems.isEmpty {
                    self.imageCompressionJob.errorMessage = String(format: L10n.string("有 %lld 张图片未完成"), Int64(completedFailedCount))
                }

                Self.endAdvancedCompressionBackgroundTask(backgroundTaskID)
            }
        }
    }

    func startVideoCompression(videos: [PHAsset], plan: VideoCompressionPlan) {
        guard !videos.isEmpty, !videoCompressionJob.isCompressing else { return }

        videoCompressionTask?.cancel()
        videoCompressionJob = .running(totalCount: videos.count)
        videoCompressionTask = Task { [weak self] in
            guard let self else { return }
            let backgroundTaskID = await MainActor.run {
                Self.beginAdvancedCompressionBackgroundTask(named: "PhotoDelete.VideoCompression")
            }
            var resultItems: [AdvancedVideoCompressionResultItem] = []
            var failedCount = 0
            var firstErrorMessage: String?

            for (index, asset) in videos.enumerated() {
                if Task.isCancelled {
                    break
                }

                await MainActor.run {
                    self.videoCompressionJob.processedCount = index
                    self.videoCompressionJob.currentProgress = 0
                    self.videoCompressionJob.message = String(format: L10n.string("正在处理第 %lld 个视频"), Int64(index + 1))
                }

                do {
                    let result = try await self.photoLibraryManager.compressVideo(
                        asset,
                        plan: plan
                    ) { [weak self] progress, message in
                        guard let self else { return }
                        self.videoCompressionJob.currentProgress = progress
                        self.videoCompressionJob.message = message
                    }
                    resultItems.append(AdvancedVideoCompressionResultItem(result: result))
                } catch is CancellationError {
                    break
                } catch {
                    failedCount += 1
                    if firstErrorMessage == nil {
                        firstErrorMessage = error.localizedDescription
                    }
                }

                await MainActor.run {
                    self.videoCompressionJob.processedCount = index + 1
                    self.videoCompressionJob.currentProgress = 0
                }
            }

            let completedResultItems = resultItems
            let completedFailedCount = failedCount
            let completedFirstErrorMessage = firstErrorMessage
            let wasCancelled = Task.isCancelled
            await MainActor.run {
                self.videoCompressionJob.isCompressing = false
                self.videoCompressionJob.currentProgress = 0
                self.videoCompressionJob.message = nil
                self.videoCompressionTask = nil

                if !completedResultItems.isEmpty {
                    let completedResult = AdvancedVideoCompressionResult(
                        items: completedResultItems,
                        failedCount: completedFailedCount,
                        completedAt: Date(),
                        plan: plan
                    )
                    self.videoCompressionJob.result = completedResult
                    self.recordVideoCompressionSession(
                        videoCount: completedResult.successCount,
                        failedCount: completedFailedCount,
                        originalSizeMB: completedResult.originalSizeMB,
                        compressedSizeMB: completedResult.compressedSizeMB,
                        date: completedResult.completedAt,
                        items: completedResult.historyItems
                    )
                    self.cacheVideoCompressionSizeEstimates(from: completedResultItems)
                    HapticManager.notify(.success)
                } else if !wasCancelled {
                    self.videoCompressionJob.errorMessage = completedFirstErrorMessage ?? L10n.string("视频压缩失败，请稍后再试。")
                    HapticManager.notify(.warning)
                }

                if completedFailedCount > 0 && !completedResultItems.isEmpty {
                    self.videoCompressionJob.errorMessage = String(format: L10n.string("有 %lld 个视频未完成"), Int64(completedFailedCount))
                }

                Self.endAdvancedCompressionBackgroundTask(backgroundTaskID)
            }
        }
    }

    func setImageCompressionError(_ message: String?) {
        imageCompressionJob.errorMessage = message
    }

    func setVideoCompressionError(_ message: String?) {
        videoCompressionJob.errorMessage = message
    }

    func clearImageCompressionResult() {
        imageCompressionJob.result = nil
        imageCompressionJob.errorMessage = nil
    }

    func clearVideoCompressionResult() {
        videoCompressionJob.result = nil
        videoCompressionJob.errorMessage = nil
    }

    private func cancelAdvancedCompressionJobs() {
        imageCompressionTask?.cancel()
        videoCompressionTask?.cancel()
        imageCompressionTask = nil
        videoCompressionTask = nil
        imageCompressionJob = AdvancedImageCompressionJobState()
        videoCompressionJob = AdvancedVideoCompressionJobState()
    }

    private func cacheVideoCompressionSizeEstimates(from items: [AdvancedVideoCompressionResultItem]) {
        for item in items {
            videoFileSizeEstimateCache[item.originalAssetIdentifier] = VideoFileSizeEstimate(
                sizeMB: item.originalSizeMB,
                source: .assetResource
            )
            if let createdAssetIdentifier = item.createdAssetIdentifier {
                videoFileSizeEstimateCache[createdAssetIdentifier] = VideoFileSizeEstimate(
                    sizeMB: item.compressedSizeMB,
                    source: .assetResource
                )
            }
        }
    }

    private static func beginAdvancedCompressionBackgroundTask(named name: String) -> UIBackgroundTaskIdentifier {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: name) {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }
        return taskID
    }

    private static func endAdvancedCompressionBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
    }

    private func refreshDerivedLibraryData(progressRefreshDelay: TimeInterval = 0) {
        pruneReviewedAssetIDs()
        restorePendingCandidatesFromSavedIDs()
        prunePendingCandidates()
        loadTimeGroups(delay: progressRefreshDelay)
        updateStats()
    }

    private func clearLibraryStateAfterAccessLoss() {
        cancelAdvancedCompressionJobs()
        libraryDataRefreshWorkItem?.cancel()
        libraryDataRefreshWorkItem = nil
        suppressNextDerivedLibraryRefresh = false
        isPreparingLibrary = false
        isReloadingLibrary = false
        isRestoringLibrarySnapshot = false
        photoLibraryManager.clearLoadedLibraryData(clearSnapshot: true)
        timeGroupCache = [:]
        timeGroups = []
        historicalTodayCache = []
        historicalTodayCacheReferenceDay = nil
        historicalTodayPhotoCount = 0
        resetLocationGroupState(clearTitleCache: false)
        periodSummariesByScope = [:]
        isLoadingPeriodSummaries = false
        advancedCleanupQueues = []
        advancedCleanupQueuesRevision = UUID()
        isLoadingAdvancedCleanupQueues = false
        lastAdvancedCleanupQueueBuildSignature = nil
        pendingAdvancedCleanupQueueRefresh = false
        systemAlbums = []
        userAlbums = []
        resetAlbumMembershipState()
        albumSnapshotStore.clear()
        deleteCandidates.removeAll()
        favoriteCandidates.removeAll()
        clearPendingCandidateIDs()
        reviewedAssetIDs.removeAll()
        PhotoRandomReviewSessionStore.clearAll()
        PhotoReviewProgressStore.clearAll(defaults: userDefaults)
        saveReviewedAssetIDsNow()
        hasLoadedAlbums = false
        isLoadingAlbums = false
        isFetchingAlbums = false
        albumLoadingProgress = 0
    }

    private func resetLocationGroupState(clearTitleCache: Bool) {
        cancelLocationTitleResolution()
        locationProgressRefreshWorkItem?.cancel()
        locationProgressRefreshWorkItem = nil
        locationGroupCache = [:]
        locationGroups = []
        locationGroupCoordinatesByGroupID = [:]
        unresolvedLocationGroupCount = 0
        locatedAssetCount = 0
        locationGroupsRevision = UUID()
        isLoadingLocationGroups = false
        isResolvingLocationTitles = false
        lastLocationGroupBuildSignature = nil
        pendingLocationGroupRefresh = false
        if clearTitleCache {
            locationTitleCacheStore.clear()
        }
    }

    func cancelLocationTitleResolution() {
        let hadActiveResolution = locationTitleResolutionTask != nil || isResolvingLocationTitles
        locationTitleResolutionTask?.cancel()
        locationTitleResolutionTask = nil
        isResolvingLocationTitles = false
        if hadActiveResolution {
            lastLocationGroupBuildSignature = nil
        }
    }

    func cancelAllOperations() {
        deleteCandidates.removeAll()
        favoriteCandidates.removeAll()
        clearPendingCandidateIDs()
        scheduleLocationGroupsRefreshIfLoaded()
        updateStats()
    }

    @discardableResult
    func markReviewed(_ asset: PHAsset) -> Bool {
        let wasReviewed = reviewedAssetIDs.contains(asset.localIdentifier)
        reviewedAssetIDs.insert(asset.localIdentifier)
        scheduleReviewedAssetIDsSave()
        scheduleProgressRefresh()
        scheduleLocationGroupsRefreshIfLoaded()
        return wasReviewed
    }

    func restoreReviewedState(_ asset: PHAsset, wasReviewed: Bool) {
        if wasReviewed {
            reviewedAssetIDs.insert(asset.localIdentifier)
        } else {
            reviewedAssetIDs.remove(asset.localIdentifier)
        }
        scheduleReviewedAssetIDsSave()
        scheduleProgressRefresh()
        scheduleLocationGroupsRefreshIfLoaded()
    }

    func isReviewed(_ asset: PHAsset) -> Bool {
        reviewedAssetIDs.contains(asset.localIdentifier)
    }

    func reviewedCount(in assets: [PHAsset]) -> Int {
        assets.reduce(0) { count, asset in
            count + (reviewedAssetIDs.contains(asset.localIdentifier) ? 1 : 0)
        }
    }

    func clearLocalOrganizeData() {
        deleteCandidates.removeAll()
        favoriteCandidates.removeAll()
        clearPendingCandidateIDs()
        reviewedAssetIDs.removeAll()
        PhotoRandomReviewSessionStore.clearAll()
        PhotoReviewProgressStore.clearAll(defaults: userDefaults)
        saveReviewedAssetIDsNow()
        loadTimeGroups()
        scheduleLocationGroupsRefreshIfLoaded(delay: 0)
        updateStats()
    }

    private func scheduleProgressRefresh(delay: TimeInterval = 1.2) {
        progressRefreshWorkItem?.cancel()
        progressRefreshGeneration += 1
        let generation = progressRefreshGeneration

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.progressRefreshGeneration == generation else { return }

            let photos = self.photoLibraryManager.allPhotos
            let reviewedAssetIDs = self.reviewedAssetIDs
            let deleteCandidateIDs = Set(self.deleteCandidates.map(\.localIdentifier))
            let favoriteCandidateIDs = Set(self.favoriteCandidates.map(\.localIdentifier))

            DispatchQueue.global(qos: .utility).async { [weak self] in
                let result = Self.buildTimeGroupData(
                    photos: photos,
                    reviewedAssetIDs: reviewedAssetIDs,
                    deleteCandidateIDs: deleteCandidateIDs,
                    favoriteCandidateIDs: favoriteCandidateIDs
                )

                DispatchQueue.main.async {
                    guard let self, self.progressRefreshGeneration == generation else { return }
                    self.timeGroupCache = result.cache
                    self.timeGroups = result.timeGroups
                    self.historicalTodayCache = result.historicalTodayPhotos
                    self.historicalTodayCacheReferenceDay = result.historicalTodayReferenceDay
                    self.historicalTodayPhotoCount = result.historicalTodayPhotos.count
                    if !self.periodSummariesByScope.isEmpty {
                        self.refreshPhotoPeriodSummaries(for: Array(self.periodSummariesByScope.keys))
                    }
                }
            }
        }
        progressRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleLocationGroupsRefreshIfLoaded(delay: TimeInterval = 1.2) {
        guard locatedAssetCount > 0 ||
            !locationGroups.isEmpty ||
            isLoadingLocationGroups ||
            isResolvingLocationTitles else { return }

        locationProgressRefreshWorkItem?.cancel()
        locationProgressRefreshGeneration += 1
        let generation = locationProgressRefreshGeneration

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.locationProgressRefreshGeneration == generation else { return }
            self.loadLocationGroups(force: true)
        }

        locationProgressRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    // MARK: - 统计更新
    private func updateStats() {
        organizeStats.deletedPhotos = deleteCandidates.count
        organizeStats.totalPhotos = photoLibraryManager.totalPhotosCount

        // 删除前只能给出大致空间参考。
        organizeStats.spaceSaved = Double(deleteCandidates.count) * 3.0
    }

    // MARK: - 筛选功能
    func getRealPhotos(for category: PhotoCategory) -> [PHAsset] {
        switch category {
        case .all:
            return photoLibraryManager.allPhotos
        case .unclassified:
            return getUnclassifiedPhotos()
        case .videos:
            return photoLibraryManager.videos
        case .screenshots:
            return photoLibraryManager.screenshots
        case .livePhotos:
            return photoLibraryManager.livePhotos
        case .favorites:
            return photoLibraryManager.favorites
        }
    }

    func getUnclassifiedPhotos() -> [PHAsset] {
        guard hasLoadedAlbumMembership else { return [] }
        return photoLibraryManager.allPhotos.filter { asset in
            !albumMemberAssetIDs.contains(asset.localIdentifier)
        }
    }

    var unclassifiedPhotosCount: Int {
        getUnclassifiedPhotos().count
    }

    func getPhotosForRandomReviewScope(_ scope: PhotoRandomReviewScope) -> [PHAsset] {
        switch scope {
        case .memories:
            let cutoff = Calendar.current.date(
                byAdding: .month,
                value: -PhotoRandomReviewPlanner.oldPhotoMinimumMonthAge,
                to: Date()
            ) ?? Date()
            let oldPhotos = photoLibraryManager.allPhotos.filter { asset in
                guard let creationDate = asset.creationDate else { return false }
                return creationDate < cutoff
            }
            return oldPhotos.isEmpty ? photoLibraryManager.allPhotos : oldPhotos
        case .all:
            return photoLibraryManager.allPhotos
        case .screenshots:
            return photoLibraryManager.screenshots
        case .videos:
            return photoLibraryManager.videos
        case .livePhotos:
            return photoLibraryManager.livePhotos
        case .favorites:
            return photoLibraryManager.favorites
        }
    }

    func makeRandomReviewPhotos(
        for scope: PhotoRandomReviewScope,
        scopeID: String,
        limit: Int = PhotoRandomReviewPlanner.continuousReviewLimit
    ) -> [PHAsset] {
        let sourcePhotos = getPhotosForRandomReviewScope(scope)
        let validSourcePhotos = scope == .memories ? photoLibraryManager.allPhotos : sourcePhotos
        let validIDs = Set(validSourcePhotos.map(\.localIdentifier))
        let existingIDs = PhotoRandomReviewSessionStore.load(scopeID: scopeID)
        let resolvedIDs = PhotoRandomReviewPlanner.resolvedSessionIdentifiers(
            existingSessionIDs: existingIDs,
            candidateIdentifiers: sourcePhotos.map(\.localIdentifier),
            fallbackCandidateIdentifiers: scope == .memories ? photoLibraryManager.allPhotos.map(\.localIdentifier) : [],
            validIdentifiers: validIDs,
            excludedIdentifiers: randomReviewExcludedIdentifiers(),
            seed: UUID().uuidString,
            limit: limit
        )

        guard !resolvedIDs.isEmpty else {
            PhotoRandomReviewSessionStore.clear(scopeID: scopeID)
            return []
        }

        if !existingIDs.isEmpty {
            PhotoRandomReviewSessionStore.clear(scopeID: scopeID)
        }

        return Self.assets(in: validSourcePhotos, preserving: resolvedIDs)
    }

    private func randomReviewExcludedIdentifiers() -> Set<String> {
        reviewedAssetIDs
            .union(deleteCandidates.map(\.localIdentifier))
            .union(favoriteCandidates.map(\.localIdentifier))
    }

    func clearRandomReviewSession(scopeID: String) {
        PhotoRandomReviewSessionStore.clear(scopeID: scopeID)
    }

    private static func assets(in photos: [PHAsset], preserving identifiers: [String]) -> [PHAsset] {
        var assetsByID: [String: PHAsset] = [:]
        assetsByID.reserveCapacity(photos.count)
        for photo in photos {
            assetsByID[photo.localIdentifier] = photo
        }
        return identifiers.compactMap { assetsByID[$0] }
    }

    func makeSettingsStatsSummary() -> AdvancedLibraryStats {
        let cleanupSummary = cleanupStatsStore.summary
        let reviewedCount = min(reviewedAssetIDs.count, photoLibraryManager.allPhotos.count)

        return AdvancedLibraryStats(
            totalAssets: photoLibraryManager.totalPhotosCount,
            reviewedAssets: reviewedCount,
            deletedAssets: cleanupSummary.deletedPhotos,
            organizedAssets: max(reviewedCount, cleanupSummary.organizedPhotos),
            estimatedSpaceSavedMB: cleanupSummary.estimatedSpaceSavedMB,
            pendingDeleteAssets: deleteCandidates.count,
            storageSnapshot: Self.currentDeviceStorageSnapshot()
        )
    }

    func getPhotosForDay(_ date: Date, calendar: Calendar = .current) -> [PHAsset] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        return photoLibraryManager.allPhotos.filter { asset in
            guard let creationDate = asset.creationDate else { return false }
            return creationDate >= start && creationDate < end
        }
    }

    func getPhotosForHistoricalToday(now: Date = Date(), calendar: Calendar = .current) -> [PHAsset] {
        let todayStart = calendar.startOfDay(for: now)
        if historicalTodayCacheReferenceDay == todayStart {
            return historicalTodayCache
        }

        return Self.historicalTodayPhotos(from: photoLibraryManager.allPhotos, now: now, calendar: calendar)
    }

    func getPhotosForPeriod(
        _ scope: AdvancedTimeScope,
        containing date: Date,
        calendar: Calendar = .current
    ) -> [PHAsset] {
        let interval = calendar.dateInterval(for: scope, containing: date)
        return photoLibraryManager.allPhotos
            .filter { asset in
                guard let creationDate = asset.creationDate else { return false }
                return creationDate >= interval.start && creationDate < interval.end
            }
            .sorted {
                let lhsDate = $0.creationDate ?? .distantPast
                let rhsDate = $1.creationDate ?? .distantPast
                if lhsDate == rhsDate {
                    return $0.localIdentifier < $1.localIdentifier
                }
                return lhsDate > rhsDate
            }
    }

    func getPhotosForAdvancedCleanup(_ kind: AdvancedCleanupKind) -> [PHAsset] {
        switch kind {
        case .similarPhotos:
            return similarPhotoCandidates()
        case .largeFiles:
            return largeFileCandidates()
        case .imageCompression:
            guard AppConstants.isImageCompressionVisible else { return [] }
            return imageCompressionCandidates()
        case .videoCompression:
            return videoCompressionCandidates()
        case .videos:
            return photoLibraryManager.videos.sorted {
                estimatedAssetSizeMB($0) > estimatedAssetSizeMB($1)
            }
        }
    }

    func loadPhotosForAdvancedCleanup(
        _ kind: AdvancedCleanupKind,
        completion: @escaping ([PHAsset]) -> Void
    ) {
        let photos = photoLibraryManager.allPhotos
        let videos = photoLibraryManager.videos
        let screenshotIDs = Set(photoLibraryManager.screenshots.map(\.localIdentifier))
        let processedImageIDs = imageCompressionProcessedAssetIDs()

        DispatchQueue.global(qos: .userInitiated).async {
            let loadedAssets: [PHAsset]
            switch kind {
            case .similarPhotos:
                loadedAssets = Self.makeSimilarPhotoGroups(
                    photos: photos,
                    screenshotIDs: screenshotIDs
                )
                .flatMap(\.assets)
            case .largeFiles:
                loadedAssets = Self.largeFileCandidates(from: photos)
            case .imageCompression:
                guard AppConstants.isImageCompressionVisible else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                loadedAssets = Self.imageCompressionCandidates(
                    from: photos,
                    processedIDs: processedImageIDs
                )
            case .videoCompression:
                loadedAssets = Self.videoCompressionCandidates(from: videos)
            case .videos:
                loadedAssets = videos.sorted(by: Self.defaultVideoListOrder)
            }

            DispatchQueue.main.async {
                completion(loadedAssets)
            }
        }
    }

    func makePhotoPeriodSummaries(
        for scope: AdvancedTimeScope,
        calendar: Calendar = .current
    ) -> [PhotoPeriodSummary] {
        Self.makePhotoPeriodSummariesByScope(
            photos: photoLibraryManager.allPhotos,
            screenshotIDs: Set(photoLibraryManager.screenshots.map(\.localIdentifier)),
            reviewedIDs: reviewedAssetIDs,
            deleteCandidateIDs: Set(deleteCandidates.map(\.localIdentifier)),
            favoriteCandidateIDs: Set(favoriteCandidates.map(\.localIdentifier)),
            scopes: [scope],
            calendar: calendar
        )[scope] ?? []
    }

    func makePhotoPeriodSummariesByScope(
        calendar: Calendar = .current
    ) -> [AdvancedTimeScope: [PhotoPeriodSummary]] {
        Self.makePhotoPeriodSummariesByScope(
            photos: photoLibraryManager.allPhotos,
            screenshotIDs: Set(photoLibraryManager.screenshots.map(\.localIdentifier)),
            reviewedIDs: reviewedAssetIDs,
            deleteCandidateIDs: Set(deleteCandidates.map(\.localIdentifier)),
            favoriteCandidateIDs: Set(favoriteCandidates.map(\.localIdentifier)),
            scopes: AdvancedTimeScope.allCases,
            calendar: calendar
        )
    }

    func refreshPhotoPeriodSummaries(
        for scopes: [AdvancedTimeScope],
        calendar: Calendar = .current,
        resetCachedScopes: Bool = false
    ) {
        guard photoLibraryManager.hasPhotoLibraryAccess else {
            periodSummariesByScope = [:]
            isLoadingPeriodSummaries = false
            return
        }

        let requestedScopes = Array(Set(scopes))
        guard !requestedScopes.isEmpty else { return }

        if resetCachedScopes {
            periodSummariesByScope = [:]
        }

        periodSummaryRefreshGeneration += 1
        let generation = periodSummaryRefreshGeneration
        let photos = photoLibraryManager.allPhotos
        let screenshotIDs = Set(photoLibraryManager.screenshots.map(\.localIdentifier))
        let reviewedIDs = reviewedAssetIDs
        let deleteCandidateIDs = Set(deleteCandidates.map(\.localIdentifier))
        let favoriteCandidateIDs = Set(favoriteCandidates.map(\.localIdentifier))
        isLoadingPeriodSummaries = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let summaries = Self.makePhotoPeriodSummariesByScope(
                photos: photos,
                screenshotIDs: screenshotIDs,
                reviewedIDs: reviewedIDs,
                deleteCandidateIDs: deleteCandidateIDs,
                favoriteCandidateIDs: favoriteCandidateIDs,
                scopes: requestedScopes,
                calendar: calendar
            )

            DispatchQueue.main.async {
                guard let self, self.periodSummaryRefreshGeneration == generation else { return }
                var merged = resetCachedScopes ? [:] : self.periodSummariesByScope
                for (scope, scopeSummaries) in summaries {
                    merged[scope] = scopeSummaries
                }
                self.periodSummariesByScope = merged
                self.isLoadingPeriodSummaries = false
            }
        }
    }

    private static func makePhotoPeriodSummariesByScope(
        photos: [PHAsset],
        screenshotIDs: Set<String>,
        reviewedIDs: Set<String>,
        deleteCandidateIDs: Set<String>,
        favoriteCandidateIDs: Set<String>,
        scopes: [AdvancedTimeScope],
        calendar: Calendar
    ) -> [AdvancedTimeScope: [PhotoPeriodSummary]] {
        var bucketsByScope: [AdvancedTimeScope: [Date: DaySummaryAccumulator]] = [:]
        for scope in scopes {
            bucketsByScope[scope] = [:]
        }

        for asset in photos {
            guard let creationDate = asset.creationDate else { continue }
            let identifier = asset.localIdentifier
            let isReviewed = reviewedIDs.contains(identifier) ||
                deleteCandidateIDs.contains(identifier) ||
                favoriteCandidateIDs.contains(identifier) ||
                asset.isFavorite
            let isScreenshot = screenshotIDs.contains(identifier)
            let estimatedSize = Self.estimatedAssetSizeMBForAsset(asset)

            for scope in scopes {
                let interval = calendar.dateInterval(for: scope, containing: creationDate)
                var accumulator = bucketsByScope[scope]?[interval.start] ?? DaySummaryAccumulator()
                accumulator.add(
                    asset: asset,
                    isScreenshot: isScreenshot,
                    isReviewed: isReviewed,
                    estimatedSizeMB: estimatedSize
                )
                bucketsByScope[scope]?[interval.start] = accumulator
            }
        }

        var summariesByScope: [AdvancedTimeScope: [PhotoPeriodSummary]] = [:]
        for scope in scopes {
            summariesByScope[scope] = Self.photoPeriodSummaries(
                from: bucketsByScope[scope] ?? [:],
                scope: scope,
                calendar: calendar
            )
        }
        return summariesByScope
    }

    private static func photoPeriodSummaries(
        from buckets: [Date: DaySummaryAccumulator],
        scope: AdvancedTimeScope,
        calendar: Calendar
    ) -> [PhotoPeriodSummary] {
        buckets.map { periodStart, accumulator in
            let interval = calendar.dateInterval(for: scope, containing: periodStart)
            return PhotoPeriodSummary(
                scope: scope,
                intervalStart: interval.start,
                intervalEnd: interval.end,
                assetCount: accumulator.photoCount,
                screenshotCount: accumulator.screenshotCount,
                videoCount: accumulator.videoCount,
                reviewedCount: accumulator.reviewedCount,
                estimatedSizeMB: accumulator.estimatedSizeMB
            )
        }
        .sorted { $0.intervalStart > $1.intervalStart }
    }

    func makeAdvancedCleanupQueues() -> [AdvancedCleanupQueue] {
        Self.makeAdvancedCleanupQueues(
            photos: photoLibraryManager.allPhotos,
            videos: photoLibraryManager.videos,
            screenshotIDs: Set(photoLibraryManager.screenshots.map(\.localIdentifier)),
            imageCompressionProcessedIDs: imageCompressionProcessedAssetIDs()
        )
    }

    func refreshAdvancedCleanupQueues(force: Bool = false) {
        guard photoLibraryManager.hasPhotoLibraryAccess else {
            advancedCleanupQueues = []
            advancedCleanupQueuesRevision = UUID()
            isLoadingAdvancedCleanupQueues = false
            lastAdvancedCleanupQueueBuildSignature = nil
            pendingAdvancedCleanupQueueRefresh = false
            return
        }

        let photos = photoLibraryManager.allPhotos
        let videos = photoLibraryManager.videos
        let screenshotIDs = Set(photoLibraryManager.screenshots.map(\.localIdentifier))
        let imageSessions = AppConstants.isImageCompressionVisible ? imageCompressionHistoryStore.sessions : []
        let processedIDs = Self.imageCompressionProcessedAssetIDs(from: imageSessions)
        let signature = AdvancedCleanupQueueBuildSignature(
            photoCount: photos.count,
            firstPhotoID: photos.first?.localIdentifier,
            lastPhotoID: photos.last?.localIdentifier,
            videoCount: videos.count,
            screenshotCount: screenshotIDs.count,
            imageCompressionSessionCount: imageSessions.count,
            imageCompressionItemCount: imageSessions.reduce(0) { $0 + $1.items.count }
        )

        if !force,
           !advancedCleanupQueues.isEmpty,
           signature == lastAdvancedCleanupQueueBuildSignature {
            return
        }

        if isLoadingAdvancedCleanupQueues {
            pendingAdvancedCleanupQueueRefresh = true
            return
        }

        advancedCleanupQueueBuildGeneration += 1
        let generation = advancedCleanupQueueBuildGeneration
        isLoadingAdvancedCleanupQueues = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let queues = Self.makeAdvancedCleanupQueues(
                photos: photos,
                videos: videos,
                screenshotIDs: screenshotIDs,
                imageCompressionProcessedIDs: processedIDs
            )

            DispatchQueue.main.async {
                guard let self, self.advancedCleanupQueueBuildGeneration == generation else { return }
                self.advancedCleanupQueues = queues
                self.advancedCleanupQueuesRevision = UUID()
                self.lastAdvancedCleanupQueueBuildSignature = signature
                self.isLoadingAdvancedCleanupQueues = false

                if self.pendingAdvancedCleanupQueueRefresh {
                    self.pendingAdvancedCleanupQueueRefresh = false
                    self.refreshAdvancedCleanupQueues(force: true)
                }
            }
        }
    }

    private static func makeAdvancedCleanupQueues(
        photos: [PHAsset],
        videos: [PHAsset],
        screenshotIDs: Set<String>,
        imageCompressionProcessedIDs: Set<String>
    ) -> [AdvancedCleanupQueue] {
        let similarGroups = makeSimilarPhotoGroups(
            photos: photos,
            screenshotIDs: screenshotIDs
        )
        let largeFiles = largeFileCandidates(from: photos)
        let videoCompressionCandidates = videoCompressionCandidates(from: videos)

        var queues = [
            AdvancedCleanupQueue(
                kind: .similarPhotos,
                assetCount: similarGroups.reduce(0) { $0 + $1.suggestedDeleteCount },
                estimatedSpaceMB: similarGroups.reduce(0) { $0 + $1.estimatedSpaceMB }
            ),
            AdvancedCleanupQueue(
                kind: .largeFiles,
                assetCount: largeFiles.count,
                estimatedSpaceMB: largeFiles.reduce(0) { $0 + estimatedAssetSizeMBForAsset($1) }
            ),
            AdvancedCleanupQueue(
                kind: .videoCompression,
                assetCount: videoCompressionCandidates.count,
                estimatedSpaceMB: 0
            ),
            AdvancedCleanupQueue(
                kind: .videos,
                assetCount: videos.count,
                estimatedSpaceMB: 0
            )
        ]

        if AppConstants.isImageCompressionVisible {
            let imageCompressionCandidates = imageCompressionCandidates(
                from: photos,
                processedIDs: imageCompressionProcessedIDs
            )
            queues.insert(
                AdvancedCleanupQueue(
                    kind: .imageCompression,
                    assetCount: imageCompressionCandidates.count,
                    estimatedSpaceMB: estimatedImageCompressionEstimate(for: imageCompressionCandidates).estimatedSavedMidMB
                ),
                at: 2
            )
        }

        return queues
    }

    func makeSimilarPhotoGroups(maxGroups: Int? = nil) -> [AdvancedSimilarPhotoGroup] {
        Self.makeSimilarPhotoGroups(
            photos: photoLibraryManager.allPhotos,
            screenshotIDs: Set(photoLibraryManager.screenshots.map(\.localIdentifier)),
            maxGroups: maxGroups
        )
    }

    private static func makeSimilarPhotoGroups(
        photos allPhotos: [PHAsset],
        screenshotIDs: Set<String>,
        maxGroups: Int? = nil
    ) -> [AdvancedSimilarPhotoGroup] {
        let assetsByID = Dictionary(uniqueKeysWithValues: allPhotos.map { ($0.localIdentifier, $0) })
        let fingerprints = allPhotos.map { asset in
            SimilarPhotoAssetFingerprint(
                asset: asset,
                isScreenshot: screenshotIDs.contains(asset.localIdentifier)
            )
        }
        let groups = similarPhotoIdentifierGroups(from: fingerprints).compactMap { identifiers -> AdvancedSimilarPhotoGroup? in
            let assets = identifiers.compactMap { assetsByID[$0] }
            guard assets.count >= 2 else { return nil }
            let estimatedSpace = assets.dropFirst().reduce(0) { $0 + estimatedAssetSizeMBForAsset($1) }
            return AdvancedSimilarPhotoGroup(
                assets: assets.sorted {
                    let lhsDate = $0.creationDate ?? .distantPast
                    let rhsDate = $1.creationDate ?? .distantPast
                    if lhsDate == rhsDate {
                        return $0.localIdentifier < $1.localIdentifier
                    }
                    return lhsDate < rhsDate
                },
                estimatedSpaceMB: estimatedSpace
            )
        }

        let sortedGroups = groups.sorted { lhs, rhs in
            if lhs.estimatedSpaceMB != rhs.estimatedSpaceMB {
                return lhs.estimatedSpaceMB > rhs.estimatedSpaceMB
            }
            if lhs.suggestedDeleteCount != rhs.suggestedDeleteCount {
                return lhs.suggestedDeleteCount > rhs.suggestedDeleteCount
            }
            return (lhs.representativeDate ?? .distantPast) > (rhs.representativeDate ?? .distantPast)
        }

        guard let maxGroups else { return sortedGroups }
        return Array(sortedGroups.prefix(max(maxGroups, 0)))
    }

    static func similarPhotoIdentifierGroups(
        from fingerprints: [SimilarPhotoAssetFingerprint]
    ) -> [[String]] {
        let candidates = fingerprints
            .filter(\.isEligibleImage)
            .sorted {
                let lhsDate = $0.creationDate ?? .distantPast
                let rhsDate = $1.creationDate ?? .distantPast
                if lhsDate == rhsDate {
                    return $0.identifier < $1.identifier
                }
                return lhsDate < rhsDate
            }

        var groups: [[String]] = []
        var consumedIdentifiers = Set<String>()

        let burstGroups = Dictionary(grouping: candidates.compactMap { candidate -> SimilarPhotoAssetFingerprint? in
            guard candidate.burstIdentifier?.isEmpty == false else { return nil }
            return candidate
        }, by: { $0.burstIdentifier ?? "" })

        for burstGroup in burstGroups.values {
            let sortedBurst = burstGroup.sorted {
                let lhsDate = $0.creationDate ?? .distantPast
                let rhsDate = $1.creationDate ?? .distantPast
                if lhsDate == rhsDate {
                    return $0.identifier < $1.identifier
                }
                return lhsDate < rhsDate
            }
            guard sortedBurst.count >= 2 else { continue }
            let identifiers = sortedBurst.map(\.identifier)
            groups.append(identifiers)
            consumedIdentifiers.formUnion(identifiers)
        }

        var cluster: [SimilarPhotoAssetFingerprint] = []

        func flushCluster() {
            guard cluster.count >= similarPhotoMinimumTemporalGroupSize else {
                cluster.removeAll()
                return
            }
            groups.append(cluster.map(\.identifier))
            consumedIdentifiers.formUnion(cluster.map(\.identifier))
            cluster.removeAll()
        }

        for candidate in candidates where !consumedIdentifiers.contains(candidate.identifier) {
            if let previous = cluster.last,
               isPotentiallySimilar(candidate, to: previous),
               isWithinSimilarPhotoClusterSpan(candidate, clusterStart: cluster.first) {
                cluster.append(candidate)
            } else {
                flushCluster()
                cluster = [candidate]
            }
        }
        flushCluster()

        return groups
    }

    private func similarPhotoCandidates(maxCount: Int? = nil) -> [PHAsset] {
        let candidates = makeSimilarPhotoGroups().flatMap(\.assets)
        guard let maxCount else { return candidates }
        return Array(candidates.prefix(max(maxCount, 0)))
    }

    private func largeFileCandidates(maxCount: Int? = nil) -> [PHAsset] {
        Self.largeFileCandidates(from: photoLibraryManager.allPhotos, maxCount: maxCount)
    }

    private static func largeFileCandidates(from photos: [PHAsset], maxCount: Int? = nil) -> [PHAsset] {
        let candidates = photos.filter { asset in
            let estimatedSize = estimatedAssetSizeMBForAsset(asset)
            if asset.mediaType == .video {
                return true
            }
            return estimatedSize >= 18
        }
        let source = candidates.isEmpty ? photos : candidates

        let sorted = source.sorted {
            estimatedAssetSizeMBForAsset($0) > estimatedAssetSizeMBForAsset($1)
        }
        if let maxCount {
            return Array(sorted.prefix(maxCount))
        }
        return sorted
    }

    private func imageCompressionCandidates(maxCount: Int? = nil) -> [PHAsset] {
        Self.imageCompressionCandidates(
            from: photoLibraryManager.allPhotos,
            processedIDs: imageCompressionProcessedAssetIDs(),
            maxCount: maxCount
        )
    }

    private func imageCompressionProcessedAssetIDs() -> Set<String> {
        Self.imageCompressionProcessedAssetIDs(from: imageCompressionHistoryStore.sessions)
    }

    private static func imageCompressionProcessedAssetIDs(
        from sessions: [ImageCompressionSession]
    ) -> Set<String> {
        Set(sessions.flatMap { session in
            session.items.flatMap { item in
                [item.originalAssetIdentifier, item.createdAssetIdentifier].compactMap { $0 }
            }
        })
    }

    private static func imageCompressionCandidates(
        from photos: [PHAsset],
        processedIDs: Set<String>,
        maxCount: Int? = nil
    ) -> [PHAsset] {
        let candidates = photos.filter { asset in
            asset.mediaType == .image &&
                !asset.mediaSubtypes.contains(.photoLive) &&
                !processedIDs.contains(asset.localIdentifier) &&
                estimatedAssetSizeMBForAsset(asset) >= 2
        }
        let source = candidates.isEmpty
            ? photos.filter {
                $0.mediaType == .image &&
                    !$0.mediaSubtypes.contains(.photoLive) &&
                    !processedIDs.contains($0.localIdentifier)
            }
            : candidates

        let sorted = source.sorted {
            estimatedAssetSizeMBForAsset($0) > estimatedAssetSizeMBForAsset($1)
        }
        if let maxCount {
            return Array(sorted.prefix(maxCount))
        }
        return sorted
    }

    private func videoCompressionCandidates(maxCount: Int? = nil) -> [PHAsset] {
        Self.videoCompressionCandidates(from: photoLibraryManager.videos, maxCount: maxCount)
    }

    private static func videoCompressionCandidates(from videos: [PHAsset], maxCount: Int? = nil) -> [PHAsset] {
        let sorted = videos.sorted(by: defaultVideoListOrder)
        if let maxCount {
            return Array(sorted.prefix(maxCount))
        }
        return sorted
    }

    private static func defaultVideoListOrder(_ lhs: PHAsset, _ rhs: PHAsset) -> Bool {
        let lhsDate = lhs.creationDate ?? .distantPast
        let rhsDate = rhs.creationDate ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.localIdentifier < rhs.localIdentifier
    }

    func estimatedImageCompressionSavingsMB(
        for assets: [PHAsset],
        plan: ImageCompressionPlan = .default
    ) -> Double {
        Self.estimatedImageCompressionEstimate(for: assets, plan: plan).estimatedSavedMidMB
    }

    func estimatedImageCompressionEstimate(
        for assets: [PHAsset],
        plan: ImageCompressionPlan = .default,
        knownOriginalSizeMBByAssetID: [String: Double] = [:]
    ) -> ImageCompressionEstimate {
        Self.estimatedImageCompressionEstimate(
            for: assets,
            plan: plan,
            knownOriginalSizeMBByAssetID: knownOriginalSizeMBByAssetID
        )
    }

    private static func estimatedImageCompressionEstimate(
        for assets: [PHAsset],
        plan: ImageCompressionPlan = .default,
        knownOriginalSizeMBByAssetID: [String: Double] = [:]
    ) -> ImageCompressionEstimate {
        let originalSize = assets.reduce(0) { total, asset in
            total + originalSizeMB(for: asset, knownOriginalSizeMBByAssetID: knownOriginalSizeMBByAssetID)
        }
        let estimatedMidCompressedSize = assets.reduce(0) { total, asset in
            total + estimatedCompressedImageSizeMB(
                for: asset,
                plan: plan,
                knownOriginalSizeMBByAssetID: knownOriginalSizeMBByAssetID
            )
        }
        let lowerBound = max(estimatedMidCompressedSize * 0.84, originalSize * 0.04)
        let upperBound = min(estimatedMidCompressedSize * 1.18, originalSize * 0.98)
        return ImageCompressionEstimate(
            originalSizeMB: originalSize,
            estimatedCompressedLowMB: min(lowerBound, upperBound),
            estimatedCompressedHighMB: max(lowerBound, upperBound)
        )
    }

    func estimatedVideoCompressionSavingsMB(
        for assets: [PHAsset],
        plan: VideoCompressionPlan = .default
    ) -> Double {
        Self.estimatedVideoCompressionEstimate(for: assets, plan: plan).estimatedSavedMidMB
    }

    func estimatedVideoCompressionEstimate(
        for assets: [PHAsset],
        plan: VideoCompressionPlan = .default,
        knownOriginalSizeMBByAssetID: [String: Double] = [:]
    ) -> VideoCompressionEstimate {
        Self.estimatedVideoCompressionEstimate(
            for: assets,
            plan: plan,
            knownOriginalSizeMBByAssetID: knownOriginalSizeMBByAssetID
        )
    }

    private static func estimatedVideoCompressionEstimate(
        for assets: [PHAsset],
        plan: VideoCompressionPlan = .default,
        knownOriginalSizeMBByAssetID: [String: Double] = [:]
    ) -> VideoCompressionEstimate {
        let originalSize = assets.reduce(0) { total, asset in
            total + originalSizeMB(for: asset, knownOriginalSizeMBByAssetID: knownOriginalSizeMBByAssetID)
        }
        let estimatedMidCompressedSize = assets.reduce(0) { total, asset in
            total + estimatedCompressedSizeMB(
                for: asset,
                plan: plan,
                knownOriginalSizeMBByAssetID: knownOriginalSizeMBByAssetID
            )
        }
        let lowerBound = max(estimatedMidCompressedSize * 0.88, originalSize * 0.04)
        let upperBound = min(estimatedMidCompressedSize * 1.18, originalSize * 0.98)
        return VideoCompressionEstimate(
            originalSizeMB: originalSize,
            estimatedCompressedLowMB: min(lowerBound, upperBound),
            estimatedCompressedHighMB: max(lowerBound, upperBound)
        )
    }

    private static func isWithinSimilarPhotoClusterSpan(
        _ candidate: SimilarPhotoAssetFingerprint,
        clusterStart: SimilarPhotoAssetFingerprint?
    ) -> Bool {
        guard let startDate = clusterStart?.creationDate,
              let candidateDate = candidate.creationDate else { return false }
        return abs(candidateDate.timeIntervalSince(startDate)) <= similarPhotoTemporalMaxClusterSpan
    }

    private static func isPotentiallySimilar(
        _ candidate: SimilarPhotoAssetFingerprint,
        to previous: SimilarPhotoAssetFingerprint
    ) -> Bool {
        guard let assetDate = candidate.creationDate,
              let previousDate = previous.creationDate else { return false }

        let timeDistance = abs(assetDate.timeIntervalSince(previousDate))
        guard timeDistance <= similarPhotoTemporalMaxGap else { return false }

        guard hasSameOrientation(candidate, previous),
              hasSimilarDimensions(candidate, previous) else {
            return false
        }

        let assetAspect = aspectRatio(width: candidate.pixelWidth, height: candidate.pixelHeight)
        let previousAspect = aspectRatio(width: previous.pixelWidth, height: previous.pixelHeight)
        return abs(assetAspect - previousAspect) <= similarPhotoAspectTolerance
    }

    private static func hasSameOrientation(
        _ lhs: SimilarPhotoAssetFingerprint,
        _ rhs: SimilarPhotoAssetFingerprint
    ) -> Bool {
        let lhsPortrait = lhs.pixelHeight > lhs.pixelWidth
        let rhsPortrait = rhs.pixelHeight > rhs.pixelWidth
        return lhsPortrait == rhsPortrait
    }

    private static func hasSimilarDimensions(
        _ lhs: SimilarPhotoAssetFingerprint,
        _ rhs: SimilarPhotoAssetFingerprint
    ) -> Bool {
        relativeDifference(lhs.pixelWidth, rhs.pixelWidth) <= similarPhotoDimensionRelativeTolerance &&
            relativeDifference(lhs.pixelHeight, rhs.pixelHeight) <= similarPhotoDimensionRelativeTolerance
    }

    private static func relativeDifference(_ lhs: Int, _ rhs: Int) -> Double {
        let maxValue = Double(max(max(lhs, rhs), 1))
        return Double(abs(lhs - rhs)) / maxValue
    }

    private static func aspectRatio(width: Int, height: Int) -> Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }

    func estimatedSizeMB(for asset: PHAsset) -> Double {
        estimatedAssetSizeMB(asset)
    }

    func cachedVideoFileSizeEstimate(for asset: PHAsset) -> VideoFileSizeEstimate? {
        videoFileSizeEstimateCache[asset.localIdentifier]
    }

    func cacheVideoFileSizeEstimate(_ estimate: VideoFileSizeEstimate, for asset: PHAsset) {
        videoFileSizeEstimateCache[asset.localIdentifier] = estimate
    }

    func cacheVideoFileSizeEstimate(_ estimate: VideoFileSizeEstimate, forAssetIdentifier identifier: String) {
        videoFileSizeEstimateCache[identifier] = estimate
    }

    func pruneCachedVideoFileSizeEstimates(keeping assetIdentifiers: Set<String>) {
        videoFileSizeEstimateCache = videoFileSizeEstimateCache.filter { assetIdentifiers.contains($0.key) }
    }

    private func estimatedAssetSizeMB(_ asset: PHAsset) -> Double {
        Self.estimatedAssetSizeMBForAsset(asset)
    }

    private static func estimatedAssetSizeMBForAsset(_ asset: PHAsset) -> Double {
        if asset.mediaType == .video {
            let megapixels = Double(asset.pixelWidth) * Double(asset.pixelHeight) / 1_000_000
            let duration = max(asset.duration, 1)
            let bitrateMbps = min(max(megapixels * 4.2, 2.4), 48)
            return max(duration * bitrateMbps / 8, 1.5)
        }
        let megapixels = Double(asset.pixelWidth) * Double(asset.pixelHeight) / 1_000_000
        return max(megapixels * 0.55, 0.8)
    }

    private static func originalSizeMB(
        for asset: PHAsset,
        knownOriginalSizeMBByAssetID: [String: Double]
    ) -> Double {
        knownOriginalSizeMBByAssetID[asset.localIdentifier] ?? estimatedAssetSizeMBForAsset(asset)
    }

    private static func estimatedCompressedSizeMB(
        for asset: PHAsset,
        plan: VideoCompressionPlan,
        knownOriginalSizeMBByAssetID: [String: Double]
    ) -> Double {
        let originalSize = originalSizeMB(for: asset, knownOriginalSizeMBByAssetID: knownOriginalSizeMBByAssetID)
        let sourceSize = CGSize(width: max(asset.pixelWidth, 1), height: max(asset.pixelHeight, 1))
        let outputSize = plan.resolution.targetDisplaySize(for: sourceSize)
        let sourcePixelCount = max(sourceSize.width * sourceSize.height, 1)
        let outputPixelCount = max(outputSize.width * outputSize.height, 1)
        let pixelRatio = min(max(outputPixelCount / sourcePixelCount, 0.08), 1)

        let videoPortion = 0.92
        let audioAndContainerPortion = 0.08
        let compressedRatio = min(
            0.96,
            max(0.10, plan.quality.targetVideoBitrateMultiplier * pixelRatio * videoPortion + audioAndContainerPortion)
        )
        return originalSize * compressedRatio
    }

    private static func estimatedCompressedImageSizeMB(
        for asset: PHAsset,
        plan: ImageCompressionPlan,
        knownOriginalSizeMBByAssetID: [String: Double]
    ) -> Double {
        let originalSize = originalSizeMB(for: asset, knownOriginalSizeMBByAssetID: knownOriginalSizeMBByAssetID)
        let sourceSize = CGSize(width: max(asset.pixelWidth, 1), height: max(asset.pixelHeight, 1))
        let outputSize = plan.size.targetPixelSize(for: sourceSize)
        let sourcePixelCount = max(sourceSize.width * sourceSize.height, 1)
        let outputPixelCount = max(outputSize.width * outputSize.height, 1)
        let pixelRatio = min(max(outputPixelCount / sourcePixelCount, 0.10), 1)
        let qualityRatio = max(1 - plan.quality.estimatedSavingsRatio, 0.20)
        let compressedRatio = min(0.96, max(0.08, qualityRatio * pixelRatio + 0.06))
        return originalSize * compressedRatio
    }

    private static func currentDeviceStorageSnapshot() -> DeviceStorageSnapshot {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
            let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            return DeviceStorageSnapshot(totalBytes: total, freeBytes: free)
        } catch {
            dataManagerLogger.error("Unable to read device storage: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    // MARK: - 时间组数据加载
    func loadTimeGroups(delay: TimeInterval = 0) {
        guard photoLibraryManager.hasPhotoLibraryAccess else { return }
        scheduleProgressRefresh(delay: delay)
    }

    func loadLocationGroups(force: Bool = false) {
        guard photoLibraryManager.hasPhotoLibraryAccess else {
            resetLocationGroupState(clearTitleCache: false)
            return
        }

        let photos = photoLibraryManager.allPhotos
        let reviewedIDs = reviewedAssetIDs
        let deleteCandidateIDs = Set(deleteCandidates.map(\.localIdentifier))
        let favoriteCandidateIDs = Set(favoriteCandidates.map(\.localIdentifier))
        let titleLocaleIdentifier = Self.currentLocationTitleLocaleIdentifier()
        let titleCache = locationTitleCacheStore.titleCache(localeIdentifier: titleLocaleIdentifier)
        let signature = LocationGroupBuildSignature(
            photoCount: photos.count,
            firstPhotoID: photos.first?.localIdentifier,
            lastPhotoID: photos.last?.localIdentifier,
            assetLocationSignature: Self.locationAssetSignature(for: photos),
            reviewedCount: reviewedIDs.count,
            reviewedAssetSignature: Self.identifierSignature(reviewedIDs),
            deleteCandidateCount: deleteCandidateIDs.count,
            deleteCandidateSignature: Self.identifierSignature(deleteCandidateIDs),
            favoriteCandidateCount: favoriteCandidateIDs.count,
            favoriteCandidateSignature: Self.identifierSignature(favoriteCandidateIDs),
            cachedTitleCount: titleCache.count,
            titleLocaleIdentifier: titleLocaleIdentifier
        )

        if !force, signature == lastLocationGroupBuildSignature {
            return
        }

        if isLoadingLocationGroups {
            pendingLocationGroupRefresh = true
            return
        }

        cancelLocationTitleResolution()
        locationGroupBuildGeneration += 1
        let generation = locationGroupBuildGeneration
        isLoadingLocationGroups = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.buildLocationGroupData(
                photos: photos,
                reviewedAssetIDs: reviewedIDs,
                deleteCandidateIDs: deleteCandidateIDs,
                favoriteCandidateIDs: favoriteCandidateIDs,
                locationTitleCache: titleCache
            )

            DispatchQueue.main.async {
                guard let self, self.locationGroupBuildGeneration == generation else { return }

                self.locationGroupCache = result.cache
                self.locationGroups = result.locationGroups
                self.locationGroupCoordinatesByGroupID = result.representativeCoordinatesByGroupID
                self.unresolvedLocationGroupCount = result.unresolvedCoordinatesByGroupID.count
                self.locatedAssetCount = result.locatedAssetCount
                self.locationGroupsRevision = UUID()
                self.lastLocationGroupBuildSignature = result.locationGroups.isEmpty &&
                    !result.unresolvedCoordinatesByGroupID.isEmpty ? nil : signature
                self.isLoadingLocationGroups = false

                let validGroupIDs = Set(result.cache.keys)
                    .union(result.unresolvedCoordinatesByGroupID.keys)
                    .union(result.resolvedGroupIDs)
                self.locationTitleCacheStore.prune(
                    keeping: validGroupIDs,
                    localeIdentifier: titleLocaleIdentifier
                )

                if self.pendingLocationGroupRefresh {
                    self.pendingLocationGroupRefresh = false
                    self.loadLocationGroups(force: true)
                    return
                }

                self.resolveLocationTitlesIfNeeded(
                    for: result.unresolvedCoordinatesByGroupID,
                    generation: generation,
                    localeIdentifier: titleLocaleIdentifier
                )
            }
        }
    }

    func getPhotosForLocationGroup(_ groupID: String) -> [PHAsset] {
        if let cached = locationGroupCache[groupID] {
            return cached
        }

        guard !isLoadingLocationGroups,
              locationGroups.contains(where: { $0.id == groupID }) else {
            return []
        }

        let photos = photoLibraryManager.allPhotos.filter { asset in
            let coordinate = asset.location?.coordinate
            return PhotoLocationGrouping.groupID(
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude
            ) == groupID
        }
        return Self.sortedByNewestFirst(photos)
    }

    func locationGroupTitle(for groupID: String) -> String? {
        if let title = locationGroups.first(where: { $0.id == groupID })?.title {
            return PhotoLocationGrouping.readableLocationTitle(title)
        }
        if let cachedTitle = locationTitleCacheStore
            .titleCache(localeIdentifier: Self.currentLocationTitleLocaleIdentifier())[groupID]?.title {
            return PhotoLocationGrouping.readableLocationTitle(cachedTitle)
        }
        return nil
    }

    func locationDisplayText(for asset: PHAsset) -> String {
        locationDisplayTextIfAvailable(for: asset) ?? L10n.string("无地点信息")
    }

    func locationDisplayTextIfAvailable(for asset: PHAsset) -> String? {
        guard let coordinate = asset.location?.coordinate else {
            return nil
        }

        let groupID = PhotoLocationGrouping.groupID(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        guard groupID != PhotoLocationGrouping.noLocationID else { return nil }
        return PhotoAssetMetadataFormatter.optionalLocationText(
            locationTitle: locationGroupTitle(for: groupID),
            coordinate: coordinate
        )
    }

    private func resolveLocationTitlesIfNeeded(
        for coordinatesByGroupID: [String: CLLocationCoordinate2D],
        generation: Int,
        localeIdentifier: String
    ) {
        let cachedTitles = locationTitleCacheStore.titleCache(localeIdentifier: localeIdentifier)
        let missingCoordinates = coordinatesByGroupID
            .filter { groupID, _ in
                cachedTitles[groupID] == nil && groupID != PhotoLocationGrouping.noLocationID
            }
            .sorted { $0.key < $1.key }
            .prefix(PhotoLocationGrouping.defaultMaximumGroups)
            .map { groupID, coordinate in
                (
                    groupID: groupID,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }

        guard !missingCoordinates.isEmpty else {
            isResolvingLocationTitles = false
            return
        }

        locationTitleResolutionTask?.cancel()
        isResolvingLocationTitles = true
        locationTitleResolutionTask = Task.detached(priority: .utility) { [weak self] in
            var resolvedTitles: [String: PhotoLocationResolvedTitle] = [:]
            let preferredLocale = Locale(identifier: localeIdentifier)

            for coordinate in missingCoordinates {
                guard !Task.isCancelled else { return }

                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let geocoder = CLGeocoder()
                let placemarks = try? await geocoder.reverseGeocodeLocation(
                    location,
                    preferredLocale: preferredLocale
                )
                guard let placemark = placemarks?.first,
                      let title = Self.locationDisplayTitle(for: placemark) else {
                    continue
                }

                resolvedTitles[coordinate.groupID] = PhotoLocationResolvedTitle(
                    title: title,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )

                try? await Task.sleep(nanoseconds: 150_000_000)
            }

            let resolvedTitleSnapshot = resolvedTitles
            await MainActor.run { [weak self] in
                guard let self,
                      self.locationGroupBuildGeneration == generation,
                      Self.currentLocationTitleLocaleIdentifier() == localeIdentifier else {
                    return
                }

                self.isResolvingLocationTitles = false
                self.locationTitleResolutionTask = nil
                guard !Task.isCancelled else { return }

                if !resolvedTitleSnapshot.isEmpty {
                    self.locationTitleCacheStore.merge(
                        resolvedTitleSnapshot,
                        localeIdentifier: localeIdentifier
                    )
                    let result = Self.buildLocationGroupData(
                        photos: self.photoLibraryManager.allPhotos,
                        reviewedAssetIDs: self.reviewedAssetIDs,
                        deleteCandidateIDs: Set(self.deleteCandidates.map(\.localIdentifier)),
                        favoriteCandidateIDs: Set(self.favoriteCandidates.map(\.localIdentifier)),
                        locationTitleCache: self.locationTitleCacheStore.titleCache(localeIdentifier: localeIdentifier)
                    )
                    self.locationGroupCache = result.cache
                    self.locationGroups = result.locationGroups
                    self.locationGroupCoordinatesByGroupID = result.representativeCoordinatesByGroupID
                    self.unresolvedLocationGroupCount = result.unresolvedCoordinatesByGroupID.count
                    self.locatedAssetCount = result.locatedAssetCount
                    self.locationGroupsRevision = UUID()
                    self.lastLocationGroupBuildSignature = nil
                } else {
                    self.lastLocationGroupBuildSignature = nil
                }

                if self.pendingLocationGroupRefresh {
                    self.pendingLocationGroupRefresh = false
                    self.loadLocationGroups(force: true)
                }
            }
        }
    }

    private static func currentLocationTitleLocaleIdentifier() -> String {
        AppLanguage.current.locale.identifier
    }

    private static func locationDisplayTitle(for placemark: CLPlacemark) -> String? {
        PhotoLocationGrouping.displayTitle(
            name: placemark.name,
            locality: placemark.locality,
            subLocality: placemark.subLocality,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country
        )
    }

    private static func trimmedNonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func buildTimeGroupData(
        photos: [PHAsset],
        reviewedAssetIDs: Set<String>,
        deleteCandidateIDs: Set<String>,
        favoriteCandidateIDs: Set<String>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TimeGroupBuildResult {
        var cache: [TimeGroup: [PHAsset]] = [:]
        var historicalTodayPhotos: [PHAsset] = []
        let historicalTodayReferenceDay = calendar.startOfDay(for: now)

        for asset in photos {
            guard let creationDate = asset.creationDate else { continue }
            let group = TimeGroupResolver.group(for: creationDate, now: now, calendar: calendar)
            cache[group, default: []].append(asset)

            if HistoricalTodayResolver.isHistoricalToday(creationDate, now: now, calendar: calendar) {
                historicalTodayPhotos.append(asset)
            }
        }

        let timeGroups = TimeGroup.allCases.map { timeGroup in
            let groupPhotos = cache[timeGroup] ?? []
            guard !groupPhotos.isEmpty else {
                return TimeGroupInfo(timeGroup: timeGroup, photosCount: 0, progress: 0)
            }

            let organizedCount = groupPhotos.reduce(0) { count, asset in
                let identifier = asset.localIdentifier
                let isOrganized = reviewedAssetIDs.contains(identifier) ||
                    deleteCandidateIDs.contains(identifier) ||
                    favoriteCandidateIDs.contains(identifier) ||
                    asset.isFavorite
                return count + (isOrganized ? 1 : 0)
            }

            return TimeGroupInfo(
                timeGroup: timeGroup,
                photosCount: groupPhotos.count,
                progress: Double(organizedCount) / Double(groupPhotos.count)
            )
        }

        return TimeGroupBuildResult(
            cache: cache,
            timeGroups: timeGroups,
            historicalTodayPhotos: sortedByNewestFirst(historicalTodayPhotos),
            historicalTodayReferenceDay: historicalTodayReferenceDay
        )
    }

    private static func historicalTodayPhotos(
        from photos: [PHAsset],
        now: Date,
        calendar: Calendar
    ) -> [PHAsset] {
        let matches = photos.filter { asset in
            guard let creationDate = asset.creationDate else { return false }
            return HistoricalTodayResolver.isHistoricalToday(creationDate, now: now, calendar: calendar)
        }

        return sortedByNewestFirst(matches)
    }

    private static func sortedByNewestFirst(_ photos: [PHAsset]) -> [PHAsset] {
        photos.sorted {
            let lhsDate = $0.creationDate ?? .distantPast
            let rhsDate = $1.creationDate ?? .distantPast
            if lhsDate == rhsDate {
                return $0.localIdentifier < $1.localIdentifier
            }
            return lhsDate > rhsDate
        }
    }

    private static func buildLocationGroupData(
        photos: [PHAsset],
        reviewedAssetIDs: Set<String>,
        deleteCandidateIDs: Set<String>,
        favoriteCandidateIDs: Set<String>,
        locationTitleCache: [String: PhotoLocationResolvedTitle] = [:]
    ) -> LocationGroupBuildResult {
        let records = photos.map { asset in
            let identifier = asset.localIdentifier
            let isOrganized = reviewedAssetIDs.contains(identifier) ||
                deleteCandidateIDs.contains(identifier) ||
                favoriteCandidateIDs.contains(identifier) ||
                asset.isFavorite
            return PhotoLocationAssetRecord(
                identifier: identifier,
                location: asset.location,
                isReviewed: isOrganized
            )
        }

        let result = PhotoLocationGrouping.buildGroups(
            from: records,
            titleCache: locationTitleCache
        )
        let assetsByID = Dictionary(uniqueKeysWithValues: photos.map { ($0.localIdentifier, $0) })
        var cache: [String: [PHAsset]] = [:]
        for (groupID, identifiers) in result.identifiersByGroupID {
            cache[groupID] = sortedByNewestFirst(identifiers.compactMap { assetsByID[$0] })
        }

        return LocationGroupBuildResult(
            cache: cache,
            locationGroups: result.groups,
            representativeCoordinatesByGroupID: result.representativeCoordinatesByGroupID,
            unresolvedCoordinatesByGroupID: result.unresolvedCoordinatesByGroupID,
            resolvedGroupIDs: result.resolvedGroupIDs,
            locatedAssetCount: result.locatedAssetCount
        )
    }

    private static func locationAssetSignature(for assets: [PHAsset]) -> UInt64 {
        assets.reduce(Self.signatureSeed) { hash, asset in
            let coordinate = asset.location?.coordinate
            let latitude = coordinate.map { Int64(($0.latitude * 1_000_000).rounded()) } ?? 0
            let longitude = coordinate.map { Int64(($0.longitude * 1_000_000).rounded()) } ?? 0
            return mixedSignature(
                hash,
                values: [
                    asset.localIdentifier,
                    "\(latitude)",
                    "\(longitude)"
                ]
            )
        }
    }

    private static func identifierSignature(_ identifiers: Set<String>) -> UInt64 {
        mixedSignature(Self.signatureSeed, values: identifiers.sorted())
    }

    private static var signatureSeed: UInt64 {
        14_695_981_039_346_656_037
    }

    private static func mixedSignature(_ initialHash: UInt64, values: [String]) -> UInt64 {
        var hash = initialHash
        for value in values {
            for byte in value.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            hash ^= 0xff
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private func isAssetOrganized(_ asset: PHAsset) -> Bool {
        let identifier = asset.localIdentifier
        let deleteCandidateIDs = Set(deleteCandidates.map(\.localIdentifier))
        let favoriteCandidateIDs = Set(favoriteCandidates.map(\.localIdentifier))
        return reviewedAssetIDs.contains(identifier) ||
            deleteCandidateIDs.contains(identifier) ||
            favoriteCandidateIDs.contains(identifier) ||
            asset.isFavorite
    }

    private func loadReviewedAssetIDs() {
        let identifiers = userDefaults.stringArray(forKey: AppConstants.reviewedAssetIDsKey) ?? []
        reviewedAssetIDs = Set(identifiers)
    }

    private func saveReviewedAssetIDs() {
        userDefaults.set(Array(reviewedAssetIDs), forKey: AppConstants.reviewedAssetIDsKey)
    }

    private func scheduleReviewedAssetIDsSave() {
        reviewedAssetIDsSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveReviewedAssetIDs()
        }
        reviewedAssetIDsSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    private func saveReviewedAssetIDsNow() {
        reviewedAssetIDsSaveWorkItem?.cancel()
        reviewedAssetIDsSaveWorkItem = nil
        saveReviewedAssetIDs()
    }

    private func loadPendingCandidateIDs() {
        pendingDeleteCandidateIDs = Set(
            userDefaults.stringArray(forKey: AppConstants.pendingDeleteCandidateIDsKey) ?? []
        )
        pendingFavoriteCandidateIDs = Set(
            userDefaults.stringArray(forKey: AppConstants.pendingFavoriteCandidateIDsKey) ?? []
        )
        pendingFavoriteCandidateIDs.subtract(pendingDeleteCandidateIDs)
    }

    private func savePendingCandidateIDsNow() {
        pendingDeleteCandidateIDs = Set(deleteCandidates.map(\.localIdentifier))
        pendingFavoriteCandidateIDs = Set(favoriteCandidates.map(\.localIdentifier))
            .subtracting(pendingDeleteCandidateIDs)
        userDefaults.set(Array(pendingDeleteCandidateIDs), forKey: AppConstants.pendingDeleteCandidateIDsKey)
        userDefaults.set(Array(pendingFavoriteCandidateIDs), forKey: AppConstants.pendingFavoriteCandidateIDsKey)
    }

    private func clearPendingCandidateIDs() {
        pendingDeleteCandidateIDs.removeAll()
        pendingFavoriteCandidateIDs.removeAll()
        userDefaults.removeObject(forKey: AppConstants.pendingDeleteCandidateIDsKey)
        userDefaults.removeObject(forKey: AppConstants.pendingFavoriteCandidateIDsKey)
    }

    private func restorePendingCandidatesFromSavedIDs() {
        guard !pendingDeleteCandidateIDs.isEmpty || !pendingFavoriteCandidateIDs.isEmpty else { return }
        let photos = photoLibraryManager.allPhotos
        guard !photos.isEmpty || photoLibraryManager.hasLoadedPhotoLibrary else { return }

        let assetsByID = Dictionary(uniqueKeysWithValues: photos.map { ($0.localIdentifier, $0) })
        let deleteIDs = pendingDeleteCandidateIDs
        let favoriteIDs = pendingFavoriteCandidateIDs.subtracting(deleteIDs)

        deleteCandidates = Set(deleteIDs.compactMap { assetsByID[$0] })
        favoriteCandidates = Set(favoriteIDs.compactMap { assetsByID[$0] })

        let restoredDeleteIDs = Set(deleteCandidates.map(\.localIdentifier))
        let restoredFavoriteIDs = Set(favoriteCandidates.map(\.localIdentifier))
        if restoredDeleteIDs != pendingDeleteCandidateIDs ||
            restoredFavoriteIDs != pendingFavoriteCandidateIDs {
            pendingDeleteCandidateIDs = restoredDeleteIDs
            pendingFavoriteCandidateIDs = restoredFavoriteIDs
            userDefaults.set(Array(restoredDeleteIDs), forKey: AppConstants.pendingDeleteCandidateIDsKey)
            userDefaults.set(Array(restoredFavoriteIDs), forKey: AppConstants.pendingFavoriteCandidateIDsKey)
        }
    }

    private func pruneReviewedAssetIDs() {
        let validAssetIDs = Set(photoLibraryManager.allPhotos.map(\.localIdentifier))
        guard !validAssetIDs.isEmpty || photoLibraryManager.hasLoadedPhotoLibrary else { return }

        let prunedAssetIDs = reviewedAssetIDs.intersection(validAssetIDs)
        guard prunedAssetIDs.count != reviewedAssetIDs.count else { return }
        reviewedAssetIDs = prunedAssetIDs
        saveReviewedAssetIDsNow()
    }

    private func prunePendingCandidates() {
        let validAssetIDs = Set(photoLibraryManager.allPhotos.map(\.localIdentifier))
        guard !validAssetIDs.isEmpty || photoLibraryManager.hasLoadedPhotoLibrary else { return }

        let prunedIDs = Self.candidateIdentifiers(
            deleteIDs: Set(deleteCandidates.map(\.localIdentifier)),
            favoriteIDs: Set(favoriteCandidates.map(\.localIdentifier)),
            keepingValidIDs: validAssetIDs
        )
        guard prunedIDs.deleteIDs.count != deleteCandidates.count ||
            prunedIDs.favoriteIDs.count != favoriteCandidates.count else {
            return
        }

        deleteCandidates = Set(deleteCandidates.filter { prunedIDs.deleteIDs.contains($0.localIdentifier) })
        favoriteCandidates = Set(favoriteCandidates.filter { prunedIDs.favoriteIDs.contains($0.localIdentifier) })
        savePendingCandidateIDsNow()
    }

    private func scheduleLibraryDataRefresh(refreshDerivedData: Bool = true) {
        libraryDataRefreshWorkItem?.cancel()
        let delay = nextLibraryDataRefreshDelay ?? 0.15
        nextLibraryDataRefreshDelay = nil
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.photoLibraryManager.hasPhotoLibraryAccess else { return }
            if refreshDerivedData {
                self.refreshDerivedLibraryData()
            }
            if self.hasLoadedLocationGroups {
                self.loadLocationGroups(force: true)
            }
            if self.hasLoadedAlbums {
                self.loadAlbums(showLoading: false)
            }
        }
        libraryDataRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private var hasLoadedLocationGroups: Bool {
        locatedAssetCount > 0 ||
            !locationGroups.isEmpty ||
            isLoadingLocationGroups ||
            isResolvingLocationTitles ||
            unresolvedLocationGroupCount > 0 ||
            lastLocationGroupBuildSignature != nil
    }

    // MARK: - 相册数据加载
    func loadAlbumsIfNeeded() {
        guard AlbumLoadNeededPolicy.shouldLoad(
            hasLoadedAlbums: hasLoadedAlbums,
            hasLoadedAlbumMembership: hasLoadedAlbumMembership,
            isFetchingAlbums: isFetchingAlbums
        ) else { return }

        if !hasLoadedAlbums, restoreCachedAlbums() {
            loadAlbums(showLoading: false)
            return
        }

        loadAlbums(showLoading: !hasLoadedAlbums)
    }

    func refreshAlbumsFromLibrary(showLoading: Bool = false) {
        loadAlbums(showLoading: showLoading)
    }

    func loadAlbums(showLoading: Bool? = nil) {
        guard photoLibraryManager.hasPhotoLibraryAccess else {
            isLoadingAlbums = false
            hasLoadedAlbums = false
            isFetchingAlbums = false
            pendingAlbumRefresh = false
            pendingAlbumRefreshShouldShowLoading = false
            albumLoadingProgress = 0
            resetAlbumMembershipState()
            return
        }

        let shouldShowLoading = showLoading ?? (!hasLoadedAlbums && systemAlbums.isEmpty && userAlbums.isEmpty)
        guard !isFetchingAlbums else {
            pendingAlbumRefresh = true
            pendingAlbumRefreshShouldShowLoading = pendingAlbumRefreshShouldShowLoading || shouldShowLoading
            if shouldShowLoading {
                isLoadingAlbums = true
            }
            return
        }

        isFetchingAlbums = true
        if shouldShowLoading {
            isLoadingAlbums = true
            albumLoadingProgress = 0.03
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var systemAlbums: [AlbumInfo] = []
            var userAlbums: [AlbumInfo] = []
            var albumMembershipCountsByAssetID: [String: Int] = [:]

            // 系统相册
            let smartAlbumTypes: [PHAssetCollectionSubtype] = [
                .smartAlbumUserLibrary,  // 全部照片
                .smartAlbumRecentlyAdded, // 最近项目
                .smartAlbumFavorites,    // 收藏
                .smartAlbumScreenshots,  // 截图
                .smartAlbumVideos,       // 视频
                .smartAlbumLivePhotos    // 实况照片
            ]

            let userCollections = PHAssetCollection.fetchAssetCollections(
                with: .album,
                subtype: .any,
                options: nil
            )
            let totalSteps = max(smartAlbumTypes.count + userCollections.count, 1)
            var completedSteps = 0

            func publishProgress() {
                completedSteps += 1
                let progress = min(Double(completedSteps) / Double(totalSteps), 0.98)
                DispatchQueue.main.async {
                    if shouldShowLoading {
                        self.albumLoadingProgress = max(self.albumLoadingProgress, progress)
                    }
                }
            }

            for subtype in smartAlbumTypes {
                let collections = PHAssetCollection.fetchAssetCollections(
                    with: .smartAlbum,
                    subtype: subtype,
                    options: nil
                )

                collections.enumerateObjects { collection, _, _ in
                    let fetchOptions = PHFetchOptions()
                    let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)

                    if assets.count > 0 {
                        let albumType = self.getAlbumType(for: subtype)
                        let thumbnailAsset = assets.firstObject
                        let albumInfo = AlbumInfo(
                            assetCollection: collection,
                            type: albumType,
                            photosCount: assets.count,
                            thumbnailAsset: thumbnailAsset
                        )
                        systemAlbums.append(albumInfo)
                    }
                }
                publishProgress()
            }

            // 用户创建的相册
            userCollections.enumerateObjects { collection, _, _ in
                let albumData = self.makeUserAlbumInfoAndAssetIdentifiers(from: collection)
                userAlbums.append(albumData.albumInfo)
                for identifier in albumData.assetIdentifiers {
                    albumMembershipCountsByAssetID[identifier, default: 0] += 1
                }
                publishProgress()
            }

            DispatchQueue.main.async {
                self.systemAlbums = systemAlbums
                self.userAlbums = userAlbums
                self.setAlbumMembershipCounts(albumMembershipCountsByAssetID)
                self.hasLoadedAlbums = true
                self.isFetchingAlbums = false
                self.albumLoadingProgress = 1
                self.isLoadingAlbums = false
                self.saveAlbumSnapshot()
                if self.pendingAlbumRefresh {
                    let showPendingLoading = self.pendingAlbumRefreshShouldShowLoading
                    self.pendingAlbumRefresh = false
                    self.pendingAlbumRefreshShouldShowLoading = false
                    self.loadAlbums(showLoading: showPendingLoading)
                }
            }
        }
    }

    @discardableResult
    private func restoreCachedAlbums() -> Bool {
        guard let snapshot = albumSnapshotStore.load() else { return false }

        let restoredSystemAlbums = snapshot.systemAlbums.compactMap(restoreAlbumInfo)
        let restoredUserAlbums = snapshot.userAlbums.compactMap(restoreAlbumInfo)
        systemAlbums = restoredSystemAlbums
        userAlbums = restoredUserAlbums
        resetAlbumMembershipState()
        hasLoadedAlbums = true
        isLoadingAlbums = false
        isFetchingAlbums = false
        albumLoadingProgress = 1
        return true
    }

    private func restoreAlbumInfo(_ record: CachedAlbumRecord) -> AlbumInfo? {
        guard let albumType = AlbumType.fromStoredValue(record.typeRawValue) else { return nil }
        let collection = fetchAssetCollection(withIdentifier: record.id)
        if albumType == .userCreated && collection == nil { return nil }

        return AlbumInfo(
            id: record.id,
            title: record.title,
            assetCollection: collection,
            type: albumType,
            photosCount: record.photosCount,
            thumbnailAsset: fetchAsset(withIdentifier: record.thumbnailAssetID)
        )
    }

    private func fetchAssetCollection(withIdentifier identifier: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject
    }

    private func fetchAsset(withIdentifier identifier: String?) -> PHAsset? {
        guard let identifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    private func makeUserAlbumInfo(from collection: PHAssetCollection) -> AlbumInfo {
        makeUserAlbumInfoAndAssetIdentifiers(from: collection).albumInfo
    }

    private func makeUserAlbumInfoAndAssetIdentifiers(from collection: PHAssetCollection) -> (albumInfo: AlbumInfo, assetIdentifiers: [String]) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        var assetIdentifiers: [String] = []
        assetIdentifiers.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            assetIdentifiers.append(asset.localIdentifier)
        }

        return (
            AlbumInfo(
                assetCollection: collection,
                type: .userCreated,
                photosCount: assets.count,
                thumbnailAsset: assets.firstObject
            ),
            assetIdentifiers
        )
    }

    private func setAlbumMembershipCounts(_ counts: [String: Int]) {
        albumMembershipCountsByAssetID = counts.filter { $0.value > 0 }
        albumMemberAssetIDs = Set(albumMembershipCountsByAssetID.keys)
        hasLoadedAlbumMembership = true
    }

    private func resetAlbumMembershipState() {
        albumMembershipCountsByAssetID = [:]
        albumMemberAssetIDs = []
        hasLoadedAlbumMembership = false
    }

    private func recordAlbumMembershipAdded(for assetIdentifier: String) {
        albumMembershipCountsByAssetID[assetIdentifier, default: 0] += 1
        albumMemberAssetIDs.insert(assetIdentifier)
    }

    private func recordAlbumMembershipRemoved(for assetIdentifiers: [String]) {
        guard !assetIdentifiers.isEmpty else { return }
        for identifier in assetIdentifiers {
            let nextCount = max((albumMembershipCountsByAssetID[identifier] ?? 0) - 1, 0)
            if nextCount > 0 {
                albumMembershipCountsByAssetID[identifier] = nextCount
            } else {
                albumMembershipCountsByAssetID.removeValue(forKey: identifier)
            }
        }
        albumMemberAssetIDs = Set(albumMembershipCountsByAssetID.keys)
    }

    private func saveAlbumSnapshot() {
        let snapshot = AlbumListSnapshot(
            createdAt: Date(),
            systemAlbums: systemAlbums.map { cachedAlbumRecord(from: $0) },
            userAlbums: userAlbums.map { cachedAlbumRecord(from: $0) }
        )
        let store = albumSnapshotStore
        DispatchQueue.global(qos: .utility).async {
            store.save(snapshot)
        }
    }

    private func cachedAlbumRecord(from album: AlbumInfo) -> CachedAlbumRecord {
        CachedAlbumRecord(
            id: album.id,
            title: album.title,
            typeRawValue: album.type.rawValue,
            photosCount: album.photosCount,
            thumbnailAssetID: album.thumbnailAsset?.localIdentifier
        )
    }

    // MARK: - 时间筛选方法
    func getPhotosForTimeGroup(_ timeGroup: TimeGroup) -> [PHAsset] {
        if let cached = timeGroupCache[timeGroup] {
            return cached
        }
        // 缓存未命中时回退到实时计算
        let calendar = Calendar.current
        let now = Date()
        return photoLibraryManager.allPhotos.filter { asset in
            guard let creationDate = asset.creationDate else { return false }
            return TimeGroupResolver.group(for: creationDate, now: now, calendar: calendar) == timeGroup
        }
    }

    // MARK: - 相册筛选方法
    func getPhotosForAlbum(_ albumInfo: AlbumInfo) -> [PHAsset] {
        guard let assetCollection = albumInfo.assetCollection else {
            // 如果没有 assetCollection，根据类型返回对应的照片
            switch albumInfo.type {
            case .all:
                return photoLibraryManager.allPhotos
            case .favorites:
                return photoLibraryManager.favorites
            case .screenshots:
                return photoLibraryManager.screenshots
            case .videos:
                return photoLibraryManager.videos
            case .livePhotos:
                return photoLibraryManager.livePhotos
            default:
                return []
            }
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: assetCollection, options: fetchOptions)

        var result: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            result.append(asset)
        }

        return result
    }

    // MARK: - 辅助方法
    private func getAlbumType(for subtype: PHAssetCollectionSubtype) -> AlbumType {
        switch subtype {
        case .smartAlbumUserLibrary:
            return .all
        case .smartAlbumRecentlyAdded:
            return .recents
        case .smartAlbumFavorites:
            return .favorites
        case .smartAlbumScreenshots:
            return .screenshots
        case .smartAlbumVideos:
            return .videos
        case .smartAlbumLivePhotos:
            return .livePhotos
        default:
            return .userCreated
        }
    }

    // MARK: - 相册操作
    func getUserAlbums() -> [AlbumInfo] {
        return userAlbums
    }

    func getUserAlbumsSortedByCustomOrder() -> [AlbumInfo] {
        Self.albumsSortedByCustomOrder(userAlbums, customOrder: customAlbumOrder)
    }

    func saveCustomAlbumOrder(_ order: [String]) {
        guard let value = Self.encodeCustomAlbumOrder(order) else { return }
        objectWillChange.send()
        userDefaults.set(value, forKey: AppConstants.customAlbumOrderKey)
    }

    var customAlbumOrderForDisplay: [String] {
        customAlbumOrder
    }

    private var customAlbumOrder: [String] {
        Self.decodeCustomAlbumOrder(userDefaults.string(forKey: AppConstants.customAlbumOrderKey))
    }

    static func albumsSortedByCustomOrder(_ albums: [AlbumInfo], customOrder: [String]) -> [AlbumInfo] {
        guard !customOrder.isEmpty else { return albums }

        var ranks: [String: Int] = [:]
        for (offset, id) in customOrder.enumerated() where ranks[id] == nil {
            ranks[id] = offset
        }
        return albums.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = ranks[lhs.element.id] ?? (customOrder.count + lhs.offset)
                let rhsRank = ranks[rhs.element.id] ?? (customOrder.count + rhs.offset)
                return lhsRank < rhsRank
            }
            .map(\.element)
    }

    static func customAlbumOrderByPrepending(_ albumID: String, to order: [String]) -> [String] {
        [albumID] + order.filter { $0 != albumID }
    }

    static func decodeCustomAlbumOrder(_ value: String?) -> [String] {
        guard let value,
              let data = value.data(using: .utf8),
              let order = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return order
    }

    private static func encodeCustomAlbumOrder(_ order: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(order) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func currentUserAlbumInfo(for albumInfo: AlbumInfo) -> AlbumInfo? {
        guard albumInfo.type == .userCreated else { return albumInfo }
        return refreshUserAlbumIfAvailable(id: albumInfo.id)
    }

    func cachedUserAlbumInfo(for albumInfo: AlbumInfo) -> AlbumInfo? {
        guard albumInfo.type == .userCreated else { return albumInfo }
        return userAlbums.first { $0.id == albumInfo.id }
    }

    func currentUserAlbumInfo(for album: PHAssetCollection) -> AlbumInfo? {
        refreshUserAlbumIfAvailable(id: album.localIdentifier)
    }

    func insertCreatedUserAlbum(withIdentifier identifier: String?) {
        guard let identifier else { return }
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier],
            options: nil
        )
        guard let collection = collections.firstObject else { return }

        upsertUserAlbum(makeUserAlbumInfo(from: collection))
        let orderBasis = customAlbumOrder.isEmpty ? userAlbums.map(\.id) : customAlbumOrder
        saveCustomAlbumOrder(Self.customAlbumOrderByPrepending(identifier, to: orderBasis))
        hasLoadedAlbums = true
        saveAlbumSnapshot()
    }

    func createUserAlbum(named title: String, completion: @escaping (Bool) -> Void) {
        photoLibraryManager.createAlbum(named: title) { identifier, error in
            if let error {
                dataManagerLogger.error("Failed to create album: \(error.localizedDescription, privacy: .public)")
            }
            if let identifier {
                self.insertCreatedUserAlbum(withIdentifier: identifier)
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    func renameUserAlbum(id: String, title: String) {
        guard let index = userAlbums.firstIndex(where: { $0.id == id }) else { return }
        let album = userAlbums[index]
        userAlbums[index] = AlbumInfo(
            id: album.id,
            title: title,
            assetCollection: album.assetCollection,
            type: album.type,
            photosCount: album.photosCount,
            thumbnailAsset: album.thumbnailAsset
        )
        saveAlbumSnapshot()
    }

    func renameUserAlbum(_ album: PHAssetCollection, title: String, completion: @escaping (Bool) -> Void) {
        photoLibraryManager.renameAlbum(album, title: title) { success, error in
            if let error {
                dataManagerLogger.error("Failed to update album: \(error.localizedDescription, privacy: .public)")
            }
            if success {
                self.renameUserAlbum(id: album.localIdentifier, title: title)
            } else {
                self.refreshAlbumsFromLibrary(showLoading: false)
            }
            completion(success)
        }
    }

    func removeUserAlbum(id: String) {
        let previousCount = userAlbums.count
        userAlbums.removeAll { $0.id == id }
        guard userAlbums.count != previousCount else { return }
        saveAlbumSnapshot()
    }

    func deleteUserAlbum(_ album: PHAssetCollection, completion: @escaping (Bool) -> Void) {
        let removedAssetIdentifiers = makeUserAlbumInfoAndAssetIdentifiers(from: album).assetIdentifiers
        photoLibraryManager.deleteAlbum(album) { success, error in
            if let error {
                dataManagerLogger.error("Failed to delete album: \(error.localizedDescription, privacy: .public)")
            }
            if success {
                self.removeUserAlbum(id: album.localIdentifier)
                self.recordAlbumMembershipRemoved(for: removedAssetIdentifiers)
            } else {
                self.refreshAlbumsFromLibrary(showLoading: false)
            }
            completion(success)
        }
    }

    func recordAddedPhotoToAlbum(_ asset: PHAsset, albumID: String) {
        updateUserAlbumCount(id: albumID, delta: 1, replacementThumbnail: asset)
    }

    func recordDeletedPhotosFromAlbum(albumID: String?, deletedAssets: [PHAsset]) {
        guard let albumID, !deletedAssets.isEmpty else { return }

        if refreshUserAlbumFromLibrary(id: albumID) {
            return
        }

        updateUserAlbumCount(id: albumID, delta: -deletedAssets.count, replacementThumbnail: nil)
    }

    func recordRemovedPhotosFromAlbum(albumID: String?, removedAssets: [PHAsset]) {
        guard let albumID, !removedAssets.isEmpty else { return }

        if refreshUserAlbumFromLibrary(id: albumID) {
            return
        }

        updateUserAlbumCount(id: albumID, delta: -removedAssets.count, replacementThumbnail: nil)
    }

    @discardableResult
    private func refreshUserAlbumFromLibrary(id: String) -> Bool {
        guard userAlbums.contains(where: { $0.id == id }) else { return false }
        _ = refreshUserAlbumIfAvailable(id: id)
        return true
    }

    @discardableResult
    private func refreshUserAlbumIfAvailable(id: String) -> AlbumInfo? {
        guard let index = userAlbums.firstIndex(where: { $0.id == id }) else { return nil }
        guard let collection = fetchAssetCollection(withIdentifier: id),
              collection.assetCollectionType == .album else {
            userAlbums.remove(at: index)
            saveAlbumSnapshot()
            refreshAlbumsFromLibrary(showLoading: false)
            return nil
        }

        let albumInfo = makeUserAlbumInfo(from: collection)
        userAlbums[index] = albumInfo
        saveAlbumSnapshot()
        return albumInfo
    }

    private func upsertUserAlbum(_ albumInfo: AlbumInfo) {
        if let index = userAlbums.firstIndex(where: { $0.id == albumInfo.id }) {
            userAlbums[index] = albumInfo
        } else {
            userAlbums.insert(albumInfo, at: 0)
        }
    }

    private func updateUserAlbumCount(id: String, delta: Int, replacementThumbnail: PHAsset?) {
        guard let index = userAlbums.firstIndex(where: { $0.id == id }) else { return }
        let album = userAlbums[index]
        let nextCount = max(album.photosCount + delta, 0)
        let nextThumbnail = replacementThumbnail ?? (nextCount == 0 ? nil : album.thumbnailAsset)

        userAlbums[index] = AlbumInfo(
            id: album.id,
            title: album.title,
            assetCollection: album.assetCollection,
            type: album.type,
            photosCount: nextCount,
            thumbnailAsset: nextThumbnail
        )
        saveAlbumSnapshot()
    }

    // MARK: - 相册照片操作
    func addPhotoToAlbum(_ asset: PHAsset, album: PHAssetCollection, completion: @escaping (Bool, Bool) -> Void) {
        photoLibraryManager.addPhotosToAlbum([asset], album: album) { success, insertedCount, error in
            if let error = error {
                dataManagerLogger.error("Failed to add photo to album: \(error.localizedDescription, privacy: .public)")
            }
            if success, insertedCount > 0 {
                self.recordAddedPhotoToAlbum(asset, albumID: album.localIdentifier)
                self.recordAlbumMembershipAdded(for: asset.localIdentifier)
            }
            completion(success, insertedCount > 0)
        }
    }

    func removePhotoFromAlbum(_ asset: PHAsset, album: PHAssetCollection, completion: @escaping (Bool) -> Void) {
        photoLibraryManager.removePhotosFromAlbum([asset], album: album) { success, error in
            if let error {
                dataManagerLogger.error("Failed to remove photo from album: \(error.localizedDescription, privacy: .public)")
            }
            if success {
                self.recordRemovedPhotosFromAlbum(albumID: album.localIdentifier, removedAssets: [asset])
                self.recordAlbumMembershipRemoved(for: [asset.localIdentifier])
            }
            completion(success)
        }
    }
}
