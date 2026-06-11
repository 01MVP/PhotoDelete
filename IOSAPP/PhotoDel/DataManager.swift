//
//  DataManager.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI
import Photos
import UIKit
import Combine
import OSLog

private let dataManagerLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "PhotoDel",
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
    private var reviewedAssetIDsSaveWorkItem: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    private struct TimeGroupBuildResult {
        let cache: [TimeGroup: [PHAsset]]
        let timeGroups: [TimeGroupInfo]
    }

    init(cleanupStatsStore: CleanupStatsStore = CleanupStatsStore()) {
        self.cleanupStatsStore = cleanupStatsStore
        loadReviewedAssetIDs()
        setupPhotoLibraryManager()
    }

    private func setupPhotoLibraryManager() {
        photoLibraryManager.objectWillChange
            .receive(on: DispatchQueue.main)
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
            isPreparingLibrary = false
            isReloadingLibrary = false
            isRestoringLibrarySnapshot = false
            timeGroups = []
            systemAlbums = []
            userAlbums = []
            hasLoadedAlbums = false
            isLoadingAlbums = false
            isFetchingAlbums = false
            albumLoadingProgress = 0
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
            self.loadTimeGroups()
            _ = self.restoreCachedAlbums()
            self.updateStats()

            self.photoLibraryManager.refreshPhotoLibraryIfNeeded { [weak self] didRefreshLibrary in
                guard let self else { return }
                self.pruneReviewedAssetIDs()
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

    // MARK: - 批量操作（离开页面时执行）
    func executeBatchOperations(completion: @escaping (Bool, Error?) -> Void) {
        guard !deleteCandidates.isEmpty || !favoriteCandidates.isEmpty else {
            completion(true, nil)
            return
        }

        // 检查网络状态和iCloud同步状态
        guard checkSystemReadiness() else {
            let error = NSError(domain: "PhotoDelError", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: L10n.string("系统未准备就绪，请检查网络连接和存储空间")
            ])
            completion(false, error)
            return
        }

        // 保存操作前的状态用于回滚
        let originalDeleteCandidates = deleteCandidates
        let originalFavoriteCandidates = favoriteCandidates

        photoLibraryManager.commitBatchChanges(
            deleteAssets: Array(originalDeleteCandidates),
            favoriteAssets: Array(originalFavoriteCandidates)
        ) { success, error in
            guard success else {
                self.deleteCandidates = originalDeleteCandidates
                self.favoriteCandidates = originalFavoriteCandidates
                self.updateStats()

                let enhancedError = NSError(domain: "PhotoDelError", code: 1002, userInfo: [
                    NSLocalizedDescriptionKey: L10n.string("批量操作失败: \(error?.localizedDescription ?? L10n.string("未知错误"))"),
                    NSLocalizedFailureReasonErrorKey: L10n.string("真实照片库未完成这次批量操作，请稍后重试")
                ])
                completion(false, enhancedError)
                return
            }

            // 操作成功后先做本地增量更新，避免重新跑整库索引。
            self.photoLibraryManager.applyCommittedBatchChanges(
                deletedAssets: Array(originalDeleteCandidates),
                favoritedAssets: Array(originalFavoriteCandidates)
            )
            self.cleanupStatsStore.recordSession(
                deletedPhotos: originalDeleteCandidates.count,
                favoritedPhotos: originalFavoriteCandidates.count,
                organizedPhotos: originalDeleteCandidates.count + originalFavoriteCandidates.count,
                estimatedSpaceSavedMB: Double(originalDeleteCandidates.count) * 3.0
            )
            self.deleteCandidates.removeAll()
            self.favoriteCandidates.removeAll()
            self.refreshDerivedLibraryData()
            completion(true, nil)
        }
    }

    private func refreshDerivedLibraryData() {
        pruneReviewedAssetIDs()
        loadTimeGroups()
        updateStats()
    }

    private func checkSystemReadiness() -> Bool {
        // 检查照片库权限
        guard photoLibraryManager.hasPhotoLibraryAccess else {
            return false
        }

        // 检查存储空间（简化实现）
        let fileManager = FileManager.default
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSpace = systemAttributes[.systemFreeSize] as? NSNumber {
                let freeSpaceInBytes = freeSpace.int64Value
                let minimumRequired: Int64 = 100 * 1024 * 1024 // 100MB
                return freeSpaceInBytes > minimumRequired
            }
        } catch {
            dataManagerLogger.error("Unable to check free disk space: \(error.localizedDescription, privacy: .public)")
        }

        return true
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

    private func scheduleProgressRefresh() {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
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
        case .favorites:
            return photoLibraryManager.favorites
        }
    }

    func getVideosCount() -> Int {
        return photoLibraryManager.videosCount
    }

    // MARK: - 时间组数据加载
    func loadTimeGroups() {
        guard photoLibraryManager.hasPhotoLibraryAccess else { return }
        progressRefreshGeneration += 1

        let result = Self.buildTimeGroupData(
            photos: photoLibraryManager.allPhotos,
            reviewedAssetIDs: reviewedAssetIDs,
            deleteCandidateIDs: Set(deleteCandidates.map(\.localIdentifier)),
            favoriteCandidateIDs: Set(favoriteCandidates.map(\.localIdentifier))
        )
        timeGroupCache = result.cache
        timeGroups = result.timeGroups
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
        guard !validAssetIDs.isEmpty else { return }

        let prunedAssetIDs = reviewedAssetIDs.intersection(validAssetIDs)
        guard prunedAssetIDs.count != reviewedAssetIDs.count else { return }
        reviewedAssetIDs = prunedAssetIDs
        saveReviewedAssetIDsNow()
    }

    private func scheduleLibraryDataRefresh() {
        libraryDataRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.photoLibraryManager.hasPhotoLibraryAccess else { return }
            self.refreshDerivedLibraryData()
            self.loadAlbums(showLoading: false)
        }
        libraryDataRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
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
                .smartAlbumVideos        // 视频
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
        default:
            return .userCreated
        }
    }

    // MARK: - 相册操作
    func getAllAlbums() -> [AlbumInfo] {
        return systemAlbums + userAlbums
    }

    func getSystemAlbums() -> [AlbumInfo] {
        return systemAlbums
    }

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

    func removeUserAlbum(id: String) {
        userAlbums.removeAll { $0.id == id }
        saveAlbumSnapshot()
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
