import Foundation
import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

struct PhotoLibraryImageResult {
    let image: UIImage?
    let isDegraded: Bool
    let isInCloud: Bool
    let progress: Double?
    let isFinal: Bool
}

enum VideoCompressionQuality: String, CaseIterable, Identifiable {
    case balanced
    case smallFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return L10n.string("均衡")
        case .smallFile:
            return L10n.string("更小")
        }
    }

    var subtitle: String {
        switch self {
        case .balanced:
            return L10n.string("保持原分辨率，轻微降低码率，优先保留清晰度。")
        case .smallFile:
            return L10n.string("保持原分辨率，压缩更明显，清晰度可能略有下降。")
        }
    }

    var targetVideoBitrateMultiplier: Double {
        switch self {
        case .balanced:
            return 0.68
        case .smallFile:
            return 0.48
        }
    }

    var estimatedSavingsRatio: Double {
        switch self {
        case .balanced:
            return 0.28
        case .smallFile:
            return 0.42
        }
    }
}

struct VideoCompressionResult {
    let originalAssetIdentifier: String
    let createdAssetIdentifier: String?
    let originalSizeMB: Double
    let compressedSizeMB: Double
    let originalDimensions: CGSize
    let outputDimensions: CGSize

    var savedSizeMB: Double {
        max(originalSizeMB - compressedSizeMB, 0)
    }
}

