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
import OSLog

private let dataManagerLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "PhotoDelete",
    category: "DataManager"
)

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
    @Published var systemAlbums: [AlbumInfo] = []
    @Published var userAlbums: [AlbumInfo] = []
    @Published var isLoadingAlbums = false
    @Published var albumLoadingProgress: Double = 0
    @Published private(set) var cleanupStatsRevision = UUID()
    @Published private(set) var reviewedAssetIDs: Set<String> = []
    let cleanupStatsStore: CleanupStatsStore
    private let albumSnapshotStore = AlbumListSnapshotStore()

    private var isReloadingLibrary = false
    private var isRestoringLibrarySnapshot = false
    private var hasLoadedAlbums = false
    private var isFetchingAlbums = false
    private var timeGroupCache: [TimeGroup: [PHAsset]] = [:]
    private var progressRefreshWorkItem: DispatchWorkItem?
    private var progressRefreshGeneration = 0
    private var libraryDataRefreshWorkItem: DispatchWorkItem?
    private var nextLibraryDataRefreshDelay: TimeInterval?
    private var reviewedAssetIDsSaveWorkItem: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    private struct TimeGroupBuildResult {
        let cache: [TimeGroup: [PHAsset]]
        let timeGroups: [TimeGroupInfo]
    }

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

    init(cleanupStatsStore: CleanupStatsStore = CleanupStatsStore()) {
        self.cleanupStatsStore = cleanupStatsStore
        loadReviewedAssetIDs()
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
            self?.scheduleLibraryDataRefresh()
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
            self.pruneReviewedAssetIDs()
            self.prunePendingCandidates()
            self.loadTimeGroups()
            self.loadAlbums(showLoading: !self.hasLoadedAlbums)
            self.updateStats()
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

            self.pruneReviewedAssetIDs()
            self.prunePendingCandidates()
            self.loadTimeGroups()
            _ = self.restoreCachedAlbums()
            self.updateStats()

            self.photoLibraryManager.refreshPhotoLibraryIfNeeded { [weak self] didRefreshLibrary in
                guard let self else { return }
                self.pruneReviewedAssetIDs()
                self.prunePendingCandidates()
                self.loadTimeGroups()
                if didRefreshLibrary {
                    self.hasLoadedAlbums = false
                    self.loadAlbums(showLoading: false)
                } else {
                    self.loadAlbumsIfNeeded()
                }
                self.updateStats()
            }
        }
    }

    // MARK: - 真实照片操作
    // MARK: - 候选库操作（新的删除逻辑）- 线程安全版本
    func addToDeleteCandidates(_ asset: PHAsset) {
        favoriteCandidates.remove(asset)
        deleteCandidates.insert(asset)
        updateStats()
    }

    func removeFromDeleteCandidates(_ asset: PHAsset) {
        deleteCandidates.remove(asset)
        updateStats()
    }

    func addToFavoriteCandidates(_ asset: PHAsset) {
        deleteCandidates.remove(asset)
        favoriteCandidates.insert(asset)
        updateStats()
    }

    func removeFromFavoriteCandidates(_ asset: PHAsset) {
        favoriteCandidates.remove(asset)
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
    }

    private func refreshDerivedLibraryData() {
        pruneReviewedAssetIDs()
        prunePendingCandidates()
        loadTimeGroups()
        updateStats()
    }

    private func clearLibraryStateAfterAccessLoss() {
        isPreparingLibrary = false
        isReloadingLibrary = false
        isRestoringLibrarySnapshot = false
        photoLibraryManager.clearLoadedLibraryData(clearSnapshot: true)
        timeGroupCache = [:]
        timeGroups = []
        systemAlbums = []
        userAlbums = []
        albumSnapshotStore.clear()
        deleteCandidates.removeAll()
        favoriteCandidates.removeAll()
        reviewedAssetIDs.removeAll()
        saveReviewedAssetIDsNow()
        hasLoadedAlbums = false
        isLoadingAlbums = false
        isFetchingAlbums = false
        albumLoadingProgress = 0
    }

    func cancelAllOperations() {
        deleteCandidates.removeAll()
        favoriteCandidates.removeAll()
        updateStats()
    }

    @discardableResult
    func markReviewed(_ asset: PHAsset) -> Bool {
        let wasReviewed = reviewedAssetIDs.contains(asset.localIdentifier)
        reviewedAssetIDs.insert(asset.localIdentifier)
        scheduleReviewedAssetIDsSave()
        scheduleProgressRefresh()
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
        reviewedAssetIDs.removeAll()
        saveReviewedAssetIDsNow()
        loadTimeGroups()
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
                }
            }
        }
        progressRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    // MARK: - 统计更新
    private func updateStats() {
        organizeStats.deletedPhotos = deleteCandidates.count
        organizeStats.totalPhotos = photoLibraryManager.totalPhotosCount

        // 估算节省的空间（每张照片约3MB）
        organizeStats.spaceSaved = Double(deleteCandidates.count) * 3.0
    }

    // MARK: - 筛选功能
    func getRealPhotos(for category: PhotoCategory) -> [PHAsset] {
        switch category {
        case .all:
            return photoLibraryManager.allPhotos
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
            return similarPhotoCandidates(maxCount: 240)
        case .largeFiles:
            return largeFileCandidates(maxCount: 240)
        case .videoCompression:
            return videoCompressionCandidates(maxCount: 240)
        case .screenshots:
            return photoLibraryManager.screenshots
        case .videos:
            return photoLibraryManager.videos.sorted {
                estimatedAssetSizeMB($0) > estimatedAssetSizeMB($1)
            }
        }
    }

    func makePhotoPeriodSummariesByScope(
        calendar: Calendar = .current
    ) -> [AdvancedTimeScope: [PhotoPeriodSummary]] {
        let screenshotIDs = Set(photoLibraryManager.screenshots.map(\.localIdentifier))
        let reviewedIDs = reviewedAssetIDs
        let deleteCandidateIDs = Set(deleteCandidates.map(\.localIdentifier))
        let favoriteCandidateIDs = Set(favoriteCandidates.map(\.localIdentifier))
        var dayBuckets: [Date: DaySummaryAccumulator] = [:]
        var weekBuckets: [Date: DaySummaryAccumulator] = [:]
        var monthBuckets: [Date: DaySummaryAccumulator] = [:]
        var yearBuckets: [Date: DaySummaryAccumulator] = [:]

        func add(
            asset: PHAsset,
            creationDate: Date,
            isScreenshot: Bool,
            isReviewed: Bool,
            estimatedSize: Double,
            to buckets: inout [Date: DaySummaryAccumulator],
            scope: AdvancedTimeScope
        ) {
            let interval = calendar.dateInterval(for: scope, containing: creationDate)
            var accumulator = buckets[interval.start] ?? DaySummaryAccumulator()
            accumulator.add(
                asset: asset,
                isScreenshot: isScreenshot,
                isReviewed: isReviewed,
                estimatedSizeMB: estimatedSize
            )
            buckets[interval.start] = accumulator
        }

        for asset in photoLibraryManager.allPhotos {
            guard let creationDate = asset.creationDate else { continue }
            let identifier = asset.localIdentifier
            let isReviewed = reviewedIDs.contains(identifier) ||
                deleteCandidateIDs.contains(identifier) ||
                favoriteCandidateIDs.contains(identifier) ||
                asset.isFavorite
            let isScreenshot = screenshotIDs.contains(identifier)
            let estimatedSize = estimatedAssetSizeMB(asset)

            add(
                asset: asset,
                creationDate: creationDate,
                isScreenshot: isScreenshot,
                isReviewed: isReviewed,
                estimatedSize: estimatedSize,
                to: &dayBuckets,
                scope: .day
            )
            add(
                asset: asset,
                creationDate: creationDate,
                isScreenshot: isScreenshot,
                isReviewed: isReviewed,
                estimatedSize: estimatedSize,
                to: &weekBuckets,
                scope: .week
            )
            add(
                asset: asset,
                creationDate: creationDate,
                isScreenshot: isScreenshot,
                isReviewed: isReviewed,
                estimatedSize: estimatedSize,
                to: &monthBuckets,
                scope: .month
            )
            add(
                asset: asset,
                creationDate: creationDate,
                isScreenshot: isScreenshot,
                isReviewed: isReviewed,
                estimatedSize: estimatedSize,
                to: &yearBuckets,
                scope: .year
            )
        }

        func summaries(
            from buckets: [Date: DaySummaryAccumulator],
            scope: AdvancedTimeScope
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

        return [
            .day: summaries(from: dayBuckets, scope: .day),
            .week: summaries(from: weekBuckets, scope: .week),
            .month: summaries(from: monthBuckets, scope: .month),
            .year: summaries(from: yearBuckets, scope: .year)
        ]
    }

    func makeAdvancedCleanupQueues() -> [AdvancedCleanupQueue] {
        let similarGroups = makeSimilarPhotoGroups(maxGroups: 120)
        let largeFiles = largeFileCandidates(maxCount: 240)
        let videoCompressionCandidates = videoCompressionCandidates(maxCount: 240)
        let screenshots = photoLibraryManager.screenshots
        let videos = photoLibraryManager.videos

        return [
            AdvancedCleanupQueue(
                kind: .similarPhotos,
                assetCount: similarGroups.reduce(0) { $0 + $1.suggestedDeleteCount },
                estimatedSpaceMB: similarGroups.reduce(0) { $0 + $1.estimatedSpaceMB }
            ),
            AdvancedCleanupQueue(
                kind: .largeFiles,
                assetCount: largeFiles.count,
                estimatedSpaceMB: largeFiles.reduce(0) { $0 + estimatedAssetSizeMB($1) }
            ),
            AdvancedCleanupQueue(
                kind: .videoCompression,
                assetCount: videoCompressionCandidates.count,
                estimatedSpaceMB: estimatedVideoCompressionSavingsMB(for: videoCompressionCandidates)
            ),
            AdvancedCleanupQueue(
                kind: .screenshots,
                assetCount: screenshots.count,
                estimatedSpaceMB: screenshots.reduce(0) { $0 + estimatedAssetSizeMB($1) }
            ),
            AdvancedCleanupQueue(
                kind: .videos,
                assetCount: videos.count,
                estimatedSpaceMB: videos.reduce(0) { $0 + estimatedAssetSizeMB($1) }
            )
        ]
    }

    func makeSimilarPhotoGroups(maxGroups: Int = 80) -> [AdvancedSimilarPhotoGroup] {
        let screenshotIDs = Set(photoLibraryManager.screenshots.map(\.localIdentifier))
        let photos = photoLibraryManager.allPhotos
            .filter { asset in
                asset.mediaType == .image &&
                    asset.creationDate != nil &&
                    !screenshotIDs.contains(asset.localIdentifier)
            }
            .sorted {
                let lhsDate = $0.creationDate ?? .distantPast
                let rhsDate = $1.creationDate ?? .distantPast
                if lhsDate == rhsDate {
                    return $0.localIdentifier < $1.localIdentifier
                }
                return lhsDate < rhsDate
            }

        var groups: [AdvancedSimilarPhotoGroup] = []
        var cluster: [PHAsset] = []

        func flushCluster() {
            guard cluster.count >= 3 else { return }
            let estimatedSpace = cluster.dropFirst().reduce(0) { $0 + estimatedAssetSizeMB($1) }
            groups.append(
                AdvancedSimilarPhotoGroup(
                    assets: cluster.sorted {
                        let lhsDate = $0.creationDate ?? .distantPast
                        let rhsDate = $1.creationDate ?? .distantPast
                        return lhsDate < rhsDate
                    },
                    estimatedSpaceMB: estimatedSpace
                )
            )
        }

        for asset in photos {
            if let previous = cluster.last, isPotentiallySimilar(asset, to: previous) {
                cluster.append(asset)
            } else {
                flushCluster()
                cluster = [asset]
            }
        }
        flushCluster()

        return Array(groups.sorted {
            ($0.representativeDate ?? .distantPast) > ($1.representativeDate ?? .distantPast)
        }.prefix(maxGroups))
    }

    private func similarPhotoCandidates(maxCount: Int) -> [PHAsset] {
        Array(makeSimilarPhotoGroups(maxGroups: max(80, maxCount / 2))
            .flatMap(\.assets)
            .prefix(maxCount))
    }

    private func largeFileCandidates(maxCount: Int) -> [PHAsset] {
        let candidates = photoLibraryManager.allPhotos.filter { asset in
            let estimatedSize = estimatedAssetSizeMB(asset)
            if asset.mediaType == .video {
                return estimatedSize >= 80
            }
            return estimatedSize >= 18
        }
        let source = candidates.isEmpty ? photoLibraryManager.allPhotos : candidates

        return Array(source.sorted {
            estimatedAssetSizeMB($0) > estimatedAssetSizeMB($1)
        }.prefix(maxCount))
    }

    private func videoCompressionCandidates(maxCount: Int) -> [PHAsset] {
        Array(photoLibraryManager.videos.sorted {
            estimatedAssetSizeMB($0) > estimatedAssetSizeMB($1)
        }.prefix(maxCount))
    }

    func estimatedVideoCompressionSavingsMB(
        for assets: [PHAsset],
        quality: VideoCompressionQuality = .balanced
    ) -> Double {
        assets.reduce(0) { total, asset in
            total + estimatedAssetSizeMB(asset) * quality.estimatedSavingsRatio
        }
    }

    private func isPotentiallySimilar(_ asset: PHAsset, to previous: PHAsset) -> Bool {
        guard let assetDate = asset.creationDate,
              let previousDate = previous.creationDate else { return false }

        let timeDistance = abs(assetDate.timeIntervalSince(previousDate))
        guard timeDistance <= 90 else { return false }

        let assetAspect = aspectRatio(for: asset)
        let previousAspect = aspectRatio(for: previous)
        return abs(assetAspect - previousAspect) <= 0.025
    }

    private func aspectRatio(for asset: PHAsset) -> Double {
        guard asset.pixelHeight > 0 else { return 0 }
        return Double(asset.pixelWidth) / Double(asset.pixelHeight)
    }

    func estimatedSizeMB(for asset: PHAsset) -> Double {
        estimatedAssetSizeMB(asset)
    }

    private func estimatedAssetSizeMB(_ asset: PHAsset) -> Double {
        let megapixels = Double(asset.pixelWidth) * Double(asset.pixelHeight) / 1_000_000
        if asset.mediaType == .video {
            return max(asset.duration * 8.0, megapixels * 0.75, 2.0)
        }
        return max(megapixels * 0.55, 0.8)
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
    func loadTimeGroups() {
        guard photoLibraryManager.hasPhotoLibraryAccess else { return }
        scheduleProgressRefresh(delay: 0)
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

        for asset in photos {
            guard let creationDate = asset.creationDate else { continue }
            let group = TimeGroupResolver.group(for: creationDate, now: now, calendar: calendar)
            cache[group, default: []].append(asset)
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

        return TimeGroupBuildResult(cache: cache, timeGroups: timeGroups)
    }

    private func loadReviewedAssetIDs() {
        let identifiers = UserDefaults.standard.stringArray(forKey: AppConstants.reviewedAssetIDsKey) ?? []
        reviewedAssetIDs = Set(identifiers)
    }

    private func saveReviewedAssetIDs() {
        UserDefaults.standard.set(Array(reviewedAssetIDs), forKey: AppConstants.reviewedAssetIDsKey)
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
    }

    private func scheduleLibraryDataRefresh() {
        libraryDataRefreshWorkItem?.cancel()
        let delay = nextLibraryDataRefreshDelay ?? 0.15
        nextLibraryDataRefreshDelay = nil
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.photoLibraryManager.hasPhotoLibraryAccess else { return }
            self.refreshDerivedLibraryData()
            self.loadAlbums(showLoading: false)
        }
        libraryDataRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    // MARK: - 相册数据加载
    func loadAlbumsIfNeeded() {
        guard !hasLoadedAlbums, !isFetchingAlbums else { return }
        if restoreCachedAlbums() {
            loadAlbums(showLoading: false)
            return
        }
        loadAlbums(showLoading: true)
    }

    func loadAlbums(showLoading: Bool? = nil) {
        guard photoLibraryManager.hasPhotoLibraryAccess else {
            isLoadingAlbums = false
            hasLoadedAlbums = false
            isFetchingAlbums = false
            albumLoadingProgress = 0
            return
        }

        let shouldShowLoading = showLoading ?? (!hasLoadedAlbums && systemAlbums.isEmpty && userAlbums.isEmpty)
        guard !isFetchingAlbums else {
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
                let fetchOptions = PHFetchOptions()
                let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)

                let thumbnailAsset = assets.firstObject
                let albumInfo = AlbumInfo(
                    assetCollection: collection,
                    type: .userCreated,
                    photosCount: assets.count,
                    thumbnailAsset: thumbnailAsset
                )
                userAlbums.append(albumInfo)
                publishProgress()
            }

            DispatchQueue.main.async {
                self.systemAlbums = systemAlbums
                self.userAlbums = userAlbums
                self.hasLoadedAlbums = true
                self.isFetchingAlbums = false
                self.albumLoadingProgress = 1
                self.isLoadingAlbums = false
                self.saveAlbumSnapshot()
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

    func insertCreatedUserAlbum(withIdentifier identifier: String?) {
        guard let identifier else { return }
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier],
            options: nil
        )
        guard let collection = collections.firstObject else { return }

        let albumInfo = AlbumInfo(
            assetCollection: collection,
            type: .userCreated,
            photosCount: 0,
            thumbnailAsset: nil
        )
        upsertUserAlbum(albumInfo)
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
            }
            completion(success)
        }
    }

    func removeUserAlbum(id: String) {
        userAlbums.removeAll { $0.id == id }
        saveAlbumSnapshot()
    }

    func deleteUserAlbum(_ album: PHAssetCollection, completion: @escaping (Bool) -> Void) {
        photoLibraryManager.deleteAlbum(album) { success, error in
            if let error {
                dataManagerLogger.error("Failed to delete album: \(error.localizedDescription, privacy: .public)")
            }
            if success {
                self.removeUserAlbum(id: album.localIdentifier)
            }
            completion(success)
        }
    }

    func recordAddedPhotoToAlbum(_ asset: PHAsset, albumID: String) {
        if refreshUserAlbumFromLibrary(id: albumID) {
            return
        }
        updateUserAlbumCount(id: albumID, delta: 1, replacementThumbnail: asset)
    }

    func recordDeletedPhotosFromAlbum(albumID: String?, deletedAssets: [PHAsset]) {
        guard let albumID, !deletedAssets.isEmpty else { return }

        if refreshUserAlbumFromLibrary(id: albumID) {
            return
        }

        updateUserAlbumCount(id: albumID, delta: -deletedAssets.count, replacementThumbnail: nil)
    }

    @discardableResult
    private func refreshUserAlbumFromLibrary(id: String) -> Bool {
        guard let index = userAlbums.firstIndex(where: { $0.id == id }) else { return false }
        let album = userAlbums[index]
        guard let collection = album.assetCollection else { return false }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        userAlbums[index] = AlbumInfo(
            id: album.id,
            title: album.title,
            assetCollection: album.assetCollection,
            type: album.type,
            photosCount: assets.count,
            thumbnailAsset: assets.firstObject
        )
        saveAlbumSnapshot()
        return true
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
    func addPhotoToAlbum(_ asset: PHAsset, album: PHAssetCollection, completion: @escaping (Bool) -> Void) {
        photoLibraryManager.addPhotosToAlbum([asset], album: album) { success, error in
            if let error = error {
                dataManagerLogger.error("Failed to add photo to album: \(error.localizedDescription, privacy: .public)")
            }
            if success {
                self.recordAddedPhotoToAlbum(asset, albumID: album.localIdentifier)
            }
            completion(success)
        }
    }
}
