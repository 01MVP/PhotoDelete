import Foundation
import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

class PhotoLibraryManager: NSObject, ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allPhotos: [PHAsset] = []
    @Published var videos: [PHAsset] = []
    @Published var screenshots: [PHAsset] = []
    @Published var livePhotos: [PHAsset] = []
    @Published var favorites: [PHAsset] = []
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published private(set) var hasLoadedPhotoLibrary = false

    private var allPhotosResult: PHFetchResult<PHAsset>?
    private let imageManager = PHCachingImageManager()
    private let imageCache = NSCache<NSString, UIImage>()
    private let snapshotStore = PhotoLibrarySnapshotStore()
    private var pendingLoadCompletions: [() -> Void] = []
    private var localChangeNotificationsRemaining = 0
    private var localChangeResetWorkItem: DispatchWorkItem?
    private var isRestoringSnapshot = false

    private var isObserverRegistered = false
    var onLibraryDataChanged: (() -> Void)?

    var hasPhotoLibraryAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    var hasLimitedPhotoLibraryAccess: Bool {
        authorizationStatus == .limited
    }

    var hasCachedPhotoLibrarySnapshot: Bool {
        snapshotStore.hasSnapshot
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

    func presentLimitedLibraryPicker() {
        guard hasLimitedPhotoLibraryAccess,
              let presentingViewController = UIApplication.shared.topMostViewController else {
            return
        }

        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presentingViewController)
    }

    // MARK: - Load Photos

    func restoreCachedPhotoLibrary(completion: @escaping (Bool) -> Void) {
        guard hasPhotoLibraryAccess, !isLoading, !isRestoringSnapshot else {
            completion(false)
            return
        }

        guard let snapshot = snapshotStore.load() else {
            completion(false)
            return
        }

        isRestoringSnapshot = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let restoredAssets = self.fetchAssetsPreservingOrder(snapshot.allPhotoIDs)
            let assetByID = Dictionary(uniqueKeysWithValues: restoredAssets.map { ($0.localIdentifier, $0) })
            let restoredVideos = snapshot.videoIDs.compactMap { assetByID[$0] }
            let restoredScreenshots = snapshot.screenshotIDs.compactMap { assetByID[$0] }
            let restoredLivePhotos = snapshot.livePhotoIDs.compactMap { assetByID[$0] }
            let restoredFavorites = snapshot.favoriteIDs.compactMap { assetByID[$0] }
            let fetchResult = PHAsset.fetchAssets(with: self.defaultPhotoFetchOptions())

            DispatchQueue.main.async {
                self.allPhotosResult = fetchResult
                self.allPhotos = restoredAssets
                self.videos = restoredVideos
                self.screenshots = restoredScreenshots
                self.livePhotos = restoredLivePhotos
                self.favorites = restoredFavorites
                self.loadingProgress = 1
                self.isLoading = false
                self.hasLoadedPhotoLibrary = true
                self.isRestoringSnapshot = false
                completion(!restoredAssets.isEmpty || snapshot.allPhotoIDs.isEmpty)
            }
        }
    }

    func refreshPhotoLibraryIfNeeded(completion: ((Bool) -> Void)? = nil) {
        guard hasPhotoLibraryAccess, hasLoadedPhotoLibrary, !isLoading else {
            completion?(false)
            return
        }

        let currentAllPhotoIDs = allPhotos.map(\.localIdentifier)
        let currentVideoIDs = videos.map(\.localIdentifier)
        let currentFavoriteIDs = favorites.map(\.localIdentifier)
        let currentScreenshotIDs = screenshots.map(\.localIdentifier)
        let currentLivePhotoIDs = livePhotos.map(\.localIdentifier)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let identifiersChanged =
                self.assetIdentifiers(from: PHAsset.fetchAssets(with: self.defaultPhotoFetchOptions())) != currentAllPhotoIDs ||
                self.assetIdentifiers(from: self.fetchAssets(mediaType: .video)) != currentVideoIDs ||
                self.assetIdentifiers(from: self.fetchFavoriteAssets()) != currentFavoriteIDs ||
                self.assetIdentifiers(from: self.fetchSmartAlbumAssets(.smartAlbumScreenshots)) != currentScreenshotIDs ||
                self.assetIdentifiers(from: self.fetchSmartAlbumAssets(.smartAlbumLivePhotos)) != currentLivePhotoIDs

            DispatchQueue.main.async {
                if identifiersChanged {
                    self.loadPhotos(preserveExistingData: true) {
                        completion?(true)
                    }
                } else {
                    completion?(false)
                }
            }
        }
    }

    func loadPhotos(preserveExistingData: Bool = false, completion: (() -> Void)? = nil) {
        guard hasPhotoLibraryAccess else {
            completion?()
            return
        }
        guard !isLoading else {
            if let completion {
                pendingLoadCompletions.append(completion)
            }
            return
        }

        if let completion {
            pendingLoadCompletions.append(completion)
        }
        let shouldPreserveExistingData = preserveExistingData && hasLoadedPhotoLibrary && !allPhotos.isEmpty
        isLoading = true
        if shouldPreserveExistingData {
            loadingProgress = max(loadingProgress, 0.05)
        } else {
            hasLoadedPhotoLibrary = false
            loadingProgress = 0
        }

        let screenPixelSize = Self.currentScreenPixelSize()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 分页加载照片以避免内存压力
            let batchSize = 500 // 每批加载500张照片

            // 获取所有照片的数量
            let fetchOptions = self.defaultPhotoFetchOptions()

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
                    self.livePhotos = []
                    self.favorites = []
                    self.loadingProgress = 1.0
                    self.isLoading = false
                    self.hasLoadedPhotoLibrary = true
                    self.saveSnapshot(allPhotos: [], videos: [], screenshots: [], livePhotos: [], favorites: [])
                    self.finishLoadingPhotos()
                    self.onLibraryDataChanged?()
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
            self.categorizePhotos(allPhotosArray, screenPixelSize: screenPixelSize) { videos, screenshots, livePhotos, favorites in
                DispatchQueue.main.async {
                    self.allPhotos = allPhotosArray
                    self.videos = videos
                    self.screenshots = screenshots
                    self.livePhotos = livePhotos
                    self.favorites = favorites
                    self.loadingProgress = 1.0
                    self.isLoading = false
                    self.hasLoadedPhotoLibrary = true
                    self.saveSnapshot(
                        allPhotos: allPhotosArray,
                        videos: videos,
                        screenshots: screenshots,
                        livePhotos: livePhotos,
                        favorites: favorites
                    )
                    self.finishLoadingPhotos()
                    self.onLibraryDataChanged?()
                }
            }
        }
    }

    private func finishLoadingPhotos() {
        let completions = pendingLoadCompletions
        pendingLoadCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func categorizePhotos(
        _ photos: [PHAsset],
        screenPixelSize: CGSize,
        completion: @escaping ([PHAsset], [PHAsset], [PHAsset], [PHAsset]) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            var videos: [PHAsset] = []
            var screenshots: [PHAsset] = []
            var livePhotos: [PHAsset] = []

            // 分批处理分类以避免内存压力
            let batchSize = 100
            for batchStart in stride(from: 0, to: photos.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, photos.count)
                let batch = Array(photos[batchStart..<batchEnd])

                for asset in batch {
                    if asset.mediaType == .video {
                        videos.append(asset)
                    } else if self.isScreenshot(asset, screenPixelSize: screenPixelSize) {
                        screenshots.append(asset)
                    }

                    if self.isLivePhoto(asset) {
                        livePhotos.append(asset)
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

            completion(videos, screenshots, livePhotos, favoritesArray)
        }
    }

    // MARK: - Photo Classification

    func isScreenshot(_ asset: PHAsset) -> Bool {
        isScreenshot(asset, screenPixelSize: Self.currentScreenPixelSize())
    }

    func isLivePhoto(_ asset: PHAsset) -> Bool {
        asset.mediaType == .image && asset.mediaSubtypes.contains(.photoLive)
    }

    private func isScreenshot(_ asset: PHAsset, screenPixelSize: CGSize) -> Bool {
        // 检查截图的特征
        if #available(iOS 9.0, *) {
            // 通过资源子类型判断
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                return true
            }
        }

        // 备用方法：通过设备尺寸判断
        let assetSize = CGSize(width: CGFloat(asset.pixelWidth), height: CGFloat(asset.pixelHeight))
        let screenLongSide = max(screenPixelSize.width, screenPixelSize.height)
        let screenShortSide = min(screenPixelSize.width, screenPixelSize.height)
        let assetLongSide = max(assetSize.width, assetSize.height)
        let assetShortSide = min(assetSize.width, assetSize.height)

        // 如果尺寸匹配屏幕尺寸，可能是截图
        return abs(assetLongSide - screenLongSide) < 10 &&
               abs(assetShortSide - screenShortSide) < 10
    }

    // MARK: - Photo Operations

    func commitBatchChanges(deleteAssets: [PHAsset], favoriteAssets: [PHAsset], completion: @escaping (Bool, Error?) -> Void) {
        guard hasPhotoLibraryAccess else {
            completion(false, PhotoLibraryWriteError.noLibraryAccess)
            return
        }

        let uniqueDeleteAssets = uniqueAssets(deleteAssets)
        let deletedIDs = Set(uniqueDeleteAssets.map(\.localIdentifier))
        let uniqueFavoriteAssets = uniqueAssets(favoriteAssets)
            .filter { !deletedIDs.contains($0.localIdentifier) }

        guard uniqueDeleteAssets.allSatisfy({ $0.canPerform(.delete) }) else {
            completion(false, PhotoLibraryWriteError.unsupportedDelete)
            return
        }

        guard uniqueFavoriteAssets.allSatisfy({ $0.canPerform(.properties) }) else {
            completion(false, PhotoLibraryWriteError.unsupportedFavorite)
            return
        }

        expectLocalLibraryChange()
        PHPhotoLibrary.shared().performChanges({
            if !uniqueDeleteAssets.isEmpty {
                PHAssetChangeRequest.deleteAssets(uniqueDeleteAssets as NSArray)
            }

            for asset in uniqueFavoriteAssets {
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
        let cacheKey = imageCacheKey(for: asset, purpose: "image", size: size)

        // 检查缓存
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return imageManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            DispatchQueue.main.async {
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                guard !isCancelled else { return }

                // 缓存图片
                if let image = image {
                    self?.cacheImage(image, forKey: cacheKey, isDegraded: isDegraded)
                } else if isInCloud {
                    return
                }
                completion(image)
            }
        }
    }

    @discardableResult
    func loadSwipePreview(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID? {
        let cacheKey = imageCacheKey(for: asset, purpose: "swipe", size: size)

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return imageManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            DispatchQueue.main.async {
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                guard !isCancelled else { return }

                if let image {
                    self?.cacheImage(image, forKey: cacheKey, isDegraded: isDegraded)
                } else if isInCloud {
                    return
                }
                completion(image)
            }
        }
    }

    @discardableResult
    func loadHighQualityPreview(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID? {
        let cacheKey = imageCacheKey(for: asset, purpose: "hq", size: size)

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return imageManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            DispatchQueue.main.async {
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                let error = info?[PHImageErrorKey] as? Error
                guard !isCancelled else { return }

                if let image {
                    self?.cacheImage(image, forKey: cacheKey, isDegraded: isDegraded)
                    completion(image)
                } else if isInCloud && error == nil {
                    return
                } else {
                    completion(nil)
                }
            }
        }
    }

    @discardableResult
    func loadBrowserPreview(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID? {
        let cacheKey = imageCacheKey(for: asset, purpose: "browser", size: size)

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return imageManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            DispatchQueue.main.async {
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                let error = info?[PHImageErrorKey] as? Error
                guard !isCancelled else { return }

                if let image, !isDegraded {
                    self?.cacheImage(image, forKey: cacheKey, isDegraded: false)
                    completion(image)
                } else if isInCloud && error == nil {
                    return
                } else if image == nil {
                    completion(nil)
                }
            }
        }
    }

    func cancelImageRequest(_ requestID: PHImageRequestID?) {
        guard let requestID else { return }
        imageManager.cancelImageRequest(requestID)
    }

    @discardableResult
    func loadPlayerItem(for asset: PHAsset, completion: @escaping (AVPlayerItem?) -> Void) -> PHImageRequestID? {
        guard asset.mediaType == .video else {
            completion(nil)
            return nil
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        return imageManager.requestPlayerItem(forVideo: asset, options: options) { playerItem, info in
            DispatchQueue.main.async {
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                guard !isCancelled else { return }
                completion(playerItem)
            }
        }
    }

    func applyCommittedBatchChanges(deletedAssets: [PHAsset], favoritedAssets: [PHAsset]) {
        let deletedIDs = Set(deletedAssets.map(\.localIdentifier))
        if !deletedIDs.isEmpty {
            removeAssets(with: deletedIDs, from: &allPhotos)
            removeAssets(with: deletedIDs, from: &videos)
            removeAssets(with: deletedIDs, from: &screenshots)
            removeAssets(with: deletedIDs, from: &livePhotos)
            removeAssets(with: deletedIDs, from: &favorites)
            imageCache.removeAllObjects()
        }

        for asset in favoritedAssets {
            upsertFavorite(asset)
        }

        loadingProgress = 1
        isLoading = false
        hasLoadedPhotoLibrary = true
        saveSnapshot(allPhotos: allPhotos, videos: videos, screenshots: screenshots, livePhotos: livePhotos, favorites: favorites)
        onLibraryDataChanged?()
    }

    func preloadImagesForAssets(_ assets: [PHAsset], size: CGSize, maxCount: Int = 10) {
        // 预加载接下来几张照片以提升用户体验
        let assetsToPreload = Array(assets.prefix(maxCount))
        guard !assetsToPreload.isEmpty else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true

        imageManager.startCachingImages(
            for: assetsToPreload,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        )
    }

    func preloadGridThumbnailsForAssets(_ assets: [PHAsset], size: CGSize, maxCount: Int = 30) {
        let assetsToPreload = Array(assets.prefix(maxCount))
        guard !assetsToPreload.isEmpty else { return }

        imageManager.startCachingImages(
            for: assetsToPreload,
            targetSize: size,
            contentMode: .aspectFill,
            options: makeGridThumbnailOptions()
        )
    }

    func handleMemoryWarning() {
        imageCache.removeAllObjects()
        imageManager.stopCachingImagesForAllAssets()
    }

    func stopCachingImages(_ assets: [PHAsset], size: CGSize) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        imageManager.stopCachingImages(for: assets, targetSize: size, contentMode: .aspectFit, options: options)
    }

    func stopCachingGridThumbnails(_ assets: [PHAsset], size: CGSize) {
        guard !assets.isEmpty else { return }
        imageManager.stopCachingImages(
            for: assets,
            targetSize: size,
            contentMode: .aspectFill,
            options: makeGridThumbnailOptions()
        )
    }

    @discardableResult
    func loadFastThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID? {
        let cacheKey = imageCacheKey(for: asset, purpose: "thumb", size: size)

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return imageManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            DispatchQueue.main.async {
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                guard !isCancelled else { return }

                if let image {
                    self?.cacheImage(image, forKey: cacheKey, isDegraded: isDegraded)
                } else if isInCloud {
                    return
                }
                completion(image)
            }
        }
    }

    @discardableResult
    func loadGridThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID? {
        let cacheKey = imageCacheKey(for: asset, purpose: "grid", size: size)

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return nil
        }

        let options = makeGridThumbnailOptions()

        return imageManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            DispatchQueue.main.async {
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                guard !isCancelled else { return }

                if let image {
                    self?.cacheImage(image, forKey: cacheKey, isDegraded: isDegraded)
                }
                completion(image)
            }
        }
    }

    private func makeGridThumbnailOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        return options
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
        guard changes.hasIncrementalChanges, !changes.hasMoves else {
            rebuildCachedAssets(from: changes.fetchResultAfterChanges)
            return
        }

        let removedIDs = Set(changes.removedObjects.map(\.localIdentifier))
        if !removedIDs.isEmpty {
            removeAssets(with: removedIDs, from: &allPhotos)
            removeAssets(with: removedIDs, from: &videos)
            removeAssets(with: removedIDs, from: &screenshots)
            removeAssets(with: removedIDs, from: &livePhotos)
            removeAssets(with: removedIDs, from: &favorites)
        }

        if !removedIDs.isEmpty || !changes.changedObjects.isEmpty {
            imageCache.removeAllObjects()
        }

        for changedAsset in changes.changedObjects {
            upsertPhotoAsset(changedAsset)
        }

        for insertedAsset in changes.insertedObjects {
            upsertPhotoAsset(insertedAsset)
        }

        loadingProgress = 1
        isLoading = false
        hasLoadedPhotoLibrary = true
        saveSnapshot(allPhotos: allPhotos, videos: videos, screenshots: screenshots, livePhotos: livePhotos, favorites: favorites)
        finishLoadingPhotos()
        onLibraryDataChanged?()
    }

    private func rebuildCachedAssets(from fetchResult: PHFetchResult<PHAsset>) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            var photos: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                photos.append(asset)
            }

            let screenPixelSize = Self.currentScreenPixelSize()
            self.categorizePhotos(photos, screenPixelSize: screenPixelSize) { videos, screenshots, livePhotos, favorites in
                DispatchQueue.main.async {
                    self.allPhotos = photos
                    self.videos = videos
                    self.screenshots = screenshots
                    self.livePhotos = livePhotos
                    self.favorites = favorites
                    self.loadingProgress = 1
                    self.isLoading = false
                    self.hasLoadedPhotoLibrary = true
                    self.saveSnapshot(allPhotos: photos, videos: videos, screenshots: screenshots, livePhotos: livePhotos, favorites: favorites)
                    self.finishLoadingPhotos()
                    self.onLibraryDataChanged?()
                }
            }
        }
    }

    private func removeAssets(with identifiers: Set<String>, from assets: inout [PHAsset]) {
        assets.removeAll { identifiers.contains($0.localIdentifier) }
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

        if isLivePhoto(asset) {
            upsertAsset(asset, in: &livePhotos)
        } else {
            livePhotos.removeAll { $0.localIdentifier == asset.localIdentifier }
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
        upsertAsset(asset, in: &favorites)
    }

    private func cacheImage(_ image: UIImage, forKey cacheKey: NSString, isDegraded: Bool) {
        guard !isDegraded else { return }
        let cost: Int
        if let cgImage = image.cgImage {
            cost = cgImage.bytesPerRow * cgImage.height
        } else {
            cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        }
        imageCache.setObject(image, forKey: cacheKey, cost: cost)
    }

    private func imageCacheKey(for asset: PHAsset, purpose: String, size: CGSize) -> NSString {
        let modifiedAt = Int((asset.modificationDate ?? asset.creationDate ?? .distantPast).timeIntervalSinceReferenceDate)
        return "\(purpose)_\(asset.localIdentifier)_\(asset.pixelWidth)x\(asset.pixelHeight)_\(modifiedAt)_\(Int(size.width))x\(Int(size.height))" as NSString
    }

    private func defaultPhotoFetchOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return fetchOptions
    }

    private func fetchAssetsPreservingOrder(_ identifiers: [String]) -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assetsByID: [String: PHAsset] = [:]
        assetsByID.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assetsByID[asset.localIdentifier] = asset
        }
        return identifiers.compactMap { assetsByID[$0] }
    }

    private func fetchAssets(mediaType: PHAssetMediaType) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", mediaType.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: options)
    }

    private func fetchFavoriteAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "isFavorite == YES")
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: options)
    }

    private func fetchSmartAlbumAssets(_ subtype: PHAssetCollectionSubtype) -> PHFetchResult<PHAsset> {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: subtype,
            options: nil
        )
        guard let collection = collections.firstObject else {
            return PHAsset.fetchAssets(withLocalIdentifiers: [], options: nil)
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(in: collection, options: options)
    }

    private func assetIdentifiers(from fetchResult: PHFetchResult<PHAsset>) -> [String] {
        var identifiers: [String] = []
        identifiers.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            identifiers.append(asset.localIdentifier)
        }
        return identifiers
    }

    private func saveSnapshot(allPhotos: [PHAsset], videos: [PHAsset], screenshots: [PHAsset], livePhotos: [PHAsset], favorites: [PHAsset]) {
        let store = snapshotStore
        let createdAt = Date()
        DispatchQueue.global(qos: .utility).async {
            let snapshot = PhotoLibrarySnapshot(
                createdAt: createdAt,
                allPhotoIDs: allPhotos.map(\.localIdentifier),
                videoIDs: videos.map(\.localIdentifier),
                screenshotIDs: screenshots.map(\.localIdentifier),
                livePhotoIDs: livePhotos.map(\.localIdentifier),
                favoriteIDs: favorites.map(\.localIdentifier)
            )
            store.save(snapshot)
        }
    }

    // MARK: - Albums

    func addPhotosToAlbum(_ assets: [PHAsset], album: PHAssetCollection, completion: @escaping (Bool, Error?) -> Void) {
        guard hasPhotoLibraryAccess else {
            completion(false, PhotoLibraryWriteError.noLibraryAccess)
            return
        }

        guard album.canPerform(.addContent) else {
            completion(false, PhotoLibraryWriteError.unsupportedAlbumAdd)
            return
        }

        let uniqueAssets = uniqueAssets(assets)
        guard !uniqueAssets.isEmpty else {
            completion(true, nil)
            return
        }

        PHPhotoLibrary.shared().performChanges({
            if let addAssetRequest = PHAssetCollectionChangeRequest(for: album) {
                addAssetRequest.addAssets(uniqueAssets as NSArray)
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
    var livePhotosCount: Int { livePhotos.count }
    var favoritesCount: Int { favorites.count }

    private func uniqueAssets(_ assets: [PHAsset]) -> [PHAsset] {
        var seenIdentifiers = Set<String>()
        return assets.filter { asset in
            seenIdentifiers.insert(asset.localIdentifier).inserted
        }
    }

}

private enum PhotoLibraryWriteError: LocalizedError {
    case noLibraryAccess
    case unsupportedDelete
    case unsupportedFavorite
    case unsupportedAlbumAdd

    var errorDescription: String? {
        switch self {
        case .noLibraryAccess:
            return L10n.string("当前照片权限不可用")
        case .unsupportedDelete:
            return L10n.string("有照片无法删除，请先在系统照片中检查权限或来源。")
        case .unsupportedFavorite:
            return L10n.string("有照片无法收藏，请先在系统照片中检查权限或来源。")
        case .unsupportedAlbumAdd:
            return L10n.string("这个相册不支持添加照片。")
        }
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

private extension PhotoLibraryManager {
    static func currentScreenPixelSize() -> CGSize {
        if Thread.isMainThread {
            return readCurrentScreenPixelSize()
        }

        var pixelSize = CGSize(width: 390 * 3, height: 844 * 3)
        DispatchQueue.main.sync {
            pixelSize = readCurrentScreenPixelSize()
        }
        return pixelSize
    }

    static func readCurrentScreenPixelSize() -> CGSize {
        let screen = UIScreen.main
        return CGSize(
            width: screen.bounds.width * screen.scale,
            height: screen.bounds.height * screen.scale
        )
    }
}

private extension UIApplication {
    var topMostViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMostPresentedViewController
    }
}

private extension UIViewController {
    var topMostPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostPresentedViewController
        }

        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.topMostPresentedViewController
        }

        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.topMostPresentedViewController
        }

        return self
    }
}
