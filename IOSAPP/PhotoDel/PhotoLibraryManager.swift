import Foundation
import Photos
import PhotosUI
import SwiftUI

class PhotoLibraryManager: NSObject, ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allPhotos: [PHAsset] = []
    @Published var videos: [PHAsset] = []
    @Published var screenshots: [PHAsset] = []
    @Published var favorites: [PHAsset] = []
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0

    private var allPhotosResult: PHFetchResult<PHAsset>?
    private let imageManager = PHCachingImageManager()
    private let imageCache = NSCache<NSString, UIImage>()
    private var pendingLoadCompletions: [() -> Void] = []
    private var localChangeNotificationsRemaining = 0
    private var localChangeResetWorkItem: DispatchWorkItem?

    private var isObserverRegistered = false

    var hasPhotoLibraryAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    override init() {
        super.init()
        // 配置图片缓存
        imageCache.countLimit = 50 // 最多缓存50张图片
        imageCache.totalCostLimit = 100 * 1024 * 1024 // 100MB内存限制

        // 延迟初始化，避免启动时崩溃
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.checkAuthorizationStatus()
            self.registerPhotoLibraryObserver()
        }
    }

    deinit {
        unregisterPhotoLibraryObserver()
    }

    private func registerPhotoLibraryObserver() {
        guard !isObserverRegistered else { return }
        PHPhotoLibrary.shared().register(self)
        isObserverRegistered = true
    }

    private func unregisterPhotoLibraryObserver() {
        guard isObserverRegistered else { return }
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        isObserverRegistered = false
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization(completion: ((PHAuthorizationStatus) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                completion?(status)
            }
        }
    }

    // MARK: - Load Photos

    func loadPhotos(completion: (() -> Void)? = nil) {
        guard hasPhotoLibraryAccess else { return }
        guard !isLoading else {
            if let completion {
                pendingLoadCompletions.append(completion)
            }
            return
        }

        if let completion {
            pendingLoadCompletions.append(completion)
        }
        isLoading = true
        loadingProgress = 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 分页加载照片以避免内存压力
            let batchSize = 500 // 每批加载500张照片

            // 获取所有照片的数量
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let allPhotosResult = PHAsset.fetchAssets(with: fetchOptions)
            DispatchQueue.main.async {
                self.allPhotosResult = allPhotosResult
            }

            let totalCount = allPhotosResult.count
            var allPhotosArray: [PHAsset] = []

            if totalCount == 0 {
                DispatchQueue.main.async {
                    self.allPhotos = []
                    self.videos = []
                    self.screenshots = []
                    self.favorites = []
                    self.loadingProgress = 1.0
                    self.isLoading = false
                    self.finishLoadingPhotos()
                }
                return
            }

            // 分批处理照片
            for batchStart in stride(from: 0, to: totalCount, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, totalCount)
                let batchRange = NSRange(location: batchStart, length: batchEnd - batchStart)

                // 批量获取资产
                var batchAssets: [PHAsset] = []
                allPhotosResult.enumerateObjects(at: IndexSet(integersIn: batchRange.location..<(batchRange.location + batchRange.length))) { asset, _, _ in
                    batchAssets.append(asset)
                }

                allPhotosArray.append(contentsOf: batchAssets)

                // 更新进度
                DispatchQueue.main.async {
                    self.loadingProgress = Double(batchEnd) / Double(totalCount) * 0.6 // 60%用于基础加载
                }

            }

            DispatchQueue.main.async {
                self.loadingProgress = 0.6
            }

            // 异步分类照片，避免阻塞
            self.categorizePhotos(allPhotosArray) { videos, screenshots, favorites in
                DispatchQueue.main.async {
                    self.allPhotos = allPhotosArray
                    self.videos = videos
                    self.screenshots = screenshots
                    self.favorites = favorites
                    self.loadingProgress = 1.0
                    self.isLoading = false
                    self.finishLoadingPhotos()
                }
            }
        }
    }

    private func finishLoadingPhotos() {
        let completions = pendingLoadCompletions
        pendingLoadCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func categorizePhotos(_ photos: [PHAsset], completion: @escaping ([PHAsset], [PHAsset], [PHAsset]) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            var videos: [PHAsset] = []
            var screenshots: [PHAsset] = []

            // 分批处理分类以避免内存压力
            let batchSize = 100
            for batchStart in stride(from: 0, to: photos.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, photos.count)
                let batch = Array(photos[batchStart..<batchEnd])

                for asset in batch {
                    if asset.mediaType == .video {
                        videos.append(asset)
                    } else if self.isScreenshot(asset) {
                        screenshots.append(asset)
                    }
                }

                // 更新进度
                DispatchQueue.main.async {
                    let progress = 0.6 + (Double(batchEnd) / Double(photos.count)) * 0.3 // 30%用于分类
                    self.loadingProgress = progress
                }
            }

            // 获取收藏的照片
            let favoriteOptions = PHFetchOptions()
            favoriteOptions.predicate = NSPredicate(format: "isFavorite == YES")
            favoriteOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let favoritesResult = PHAsset.fetchAssets(with: favoriteOptions)

            var favoritesArray: [PHAsset] = []
            favoritesResult.enumerateObjects { asset, _, _ in
                favoritesArray.append(asset)
            }

            completion(videos, screenshots, favoritesArray)
        }
    }

    // MARK: - Photo Classification

    private func isScreenshot(_ asset: PHAsset) -> Bool {
        // 检查截图的特征
        if #available(iOS 9.0, *) {
            // 通过资源子类型判断
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                return true
            }
        }

        // 备用方法：通过设备尺寸判断
        let screenScale = UIScreen.main.scale
        let screenSize = UIScreen.main.bounds.size
        let assetSize = CGSize(width: CGFloat(asset.pixelWidth), height: CGFloat(asset.pixelHeight))
        let screenLongSide = max(screenSize.width, screenSize.height) * screenScale
        let screenShortSide = min(screenSize.width, screenSize.height) * screenScale
        let assetLongSide = max(assetSize.width, assetSize.height)
        let assetShortSide = min(assetSize.width, assetSize.height)

        // 如果尺寸匹配屏幕尺寸，可能是截图
        return abs(assetLongSide - screenLongSide) < 10 &&
               abs(assetShortSide - screenShortSide) < 10
    }

    // MARK: - Photo Operations

    func deletePhotos(_ assets: [PHAsset], completion: @escaping (Bool, Error?) -> Void) {
        expectLocalLibraryChange()
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    func toggleFavorite(_ asset: PHAsset, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = !asset.isFavorite
        }) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    func addToFavorites(_ assets: [PHAsset], completion: @escaping (Bool, Error?) -> Void) {
        expectLocalLibraryChange()
        PHPhotoLibrary.shared().performChanges({
            for asset in assets {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = true
            }
        }) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    // MARK: - Image Loading

    @discardableResult
    func loadImage(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID? {
        let cacheKey = "\(asset.localIdentifier)_\(Int(size.width))x\(Int(size.height))" as NSString

        // 检查缓存
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        return imageManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            DispatchQueue.main.async {
                // 缓存图片
                if let image = image {
                    let cost = Int(image.size.width * image.size.height * 4) // 估算内存使用
                    self?.imageCache.setObject(image, forKey: cacheKey, cost: cost)
                }
                completion(image)
            }
        }
    }

    @discardableResult
    func loadSwipePreview(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID? {
        let cacheKey = "\(asset.localIdentifier)_swipe_\(Int(size.width))x\(Int(size.height))" as NSString

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false

        return imageManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            DispatchQueue.main.async {
                if let image {
                    let cost = Int(image.size.width * image.size.height * 4)
                    self?.imageCache.setObject(image, forKey: cacheKey, cost: cost)
                }
                completion(image)
            }
        }
    }

    func cancelImageRequest(_ requestID: PHImageRequestID?) {
        guard let requestID else { return }
        imageManager.cancelImageRequest(requestID)
    }

    func clearImageCache() {
        imageCache.removeAllObjects()
    }

    func applyCommittedBatchChanges(deletedAssets: [PHAsset], favoritedAssets: [PHAsset]) {
        let deletedIDs = Set(deletedAssets.map(\.localIdentifier))
        if !deletedIDs.isEmpty {
            removeAssets(with: deletedIDs, from: &allPhotos)
            removeAssets(with: deletedIDs, from: &videos)
            removeAssets(with: deletedIDs, from: &screenshots)
            removeAssets(with: deletedIDs, from: &favorites)
        }

        for asset in favoritedAssets {
            upsertFavorite(asset)
        }

        loadingProgress = 1
        isLoading = false
    }

    func preloadImagesForAssets(_ assets: [PHAsset], size: CGSize, maxCount: Int = 10) {
        // 预加载接下来几张照片以提升用户体验
        let assetsToPreload = Array(assets.prefix(maxCount))
        guard !assetsToPreload.isEmpty else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false

        imageManager.startCachingImages(
            for: assetsToPreload,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        )
    }

    func handleMemoryWarning() {
        // 清理一半的缓存
        let currentCount = imageCache.countLimit
        imageCache.countLimit = currentCount / 2

        // 重置缓存限制
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.imageCache.countLimit = currentCount
        }
    }

    func loadThumbnail(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        loadImage(for: asset, size: CGSize(width: 150, height: 150), completion: completion)
    }

    func loadFullImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false

        imageManager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    private func expectLocalLibraryChange() {
        let updateCounter = { [weak self] in
            guard let self else { return }
            self.localChangeNotificationsRemaining += 1
            self.localChangeResetWorkItem?.cancel()

            let resetWorkItem = DispatchWorkItem { [weak self] in
                self?.localChangeNotificationsRemaining = 0
            }
            self.localChangeResetWorkItem = resetWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: resetWorkItem)
        }

        if Thread.isMainThread {
            updateCounter()
        } else {
            DispatchQueue.main.async {
                updateCounter()
            }
        }
    }

    private func shouldApplyChangeIncrementally() -> Bool {
        guard localChangeNotificationsRemaining > 0 else { return false }
        localChangeNotificationsRemaining -= 1
        if localChangeNotificationsRemaining == 0 {
            localChangeResetWorkItem?.cancel()
            localChangeResetWorkItem = nil
        }
        return true
    }

    private func applyIncrementalPhotoChanges(_ changes: PHFetchResultChangeDetails<PHAsset>) {
        guard changes.hasIncrementalChanges else {
            rebuildCachedAssets(from: changes.fetchResultAfterChanges)
            return
        }

        let removedIDs = Set(changes.removedObjects.map(\.localIdentifier))
        if !removedIDs.isEmpty {
            removeAssets(with: removedIDs, from: &allPhotos)
            removeAssets(with: removedIDs, from: &videos)
            removeAssets(with: removedIDs, from: &screenshots)
            removeAssets(with: removedIDs, from: &favorites)
        }

        for changedAsset in changes.changedObjects {
            replaceAsset(changedAsset, in: &allPhotos)
            replaceAsset(changedAsset, in: &videos)
            replaceAsset(changedAsset, in: &screenshots)

            if changedAsset.isFavorite {
                upsertFavorite(changedAsset)
            } else {
                favorites.removeAll { $0.localIdentifier == changedAsset.localIdentifier }
            }
        }

        for insertedAsset in changes.insertedObjects {
            upsertPhotoAsset(insertedAsset)
        }

        loadingProgress = 1
        isLoading = false
        finishLoadingPhotos()
    }

    private func rebuildCachedAssets(from fetchResult: PHFetchResult<PHAsset>) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            var photos: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                photos.append(asset)
            }

            self.categorizePhotos(photos) { videos, screenshots, favorites in
                DispatchQueue.main.async {
                    self.allPhotos = photos
                    self.videos = videos
                    self.screenshots = screenshots
                    self.favorites = favorites
                    self.loadingProgress = 1
                    self.isLoading = false
                    self.finishLoadingPhotos()
                }
            }
        }
    }

    private func removeAssets(with identifiers: Set<String>, from assets: inout [PHAsset]) {
        assets.removeAll { identifiers.contains($0.localIdentifier) }
    }

    private func replaceAsset(_ asset: PHAsset, in assets: inout [PHAsset]) {
        guard let index = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else { return }
        assets[index] = asset
    }

    private func upsertPhotoAsset(_ asset: PHAsset) {
        upsertAsset(asset, in: &allPhotos)

        if asset.mediaType == .video {
            upsertAsset(asset, in: &videos)
        } else {
            videos.removeAll { $0.localIdentifier == asset.localIdentifier }
        }

        if isScreenshot(asset) {
            upsertAsset(asset, in: &screenshots)
        } else {
            screenshots.removeAll { $0.localIdentifier == asset.localIdentifier }
        }

        if asset.isFavorite {
            upsertFavorite(asset)
        } else {
            favorites.removeAll { $0.localIdentifier == asset.localIdentifier }
        }
    }

    private func upsertAsset(_ asset: PHAsset, in assets: inout [PHAsset]) {
        if let index = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            assets[index] = asset
            return
        }

        let assetDate = asset.creationDate ?? .distantPast
        let insertionIndex = assets.firstIndex { existingAsset in
            (existingAsset.creationDate ?? .distantPast) < assetDate
        } ?? assets.endIndex
        assets.insert(asset, at: insertionIndex)
    }

    private func upsertFavorite(_ asset: PHAsset) {
        if let index = favorites.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            favorites[index] = asset
        } else {
            favorites.insert(asset, at: 0)
        }
    }

    // MARK: - Albums

    func createAlbum(title: String, completion: @escaping (PHAssetCollection?, Error?) -> Void) {
        var albumPlaceholder: PHObjectPlaceholder?

        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            albumPlaceholder = request.placeholderForCreatedAssetCollection
        }) { success, error in
            DispatchQueue.main.async {
                if success, let placeholder = albumPlaceholder {
                    let album = PHAssetCollection.fetchAssetCollections(
                        withLocalIdentifiers: [placeholder.localIdentifier],
                        options: nil
                    ).firstObject
                    completion(album, nil)
                } else {
                    completion(nil, error)
                }
            }
        }
    }

    func addPhotosToAlbum(_ assets: [PHAsset], album: PHAssetCollection, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            if let addAssetRequest = PHAssetCollectionChangeRequest(for: album) {
                addAssetRequest.addAssets(assets as NSArray)
            }
        }) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    // MARK: - Statistics

    var totalPhotosCount: Int { allPhotos.count }
    var videosCount: Int { videos.count }
    var screenshotsCount: Int { screenshots.count }
    var favoritesCount: Int { favorites.count }

    func getTotalSizeOfPhotos(_ assets: [PHAsset]) -> Int64 {
        // 这是一个估算，实际大小需要异步获取
        return Int64(assets.count) * 3_000_000 // 平均3MB每张照片
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension PhotoLibraryManager: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let fetchResult = self.allPhotosResult,
                  let changes = changeInstance.changeDetails(for: fetchResult) else {
                return
            }

            self.allPhotosResult = changes.fetchResultAfterChanges

            if self.shouldApplyChangeIncrementally() {
                self.applyIncrementalPhotoChanges(changes)
            } else {
                self.rebuildCachedAssets(from: changes.fetchResultAfterChanges)
            }
        }
    }
}
