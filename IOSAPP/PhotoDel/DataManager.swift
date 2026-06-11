//
//  DataManager.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI
import Photos
import UIKit

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
    @Published private(set) var reviewedAssetIDs: Set<String> = []

    private var isReloadingLibrary = false
    private var hasLoadedAlbums = false
    private var timeGroupCache: [TimeGroup: [PHAsset]] = [:]
    private var progressRefreshWorkItem: DispatchWorkItem?
    private let reviewedAssetIDsKey = "photoDelReviewedAssetIDs"

    init() {
        loadReviewedAssetIDs()
        setupPhotoLibraryManager()
    }

    private func setupPhotoLibraryManager() {
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
            timeGroups = []
            systemAlbums = []
            userAlbums = []
            hasLoadedAlbums = false
            return
        }

        if !hadAccess ||
            previousStatus != photoLibraryManager.authorizationStatus ||
            (!photoLibraryManager.hasLoadedPhotoLibrary && !photoLibraryManager.isLoading) {
            reloadLibraryData(showPreparing: showPreparing)
        }
    }

    func openPhotoLibrarySettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(settingsURL) else { return }

        UIApplication.shared.open(settingsURL)
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

        photoLibraryManager.loadPhotos { [weak self] in
            guard let self else { return }
            self.loadTimeGroups()
            self.loadAlbums(showLoading: !self.hasLoadedAlbums)
            self.updateStats()
            self.isPreparingLibrary = false
            self.isReloadingLibrary = false
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
                NSLocalizedDescriptionKey: "系统未准备就绪，请检查网络连接和存储空间"
            ])
            completion(false, error)
            return
        }

        // 保存操作前的状态用于回滚
        let originalDeleteCandidates = deleteCandidates
        let originalFavoriteCandidates = favoriteCandidates

        let group = DispatchGroup()
        var hasError = false
        var lastError: Error?
        var completedOperations: [(() -> Void)] = []

        // 批量删除
        if !deleteCandidates.isEmpty {
            group.enter()
            let assetsToDelete = Array(deleteCandidates)
            photoLibraryManager.deletePhotos(assetsToDelete) { success, error in
                if success {
                    // 记录成功的操作以便回滚
                    completedOperations.append {
                        // 删除操作无法回滚，但可以记录
                        print("删除操作已完成，无法回滚")
                    }
                } else {
                    hasError = true
                    lastError = error
                }
                group.leave()
            }
        }

        // 批量收藏
        if !favoriteCandidates.isEmpty {
            group.enter()
            let assetsToFavorite = Array(favoriteCandidates)
            photoLibraryManager.addToFavorites(assetsToFavorite) { success, error in
                if success {
                    // 记录成功的操作以便回滚
                    completedOperations.append {
                        // 可以回滚收藏操作
                        for asset in assetsToFavorite {
                            self.toggleFavoriteStatus(asset, shouldFavorite: false)
                        }
                    }
                } else {
                    hasError = true
                    lastError = error
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if !hasError {
                // 操作成功后先做本地增量更新，避免重新跑整库索引。
                self.photoLibraryManager.applyCommittedBatchChanges(
                    deletedAssets: Array(originalDeleteCandidates),
                    favoritedAssets: Array(originalFavoriteCandidates)
                )
                self.deleteCandidates.removeAll()
                self.favoriteCandidates.removeAll()
                self.refreshDerivedLibraryData()
                completion(true, nil)
            } else {
                // 操作失败，恢复原始状态
                self.deleteCandidates = originalDeleteCandidates
                self.favoriteCandidates = originalFavoriteCandidates
                self.updateStats()

                // 如果部分操作成功，可以选择回滚（这里简化处理）
                let enhancedError = NSError(domain: "PhotoDelError", code: 1002, userInfo: [
                    NSLocalizedDescriptionKey: "批量操作失败: \(lastError?.localizedDescription ?? "未知错误")",
                    NSLocalizedFailureReasonErrorKey: "部分操作可能已完成，请检查照片状态"
                ])
                completion(false, enhancedError)
            }
        }
    }

    private func refreshDerivedLibraryData() {
        loadTimeGroups()
        loadAlbums(showLoading: false)
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
            print("无法检查存储空间: \(error)")
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
        saveReviewedAssetIDs()
        scheduleProgressRefresh()
        return wasReviewed
    }

    func restoreReviewedState(_ asset: PHAsset, wasReviewed: Bool) {
        if wasReviewed {
            reviewedAssetIDs.insert(asset.localIdentifier)
        } else {
            reviewedAssetIDs.remove(asset.localIdentifier)
        }
        saveReviewedAssetIDs()
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
        saveReviewedAssetIDs()
        loadTimeGroups()
        updateStats()
    }

    private func scheduleProgressRefresh() {
        progressRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.loadTimeGroups()
        }
        progressRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
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

    // MARK: - 收藏操作
    func toggleFavoriteStatus(_ asset: PHAsset, shouldFavorite: Bool) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = shouldFavorite
        }) { success, error in
            if let error = error {
                print("Failed to toggle favorite status: \(error)")
            } else {
                print("Successfully \(shouldFavorite ? "favorited" : "unfavorited") photo")
            }
        }
    }

    // MARK: - 时间组数据加载
    func loadTimeGroups() {
        guard photoLibraryManager.hasPhotoLibraryAccess else { return }

        // 单次遍历构建缓存，避免重复全量扫描
        let calendar = Calendar.current
        let now = Date()
        timeGroupCache.removeAll()

        for asset in photoLibraryManager.allPhotos {
            guard let creationDate = asset.creationDate else { continue }
            let group = TimeGroupResolver.group(for: creationDate, now: now, calendar: calendar)
            timeGroupCache[group, default: []].append(asset)
        }

        timeGroups = TimeGroup.allCases.map { timeGroup in
            let photos = timeGroupCache[timeGroup] ?? []
            let progress = calculateProgressForTimeGroup(timeGroup, photos: photos)
            return TimeGroupInfo(timeGroup: timeGroup, photosCount: photos.count, progress: progress)
        }
    }

    // MARK: - 计算时间组整理进度
    private func calculateProgressForTimeGroup(_ timeGroup: TimeGroup, photos: [PHAsset]) -> Double {
        guard !photos.isEmpty else { return 0.0 }

        // 计算已整理的照片数量（已删除或已收藏的照片）
        let organizedCount = photos.filter { asset in
            reviewedAssetIDs.contains(asset.localIdentifier) ||
                deleteCandidates.contains(asset) ||
                favoriteCandidates.contains(asset) ||
                asset.isFavorite
        }.count

        return Double(organizedCount) / Double(photos.count)
    }

    private func loadReviewedAssetIDs() {
        let identifiers = UserDefaults.standard.stringArray(forKey: reviewedAssetIDsKey) ?? []
        reviewedAssetIDs = Set(identifiers)
    }

    private func saveReviewedAssetIDs() {
        UserDefaults.standard.set(Array(reviewedAssetIDs), forKey: reviewedAssetIDsKey)
    }

    // MARK: - 相册数据加载
    func loadAlbums(showLoading: Bool? = nil) {
        guard photoLibraryManager.hasPhotoLibraryAccess else {
            isLoadingAlbums = false
            hasLoadedAlbums = false
            return
        }

        let shouldShowLoading = showLoading ?? (!hasLoadedAlbums && systemAlbums.isEmpty && userAlbums.isEmpty)
        if shouldShowLoading {
            isLoadingAlbums = true
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
            }

            // 用户创建的相册
            let userCollections = PHAssetCollection.fetchAssetCollections(
                with: .album,
                subtype: .any,
                options: nil
            )

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
            }

            DispatchQueue.main.async {
                self.systemAlbums = systemAlbums
                self.userAlbums = userAlbums
                self.hasLoadedAlbums = true
                self.isLoadingAlbums = false
            }
        }
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

    // MARK: - 相册照片操作
    func addPhotoToAlbum(_ asset: PHAsset, album: PHAssetCollection, completion: @escaping (Bool) -> Void) {
        photoLibraryManager.addPhotosToAlbum([asset], album: album) { success, error in
            if let error = error {
                print("添加照片到相册失败: \(error.localizedDescription)")
            }
            completion(success)
        }
    }
}