private struct VideoCompressionOutput {
    let url: URL
    let outputDimensions: CGSize
}

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

    func clearLoadedLibraryData(clearSnapshot: Bool = true, finishPendingLoads: Bool = false) {
        let pendingCompletions = finishPendingLoads ? pendingLoadCompletions : []
        allPhotosResult = nil
        allPhotos = []
        videos = []
        screenshots = []
        livePhotos = []
        favorites = []
        isLoading = false
        loadingProgress = 0
        hasLoadedPhotoLibrary = false
        isRestoringSnapshot = false
        pendingLoadCompletions.removeAll()
        imageCache.removeAllObjects()
        imageManager.stopCachingImagesForAllAssets()

        if clearSnapshot {
            snapshotStore.clear()
        }

        pendingCompletions.forEach { $0() }
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
                    guard self.hasPhotoLibraryAccess else {
                        self.clearLoadedLibraryData(clearSnapshot: true, finishPendingLoads: true)
                        self.onLibraryDataChanged?()
                        return
                    }
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
                    guard self.hasPhotoLibraryAccess else {
                        self.clearLoadedLibraryData(clearSnapshot: true, finishPendingLoads: true)
                        self.onLibraryDataChanged?()
                        return
                    }
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
                let error = info?[PHImageErrorKey] as? Error
                guard !isCancelled else { return }

                // 缓存图片
                if let image = image {
                    self?.cacheImage(image, forKey: cacheKey, isDegraded: isDegraded)
                } else if isInCloud && error == nil {
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
                let error = info?[PHImageErrorKey] as? Error
                guard !isCancelled else { return }

                if let image {
                    self?.cacheImage(image, forKey: cacheKey, isDegraded: isDegraded)
                } else if isInCloud && error == nil {
                    return
                }
                completion(image)
            }
        }
    }

    @discardableResult
    func loadSwipePreviewResult(
        for asset: PHAsset,
        size: CGSize,
        completion: @escaping (PhotoLibraryImageResult) -> Void
    ) -> PHImageRequestID? {
        let cacheKey = imageCacheKey(for: asset, purpose: "swipe", size: size)

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(PhotoLibraryImageResult(
                image: cachedImage,
                isDegraded: false,
                isInCloud: false,
                progress: nil,
                isFinal: true
            ))
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.progressHandler = { progress, _, _, _ in
            DispatchQueue.main.async {
                completion(PhotoLibraryImageResult(
                    image: nil,
                    isDegraded: false,
                    isInCloud: true,
                    progress: progress,
                    isFinal: false
                ))
            }
        }

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
                }

                let isWaitingForCloudDownload = image == nil && isInCloud && error == nil
                completion(PhotoLibraryImageResult(
                    image: image,
                    isDegraded: isDegraded,
                    isInCloud: isInCloud,
                    progress: nil,
                    isFinal: !isDegraded && !isWaitingForCloudDownload
                ))
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
        options.isNetworkAccessAllowed = false
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
    func loadBrowserPreviewResult(
        for asset: PHAsset,
        size: CGSize,
        completion: @escaping (PhotoLibraryImageResult) -> Void
    ) -> PHImageRequestID? {
        let cacheKey = imageCacheKey(for: asset, purpose: "browser", size: size)

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(PhotoLibraryImageResult(
                image: cachedImage,
                isDegraded: false,
                isInCloud: false,
                progress: nil,
                isFinal: true
            ))
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.version = .current
        options.isNetworkAccessAllowed = false
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
                guard !isCancelled else { return }

                if let image {
                    self?.cacheImage(image, forKey: cacheKey, isDegraded: isDegraded)
                }

                completion(PhotoLibraryImageResult(
                    image: image,
                    isDegraded: isDegraded,
                    isInCloud: isInCloud,
                    progress: nil,
                    isFinal: !isDegraded
                ))
            }
        }
    }

    @discardableResult
    func loadBrowserPreview(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID? {
        loadBrowserPreviewResult(for: asset, size: size) { result in
            if let image = result.image {
                completion(image)
            } else if result.isFinal {
                completion(nil)
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

    func compressVideo(
        _ asset: PHAsset,
        quality: VideoCompressionQuality,
        progressHandler: (@MainActor @Sendable (Double, String) -> Void)? = nil
    ) async throws -> VideoCompressionResult {
        guard hasPhotoLibraryAccess else {
            throw VideoCompressionError.noLibraryAccess
        }

        guard asset.mediaType == .video else {
            throw VideoCompressionError.notVideo
        }

        await progressHandler?(0.04, L10n.string("正在读取原视频信息"))
        let originalSizeMB = try await actualVideoFileSizeMB(for: asset)
        let videoAsset = try await requestVideoAsset(for: asset)
        await progressHandler?(0.12, L10n.string("正在准备压缩参数"))
        let originalDimensions = try await displayDimensions(for: videoAsset)
        let output = try await exportCompressedVideo(
            from: videoAsset,
            originalSizeMB: originalSizeMB,
            quality: quality,
            progressHandler: progressHandler
        )
        defer {
            try? FileManager.default.removeItem(at: output.url)
        }

        let compressedSizeMB = try compressedFileSizeMB(at: output.url)
        await progressHandler?(0.9, L10n.string("正在保存压缩副本"))
        let createdAssetIdentifier = try await saveCompressedVideo(at: output.url, originalAsset: asset)
        await progressHandler?(1, L10n.string("压缩副本已保存"))
        return VideoCompressionResult(
            originalAssetIdentifier: asset.localIdentifier,
            createdAssetIdentifier: createdAssetIdentifier,
            originalSizeMB: originalSizeMB,
            compressedSizeMB: compressedSizeMB,
            originalDimensions: originalDimensions,
            outputDimensions: output.outputDimensions
        )
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
                let error = info?[PHImageErrorKey] as? Error
                guard !isCancelled else { return }

                if let image {
                    self?.cacheImage(image, forKey: cacheKey, isDegraded: isDegraded)
                } else if isInCloud && error == nil {
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

    private func requestVideoAsset(for asset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            imageManager.requestAVAsset(forVideo: asset, options: options) { videoAsset, _, info in
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                guard !isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                guard let videoAsset else {
                    continuation.resume(throwing: VideoCompressionError.videoUnavailable)
                    return
                }

                continuation.resume(returning: videoAsset)
            }
        }
    }

    private func actualVideoFileSizeMB(for asset: PHAsset) async throws -> Double {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizeVideo }) ??
            resources.first(where: { $0.type == .video }) else {
            throw VideoCompressionError.videoUnavailable
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        let counterLock = NSLock()
        var byteCount: Int64 = 0

        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    counterLock.lock()
                    byteCount += Int64(data.count)
                    counterLock.unlock()
                },
                completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    counterLock.lock()
                    let totalBytes = byteCount
                    counterLock.unlock()
                    continuation.resume(returning: max(Double(totalBytes) / 1_048_576, 0))
                }
            )
        }
    }

    private func displayDimensions(for asset: AVAsset) async throws -> CGSize {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoCompressionError.videoUnavailable
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        return displayDimensions(naturalSize: naturalSize, transform: preferredTransform)
    }

    private func exportCompressedVideo(
        from asset: AVAsset,
        originalSizeMB: Double,
        quality: VideoCompressionQuality,
        progressHandler: (@MainActor @Sendable (Double, String) -> Void)?
    ) async throws -> VideoCompressionOutput {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoCompressionError.videoUnavailable
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let displaySize = displayDimensions(naturalSize: naturalSize, transform: preferredTransform)
        let encodedSize = evenEncodedDimensions(from: naturalSize)
        let sourceBitrate = sourceVideoBitrate(
            estimatedDataRate: Double(estimatedDataRate),
            originalSizeMB: originalSizeMB,
            duration: duration
        )
        let targetBitrate = targetVideoBitrate(
            sourceBitrate: sourceBitrate,
            displaySize: displaySize,
            quality: quality
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoDelete-Compressed-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        try? FileManager.default.removeItem(at: outputURL)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw VideoCompressionError.exportFailed
        }
        reader.add(videoOutput)

        guard let videoInput = makeVideoWriterInput(
            encodedSize: encodedSize,
            preferredTransform: preferredTransform,
            targetBitrate: targetBitrate,
            frameRate: nominalFrameRate,
            writer: writer
        ) else {
            throw VideoCompressionError.exportFailed
        }

        let audioPair = makeAudioReaderWriterPair(from: audioTracks.first, reader: reader, writer: writer)

        await progressHandler?(0.16, L10n.string("正在压缩视频"))
        try await runReaderWriterExport(
            reader: reader,
            writer: writer,
            videoInput: videoInput,
            videoOutput: videoOutput,
            audioInput: audioPair?.input,
            audioOutput: audioPair?.output,
            duration: duration,
            progressHandler: progressHandler
        )

        return VideoCompressionOutput(url: outputURL, outputDimensions: displaySize)
    }

    private func makeVideoWriterInput(
        encodedSize: CGSize,
        preferredTransform: CGAffineTransform,
        targetBitrate: Int,
        frameRate: Float,
        writer: AVAssetWriter
    ) -> AVAssetWriterInput? {
        let codecs: [AVVideoCodecType] = [.hevc, .h264]

        for codec in codecs {
            var compressionProperties: [String: Any] = [
                AVVideoAverageBitRateKey: targetBitrate,
                AVVideoExpectedSourceFrameRateKey: max(Int(frameRate.rounded()), 24)
            ]
            if codec == .h264 {
                compressionProperties[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            }

            let settings: [String: Any] = [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: Int(encodedSize.width),
                AVVideoHeightKey: Int(encodedSize.height),
                AVVideoCompressionPropertiesKey: compressionProperties
            ]

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            input.transform = preferredTransform

            if writer.canAdd(input) {
                writer.add(input)
                return input
            }
        }

        return nil
    }

    private func makeAudioReaderWriterPair(
        from audioTrack: AVAssetTrack?,
        reader: AVAssetReader,
        writer: AVAssetWriter
    ) -> (input: AVAssetWriterInput, output: AVAssetReaderTrackOutput)? {
        guard let audioTrack else { return nil }

        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM
            ]
        )
        output.alwaysCopiesSampleData = false

        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000
            ]
        )
        input.expectsMediaDataInRealTime = false

        guard reader.canAdd(output), writer.canAdd(input) else {
            return nil
        }
        reader.add(output)
        writer.add(input)
        return (input, output)
    }

    private func runReaderWriterExport(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        videoOutput: AVAssetReaderTrackOutput,
        audioInput: AVAssetWriterInput?,
        audioOutput: AVAssetReaderTrackOutput?,
        duration: CMTime,
        progressHandler: (@MainActor @Sendable (Double, String) -> Void)?
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let stateLock = NSLock()
            var didComplete = false
            var videoFinished = false
            var audioFinished = audioInput == nil || audioOutput == nil

            func complete(_ result: Result<Void, Error>) {
                stateLock.lock()
                guard !didComplete else {
                    stateLock.unlock()
                    return
                }
                didComplete = true
                stateLock.unlock()

                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            func fail(_ error: Error) {
                reader.cancelReading()
                writer.cancelWriting()
                complete(.failure(error))
            }

            func finishIfReady() {
                stateLock.lock()
                let shouldFinish = videoFinished && audioFinished && !didComplete
                stateLock.unlock()

                guard shouldFinish else { return }
                writer.finishWriting {
                    if writer.status == .completed {
                        complete(.success(()))
                    } else if writer.status == .cancelled {
                        complete(.failure(CancellationError()))
                    } else {
                        complete(.failure(writer.error ?? VideoCompressionError.exportFailed))
                    }
                }
            }

            guard writer.startWriting() else {
                complete(.failure(writer.error ?? VideoCompressionError.exportFailed))
                return
            }
            guard reader.startReading() else {
                writer.cancelWriting()
                complete(.failure(reader.error ?? VideoCompressionError.exportFailed))
                return
            }
            writer.startSession(atSourceTime: .zero)

            let durationSeconds = max(CMTimeGetSeconds(duration), 1)
            let videoQueue = DispatchQueue(label: "PhotoDelete.VideoCompression.video")
            let audioQueue = DispatchQueue(label: "PhotoDelete.VideoCompression.audio")
            var lastProgressUpdate = Date.distantPast

            videoInput.requestMediaDataWhenReady(on: videoQueue) {
                while videoInput.isReadyForMoreMediaData {
                    if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                        guard videoInput.append(sampleBuffer) else {
                            fail(writer.error ?? VideoCompressionError.exportFailed)
                            return
                        }

                        let now = Date()
                        if now.timeIntervalSince(lastProgressUpdate) >= 0.2 {
                            lastProgressUpdate = now
                            let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                            let exportProgress = min(max(seconds / durationSeconds, 0), 1)
                            Task { @MainActor in
                                progressHandler?(0.16 + exportProgress * 0.7, L10n.string("正在压缩视频"))
                            }
                        }
                    } else {
                        videoInput.markAsFinished()
                        stateLock.lock()
                        videoFinished = true
                        stateLock.unlock()
                        finishIfReady()
                        break
                    }
                }
            }

            if let audioInput, let audioOutput {
                audioInput.requestMediaDataWhenReady(on: audioQueue) {
                    while audioInput.isReadyForMoreMediaData {
                        if let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                            guard audioInput.append(sampleBuffer) else {
                                fail(writer.error ?? VideoCompressionError.exportFailed)
                                return
                            }
                        } else {
                            audioInput.markAsFinished()
                            stateLock.lock()
                            audioFinished = true
                            stateLock.unlock()
                            finishIfReady()
                            break
                        }
                    }
                }
            }
        }
    }

    private func displayDimensions(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let width = abs(transformed.width)
        let height = abs(transformed.height)
        guard width > 0, height > 0 else {
            return CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))
        }
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    private func evenEncodedDimensions(from naturalSize: CGSize) -> CGSize {
        let width = max(Int(abs(naturalSize.width).rounded()), 2)
        let height = max(Int(abs(naturalSize.height).rounded()), 2)
        return CGSize(
            width: width - (width % 2),
            height: height - (height % 2)
        )
    }

    private func sourceVideoBitrate(
        estimatedDataRate: Double,
        originalSizeMB: Double,
        duration: CMTime
    ) -> Double {
        if estimatedDataRate > 0 {
            return estimatedDataRate
        }

        let seconds = max(CMTimeGetSeconds(duration), 1)
        let totalBits = originalSizeMB * 1_048_576 * 8
        return max(totalBits / seconds, 1_200_000)
    }

    private func targetVideoBitrate(
        sourceBitrate: Double,
        displaySize: CGSize,
        quality: VideoCompressionQuality
    ) -> Int {
        let pixelCount = max(displaySize.width * displaySize.height, 1)
        let resolutionFloor: Double
        if pixelCount >= 8_000_000 {
            resolutionFloor = 8_000_000
        } else if pixelCount >= 2_000_000 {
            resolutionFloor = 3_200_000
        } else if pixelCount >= 900_000 {
            resolutionFloor = 1_800_000
        } else {
            resolutionFloor = 1_000_000
        }

        let bitrateFromQuality = sourceBitrate * quality.targetVideoBitrateMultiplier
        let adaptiveFloor = min(sourceBitrate * 0.9, resolutionFloor)
        return Int(max(bitrateFromQuality, adaptiveFloor))
    }

    private func compressedFileSizeMB(at url: URL) throws -> Double {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = attributes[.size] as? NSNumber else {
            throw VideoCompressionError.exportFailed
        }
        return max(bytes.doubleValue / 1_048_576, 0)
    }

    private func saveCompressedVideo(at url: URL, originalAsset: PHAsset) async throws -> String? {
        guard hasPhotoLibraryAccess else {
            throw VideoCompressionError.noLibraryAccess
        }

        return try await withCheckedThrowingContinuation { continuation in
            var createdAssetIdentifier: String?
            expectLocalLibraryChange()
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = originalAsset.creationDate
                request.location = originalAsset.location
                request.addResource(with: .video, fileURL: url, options: nil)
                createdAssetIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }) { success, _ in
                if success {
                    continuation.resume(returning: createdAssetIdentifier)
                } else {
                    continuation.resume(throwing: VideoCompressionError.saveFailed)
                }
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

    func createAlbum(named title: String, completion: @escaping (String?, Error?) -> Void) {
        guard hasPhotoLibraryAccess else {
            completion(nil, PhotoLibraryWriteError.noLibraryAccess)
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            completion(nil, PhotoLibraryWriteError.invalidAlbumTitle)
            return
        }

        var createdAlbumIdentifier: String?
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: trimmedTitle)
            createdAlbumIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
        }) { success, error in
            DispatchQueue.main.async {
                completion(success ? createdAlbumIdentifier : nil, error)
            }
        }
    }

    func renameAlbum(_ album: PHAssetCollection, title: String, completion: @escaping (Bool, Error?) -> Void) {
        guard hasPhotoLibraryAccess else {
            completion(false, PhotoLibraryWriteError.noLibraryAccess)
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            completion(false, PhotoLibraryWriteError.invalidAlbumTitle)
            return
        }

        guard album.assetCollectionType == .album, album.canPerform(.rename) else {
            completion(false, PhotoLibraryWriteError.unsupportedAlbumRename)
            return
        }

        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest(for: album)
            request?.title = trimmedTitle
        }) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    func deleteAlbum(_ album: PHAssetCollection, completion: @escaping (Bool, Error?) -> Void) {
        guard hasPhotoLibraryAccess else {
            completion(false, PhotoLibraryWriteError.noLibraryAccess)
            return
        }

        guard album.assetCollectionType == .album, album.canPerform(.delete) else {
            completion(false, PhotoLibraryWriteError.unsupportedAlbumDelete)
            return
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

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
    case unsupportedAlbumRename
    case unsupportedAlbumDelete
    case invalidAlbumTitle

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
        case .unsupportedAlbumRename:
            return L10n.string("这个相册不支持重命名。")
        case .unsupportedAlbumDelete:
            return L10n.string("这个相册不支持删除。")
        case .invalidAlbumTitle:
            return L10n.string("请输入相册名称。")
        }
    }
}

private enum VideoCompressionError: LocalizedError {
    case noLibraryAccess
    case notVideo
    case videoUnavailable
    case exportFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noLibraryAccess:
            return L10n.string("当前照片权限不可用")
        case .notVideo:
            return L10n.string("这个项目不是视频")
        case .videoUnavailable:
            return L10n.string("无法读取这个视频")
        case .exportFailed:
            return L10n.string("视频压缩失败，请稍后再试。")
        case .saveFailed:
            return L10n.string("无法保存压缩视频")
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
