import Foundation
import AVFoundation
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PhotoLibraryImageResult {
    let image: UIImage?
    let isDegraded: Bool
    let isInCloud: Bool
    let progress: Double?
    let isFinal: Bool
}

struct PhotoLibraryLivePhotoResult {
    let livePhoto: PHLivePhoto?
    let isDegraded: Bool
    let isInCloud: Bool
    let isFinal: Bool
}

struct PhotoLibraryAssetClassification: Equatable {
    let isVideo: Bool
    let isScreenshot: Bool
    let isLivePhoto: Bool
    let isFavorite: Bool

    static func resolve(
        mediaType: PHAssetMediaType,
        mediaSubtypes: PHAssetMediaSubtype,
        pixelWidth: Int,
        pixelHeight: Int,
        screenPixelSize: CGSize,
        isFavorite: Bool
    ) -> PhotoLibraryAssetClassification {
        let isVideo = mediaType == .video
        let hasScreenshotSubtype = mediaSubtypes.contains(.photoScreenshot)
        let assetLongSide = max(CGFloat(pixelWidth), CGFloat(pixelHeight))
        let assetShortSide = min(CGFloat(pixelWidth), CGFloat(pixelHeight))
        let screenLongSide = max(screenPixelSize.width, screenPixelSize.height)
        let screenShortSide = min(screenPixelSize.width, screenPixelSize.height)
        let matchesScreenSize = abs(assetLongSide - screenLongSide) < 10 &&
            abs(assetShortSide - screenShortSide) < 10

        return PhotoLibraryAssetClassification(
            isVideo: isVideo,
            isScreenshot: !isVideo && (hasScreenshotSubtype || matchesScreenSize),
            isLivePhoto: mediaType == .image && mediaSubtypes.contains(.photoLive),
            isFavorite: isFavorite
        )
    }
}

struct PhotoSharePayload: Identifiable {
    let id = UUID()
    let fileURL: URL
    let temporaryDirectoryURL: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}

enum PhotoSharePreparationError: Error {
    case noLibraryAccess
    case resourceUnavailable
}

struct PhotoLibraryAssetListSignature: Equatable {
    let count: Int
    let firstIdentifier: String?
    let lastIdentifier: String?

    init(identifiers: [String]) {
        self.count = identifiers.count
        self.firstIdentifier = identifiers.first
        self.lastIdentifier = identifiers.last
    }

    init(count: Int, firstIdentifier: String?, lastIdentifier: String?) {
        self.count = count
        self.firstIdentifier = firstIdentifier
        self.lastIdentifier = lastIdentifier
    }
}

struct PhotoLibraryRefreshSignature: Equatable {
    let allPhotos: PhotoLibraryAssetListSignature
    let videos: PhotoLibraryAssetListSignature
    let favorites: PhotoLibraryAssetListSignature
    let screenshots: PhotoLibraryAssetListSignature
    let livePhotos: PhotoLibraryAssetListSignature

    init(
        allPhotoIDs: [String],
        videoIDs: [String],
        favoriteIDs: [String],
        screenshotIDs: [String],
        livePhotoIDs: [String]
    ) {
        self.allPhotos = PhotoLibraryAssetListSignature(identifiers: allPhotoIDs)
        self.videos = PhotoLibraryAssetListSignature(identifiers: videoIDs)
        self.favorites = PhotoLibraryAssetListSignature(identifiers: favoriteIDs)
        self.screenshots = PhotoLibraryAssetListSignature(identifiers: screenshotIDs)
        self.livePhotos = PhotoLibraryAssetListSignature(identifiers: livePhotoIDs)
    }

    init(
        allPhotos: PhotoLibraryAssetListSignature,
        videos: PhotoLibraryAssetListSignature,
        favorites: PhotoLibraryAssetListSignature,
        screenshots: PhotoLibraryAssetListSignature,
        livePhotos: PhotoLibraryAssetListSignature
    ) {
        self.allPhotos = allPhotos
        self.videos = videos
        self.favorites = favorites
        self.screenshots = screenshots
        self.livePhotos = livePhotos
    }
}

private struct PhotoLibraryRefreshState {
    let allPhotosResult: PHFetchResult<PHAsset>
    let signature: PhotoLibraryRefreshSignature
}

enum PhotoLibraryLoadingPublishPolicy {
    static func shouldPublishInitialPhotos(
        batchStart: Int,
        batchEnd _: Int,
        totalCount: Int,
        preserveExistingData: Bool
    ) -> Bool {
        !preserveExistingData && totalCount > 0 && batchStart == 0
    }

    static func shouldPublishScanProgress(
        batchEnd: Int,
        totalCount: Int,
        batchSize: Int
    ) -> Bool {
        guard totalCount > 0, batchSize > 0 else { return false }
        return batchEnd == totalCount || batchEnd % (batchSize * 5) == 0
    }
}

enum PhotoLibraryDeferredReloadPolicy {
    static func shouldDeferReload(
        isLoading: Bool,
        isRestoringSnapshot: Bool,
        hasTrackedFetchResult: Bool,
        hasChangeDetails: Bool
    ) -> Bool {
        (isLoading || isRestoringSnapshot) && hasTrackedFetchResult && hasChangeDetails
    }
}

enum VideoCompressionQuality: String, CaseIterable, Identifiable {
    case high
    case balanced
    case spaceSaving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high:
            return L10n.string("高清保留")
        case .balanced:
            return L10n.string("均衡推荐")
        case .spaceSaving:
            return L10n.string("节省空间")
        }
    }

    var compactTitle: String {
        switch self {
        case .high:
            return L10n.string("高清")
        case .balanced:
            return L10n.string("均衡")
        case .spaceSaving:
            return L10n.string("省空间")
        }
    }

    var subtitle: String {
        switch self {
        case .high:
            return L10n.string("轻微降低码率，更适合重要视频。")
        case .balanced:
            return L10n.string("画质和体积的默认平衡，适合大多数视频。")
        case .spaceSaving:
            return L10n.string("更明显降低码率，适合只想腾出空间的视频。")
        }
    }

    var targetVideoBitrateMultiplier: Double {
        switch self {
        case .high:
            return 0.82
        case .balanced:
            return 0.62
        case .spaceSaving:
            return 0.42
        }
    }

    var estimatedSavingsRatio: Double {
        switch self {
        case .high:
            return 0.16
        case .balanced:
            return 0.34
        case .spaceSaving:
            return 0.50
        }
    }
}

enum VideoCompressionResolution: String, CaseIterable, Identifiable {
    case original
    case automatic
    case p1080
    case p720

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original:
            return L10n.string("原分辨率")
        case .automatic:
            return L10n.string("自动")
        case .p1080:
            return L10n.string("1080p")
        case .p720:
            return L10n.string("720p")
        }
    }

    var subtitle: String {
        switch self {
        case .original:
            return L10n.string("不改变分辨率，只调整编码和码率。")
        case .automatic:
            return L10n.string("4K 视频转为 1080p，1080p 及以下保持不变。")
        case .p1080:
            return L10n.string("适合 4K 生活视频，明显减少体积。")
        case .p720:
            return L10n.string("适合聊天备份和低重要性视频，空间优先。")
        }
    }

    var maxLongEdge: CGFloat? {
        switch self {
        case .original:
            return nil
        case .automatic, .p1080:
            return 1_920
        case .p720:
            return 1_280
        }
    }

    func targetDisplaySize(for originalSize: CGSize) -> CGSize {
        let width = max(originalSize.width, 1)
        let height = max(originalSize.height, 1)
        let longEdge = max(width, height)
        let shortEdge = min(width, height)

        let targetLongEdge: CGFloat
        switch self {
        case .original:
            return CGSize(width: width.rounded(), height: height.rounded())
        case .automatic:
            guard longEdge > 2_200 else {
                return CGSize(width: width.rounded(), height: height.rounded())
            }
            targetLongEdge = 1_920
        case .p1080, .p720:
            guard let maxLongEdge, longEdge > maxLongEdge else {
                return CGSize(width: width.rounded(), height: height.rounded())
            }
            targetLongEdge = maxLongEdge
        }

        let scale = targetLongEdge / longEdge
        let targetShortEdge = shortEdge * scale
        if width >= height {
            return CGSize(width: targetLongEdge.rounded(), height: targetShortEdge.rounded())
        }
        return CGSize(width: targetShortEdge.rounded(), height: targetLongEdge.rounded())
    }
}

struct VideoCompressionPlan: Equatable {
    var quality: VideoCompressionQuality
    var resolution: VideoCompressionResolution

    static let `default` = VideoCompressionPlan(quality: .balanced, resolution: .original)

    var title: String {
        "\(quality.title) · \(resolution.title)"
    }
}

struct VideoCompressionEstimate: Equatable {
    let originalSizeMB: Double
    let estimatedCompressedLowMB: Double
    let estimatedCompressedHighMB: Double

    var estimatedSavedLowMB: Double {
        max(originalSizeMB - estimatedCompressedHighMB, 0)
    }

    var estimatedSavedHighMB: Double {
        max(originalSizeMB - estimatedCompressedLowMB, 0)
    }

    var estimatedCompressedMidMB: Double {
        (estimatedCompressedLowMB + estimatedCompressedHighMB) / 2
    }

    var estimatedSavedMidMB: Double {
        max(originalSizeMB - estimatedCompressedMidMB, 0)
    }

    var formattedOriginalSize: String {
        CleanupStatsFormatter.space(originalSizeMB)
    }

    var formattedCompressedRange: String {
        if abs(estimatedCompressedHighMB - estimatedCompressedLowMB) < 1 {
            return CleanupStatsFormatter.space(estimatedCompressedMidMB)
        }
        return "\(CleanupStatsFormatter.space(estimatedCompressedLowMB)) - \(CleanupStatsFormatter.space(estimatedCompressedHighMB))"
    }

    var formattedSavedRange: String {
        if abs(estimatedSavedHighMB - estimatedSavedLowMB) < 1 {
            return CleanupStatsFormatter.space(estimatedSavedMidMB)
        }
        return "\(CleanupStatsFormatter.space(estimatedSavedLowMB)) - \(CleanupStatsFormatter.space(estimatedSavedHighMB))"
    }
}

struct VideoFileSizeEstimate: Equatable {
    enum Source: Equatable {
        case assetResource
        case iCloud
        case unavailable
    }

    let sizeMB: Double
    let source: Source

    var isReliable: Bool {
        switch source {
        case .assetResource:
            return true
        case .iCloud, .unavailable:
            return false
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

enum ImageCompressionQuality: String, CaseIterable, Identifiable {
    case high
    case balanced
    case spaceSaving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high:
            return L10n.string("细节优先")
        case .balanced:
            return L10n.string("均衡推荐")
        case .spaceSaving:
            return L10n.string("节省空间")
        }
    }

    var compactTitle: String {
        switch self {
        case .high:
            return L10n.string("细节")
        case .balanced:
            return L10n.string("均衡")
        case .spaceSaving:
            return L10n.string("省空间")
        }
    }

    var subtitle: String {
        switch self {
        case .high:
            return L10n.string("保留更多细节，适合重要照片。")
        case .balanced:
            return L10n.string("画质和体积的默认平衡，适合大多数照片。")
        case .spaceSaving:
            return L10n.string("更明显压缩体积，适合备份或低重要性图片。")
        }
    }

    var jpegQuality: CGFloat {
        switch self {
        case .high:
            return 0.88
        case .balanced:
            return 0.76
        case .spaceSaving:
            return 0.62
        }
    }

    var estimatedSavingsRatio: Double {
        switch self {
        case .high:
            return 0.18
        case .balanced:
            return 0.34
        case .spaceSaving:
            return 0.48
        }
    }
}

enum ImageCompressionSize: String, CaseIterable, Identifiable {
    case original
    case automatic
    case large
    case medium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original:
            return L10n.string("原尺寸")
        case .automatic:
            return L10n.string("自动")
        case .large:
            return L10n.string("2400px")
        case .medium:
            return L10n.string("1600px")
        }
    }

    var subtitle: String {
        switch self {
        case .original:
            return L10n.string("不改变尺寸，只调整图片编码质量。")
        case .automatic:
            return L10n.string("超大图片缩到 3200px，较小图片保持原尺寸。")
        case .large:
            return L10n.string("适合日常照片备份，细节和体积更平衡。")
        case .medium:
            return L10n.string("适合聊天分享和低重要性图片，空间优先。")
        }
    }

    var maxLongEdge: CGFloat? {
        switch self {
        case .original:
            return nil
        case .automatic:
            return 3_200
        case .large:
            return 2_400
        case .medium:
            return 1_600
        }
    }

    func targetPixelSize(for originalSize: CGSize) -> CGSize {
        let width = max(originalSize.width, 1)
        let height = max(originalSize.height, 1)
        let longEdge = max(width, height)

        switch self {
        case .original:
            return CGSize(width: width.rounded(), height: height.rounded())
        case .automatic:
            guard longEdge > 3_600 else {
                return CGSize(width: width.rounded(), height: height.rounded())
            }
        case .large, .medium:
            guard let maxLongEdge, longEdge > maxLongEdge else {
                return CGSize(width: width.rounded(), height: height.rounded())
            }
        }

        guard let targetLongEdge = maxLongEdge else {
            return CGSize(width: width.rounded(), height: height.rounded())
        }
        let scale = targetLongEdge / longEdge
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }
}

struct ImageCompressionPlan: Equatable {
    var quality: ImageCompressionQuality
    var size: ImageCompressionSize

    static let `default` = ImageCompressionPlan(quality: .high, size: .automatic)

    var title: String {
        "\(quality.title) · \(size.title)"
    }
}

struct ImageCompressionEstimate: Equatable {
    let originalSizeMB: Double
    let estimatedCompressedLowMB: Double
    let estimatedCompressedHighMB: Double

    var estimatedSavedLowMB: Double {
        max(originalSizeMB - estimatedCompressedHighMB, 0)
    }

    var estimatedSavedHighMB: Double {
        max(originalSizeMB - estimatedCompressedLowMB, 0)
    }

    var estimatedCompressedMidMB: Double {
        (estimatedCompressedLowMB + estimatedCompressedHighMB) / 2
    }

    var estimatedSavedMidMB: Double {
        max(originalSizeMB - estimatedCompressedMidMB, 0)
    }

    var formattedOriginalSize: String {
        CleanupStatsFormatter.space(originalSizeMB)
    }

    var formattedCompressedRange: String {
        if abs(estimatedCompressedHighMB - estimatedCompressedLowMB) < 0.5 {
            return CleanupStatsFormatter.space(estimatedCompressedMidMB)
        }
        return "\(CleanupStatsFormatter.space(estimatedCompressedLowMB)) - \(CleanupStatsFormatter.space(estimatedCompressedHighMB))"
    }

    var formattedSavedRange: String {
        if abs(estimatedSavedHighMB - estimatedSavedLowMB) < 0.5 {
            return CleanupStatsFormatter.space(estimatedSavedMidMB)
        }
        return "\(CleanupStatsFormatter.space(estimatedSavedLowMB)) - \(CleanupStatsFormatter.space(estimatedSavedHighMB))"
    }
}

struct ImageCompressionResult {
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

private struct ImageCompressionOutput {
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
    @Published private(set) var cachedCounts: PhotoLibraryCachedCounts?

    private var allPhotosResult: PHFetchResult<PHAsset>?
    private let imageManager = PHCachingImageManager()
    private let imageCache = NSCache<NSString, UIImage>()
    private struct SwipePreviewPreloadRequest {
        let requestID: PHImageRequestID
    }
    private var swipePreviewPreloadRequests: [String: SwipePreviewPreloadRequest] = [:]
    private let snapshotStore = PhotoLibrarySnapshotStore()
    private var pendingLoadCompletions: [() -> Void] = []
    private var localChangeNotificationsRemaining = 0
    private var localChangeResetWorkItem: DispatchWorkItem?
    private var isRestoringSnapshot = false
    private var rebuildCachedAssetsWorkItem: DispatchWorkItem?
    private var rebuildCachedAssetsGeneration = 0
    private var needsPhotoLibraryReloadAfterCurrentLoad = false

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
        needsPhotoLibraryReloadAfterCurrentLoad = false
        cancelPendingRebuildCachedAssets()
        pendingLoadCompletions.removeAll()
        imageCache.removeAllObjects()
        imageManager.stopCachingImagesForAllAssets()
        cancelSwipePreviewPreloads()

        if clearSnapshot {
            snapshotStore.clear()
            cachedCounts = nil
        }

        pendingCompletions.forEach { $0() }
    }

    override init() {
        super.init()
        // 配置图片缓存
        imageCache.countLimit = 50 // 最多缓存50张图片
        imageCache.totalCostLimit = 100 * 1024 * 1024 // 100MB内存限制
        cachedCounts = snapshotStore.load().map(PhotoLibraryCachedCounts.init(snapshot:))

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

    func prepareSharePayload(for asset: PHAsset) async throws -> PhotoSharePayload {
        guard hasPhotoLibraryAccess else {
            throw PhotoSharePreparationError.noLibraryAccess
        }

        let resources = PHAssetResource.assetResources(for: asset)
        let resource: PHAssetResource?
        if asset.mediaType == .video {
            resource = resources.first(where: { $0.type == .fullSizeVideo }) ??
                resources.first(where: { $0.type == .video })
        } else {
            resource = resources.first(where: { $0.type == .fullSizePhoto }) ??
                resources.first(where: { $0.type == .photo })
        }

        guard let resource else {
            throw PhotoSharePreparationError.resourceUnavailable
        }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoDeleteShare", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let originalFilename = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
        let fallbackExtension = UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension
        let fallbackBaseName = asset.mediaType == .video ? "Video" : "Photo"
        let fallbackFilename = fallbackExtension.map { "\(fallbackBaseName).\($0)" } ?? fallbackBaseName
        let filename = originalFilename.isEmpty ? fallbackFilename : originalFilename
        let fileURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(
                    for: resource,
                    toFile: fileURL,
                    options: options
                ) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            try Task.checkCancellation()
            return PhotoSharePayload(fileURL: fileURL, temporaryDirectoryURL: directoryURL)
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
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

        cachedCounts = PhotoLibraryCachedCounts(snapshot: snapshot)
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
            let restoreDecision = PhotoLibrarySnapshotRestorePolicy.decision(
                cachedIdentifierCount: snapshot.allPhotoIDs.count,
                restoredIdentifierCount: restoredAssets.count,
                currentLibraryCount: fetchResult.count
            )

            guard restoreDecision.shouldRestore else {
                DispatchQueue.main.async {
                    self.isRestoringSnapshot = false
                    completion(false)
                    self.reloadPhotoLibraryAfterCurrentLoadIfNeeded()
                }
                return
            }

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
                self.reloadPhotoLibraryAfterCurrentLoadIfNeeded()
            }
        }
    }

    func refreshPhotoLibraryIfNeeded(completion: ((Bool) -> Void)? = nil) {
        guard hasPhotoLibraryAccess, hasLoadedPhotoLibrary, !isLoading else {
            completion?(false)
            return
        }

        let currentSignature = loadedPhotoLibraryRefreshSignature()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let latestState = self.currentPhotoLibraryRefreshState()
            let identifiersChanged = latestState.signature != currentSignature

            DispatchQueue.main.async {
                if identifiersChanged {
                    self.rebuildCachedAssets(from: latestState.allPhotosResult, generation: nil) {
                        completion?(true)
                    }
                } else {
                    completion?(false)
                }
            }
        }
    }

    private func currentPhotoLibraryRefreshState() -> PhotoLibraryRefreshState {
        let allPhotosResult = PHAsset.fetchAssets(with: defaultPhotoFetchOptions())
        return PhotoLibraryRefreshState(
            allPhotosResult: allPhotosResult,
            signature: PhotoLibraryRefreshSignature(
                allPhotos: assetListSignature(from: allPhotosResult),
                videos: assetListSignature(from: fetchAssets(mediaType: .video)),
                favorites: assetListSignature(from: fetchFavoriteAssets()),
                screenshots: assetListSignature(from: fetchSmartAlbumAssets(.smartAlbumScreenshots)),
                livePhotos: assetListSignature(from: fetchSmartAlbumAssets(.smartAlbumLivePhotos))
            )
        )
    }

    private func loadedPhotoLibraryRefreshSignature() -> PhotoLibraryRefreshSignature {
        PhotoLibraryRefreshSignature(
            allPhotos: assetListSignature(fromLoadedAssets: allPhotos),
            videos: assetListSignature(fromLoadedAssets: videos),
            favorites: assetListSignature(fromLoadedAssets: favorites),
            screenshots: assetListSignature(fromLoadedAssets: screenshots),
            livePhotos: assetListSignature(fromLoadedAssets: livePhotos)
        )
    }

    private func assetListSignature(from fetchResult: PHFetchResult<PHAsset>) -> PhotoLibraryAssetListSignature {
        let count = fetchResult.count
        return PhotoLibraryAssetListSignature(
            count: count,
            firstIdentifier: count > 0 ? fetchResult.object(at: 0).localIdentifier : nil,
            lastIdentifier: count > 1 ? fetchResult.object(at: count - 1).localIdentifier : (count == 1 ? fetchResult.object(at: 0).localIdentifier : nil)
        )
    }

    private func assetListSignature(fromLoadedAssets assets: [PHAsset]) -> PhotoLibraryAssetListSignature {
        PhotoLibraryAssetListSignature(
            count: assets.count,
            firstIdentifier: assets.first?.localIdentifier,
            lastIdentifier: assets.last?.localIdentifier
        )
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
            var videosArray: [PHAsset] = []
            var screenshotsArray: [PHAsset] = []
            var livePhotosArray: [PHAsset] = []
            var favoritesArray: [PHAsset] = []

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
                    self.reloadPhotoLibraryAfterCurrentLoadIfNeeded()
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
                for asset in batchAssets {
                    self.appendAssetClassification(
                        asset,
                        screenPixelSize: screenPixelSize,
                        videos: &videosArray,
                        screenshots: &screenshotsArray,
                        livePhotos: &livePhotosArray,
                        favorites: &favoritesArray
                    )
                }

                // 更新进度
                let loadingProgress = Double(batchEnd) / Double(totalCount) * 0.9
                let shouldPublishPartialPhotos = PhotoLibraryLoadingPublishPolicy.shouldPublishInitialPhotos(
                    batchStart: batchStart,
                    batchEnd: batchEnd,
                    totalCount: totalCount,
                    preserveExistingData: shouldPreserveExistingData
                )
                let shouldPublishProgress = PhotoLibraryLoadingPublishPolicy.shouldPublishScanProgress(
                    batchEnd: batchEnd,
                    totalCount: totalCount,
                    batchSize: batchSize
                )
                let partialPhotos = shouldPublishPartialPhotos ? allPhotosArray : []
                if shouldPublishPartialPhotos || shouldPublishProgress {
                    DispatchQueue.main.async {
                        self.loadingProgress = max(self.loadingProgress, loadingProgress)
                        if shouldPublishPartialPhotos, self.hasPhotoLibraryAccess {
                            self.allPhotos = partialPhotos
                            self.hasLoadedPhotoLibrary = !partialPhotos.isEmpty
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                guard self.hasPhotoLibraryAccess else {
                    self.clearLoadedLibraryData(clearSnapshot: true, finishPendingLoads: true)
                    self.onLibraryDataChanged?()
                    return
                }
                self.allPhotos = allPhotosArray
                self.videos = videosArray
                self.screenshots = screenshotsArray
                self.livePhotos = livePhotosArray
                self.favorites = favoritesArray
                self.loadingProgress = 1.0
                self.isLoading = false
                self.hasLoadedPhotoLibrary = true
                self.saveSnapshot(
                    allPhotos: allPhotosArray,
                    videos: videosArray,
                    screenshots: screenshotsArray,
                    livePhotos: livePhotosArray,
                    favorites: favoritesArray
                )
                self.finishLoadingPhotos()
                self.onLibraryDataChanged?()
                self.reloadPhotoLibraryAfterCurrentLoadIfNeeded()
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

            var favoritesArray: [PHAsset] = []
            for asset in photos {
                self.appendAssetClassification(
                    asset,
                    screenPixelSize: screenPixelSize,
                    videos: &videos,
                    screenshots: &screenshots,
                    livePhotos: &livePhotos,
                    favorites: &favoritesArray
                )
            }

            completion(videos, screenshots, livePhotos, favoritesArray)
        }
    }

    private func appendAssetClassification(
        _ asset: PHAsset,
        screenPixelSize: CGSize,
        videos: inout [PHAsset],
        screenshots: inout [PHAsset],
        livePhotos: inout [PHAsset],
        favorites: inout [PHAsset]
    ) {
        let classification = assetClassification(asset, screenPixelSize: screenPixelSize)
        if classification.isVideo {
            videos.append(asset)
        } else if classification.isScreenshot {
            screenshots.append(asset)
        }

        if classification.isLivePhoto {
            livePhotos.append(asset)
        }
        if classification.isFavorite {
            favorites.append(asset)
        }
    }

    // MARK: - Photo Classification

    func isScreenshot(_ asset: PHAsset) -> Bool {
        assetClassification(asset, screenPixelSize: Self.currentScreenPixelSize()).isScreenshot
    }

    func isLivePhoto(_ asset: PHAsset) -> Bool {
        asset.mediaType == .image && asset.mediaSubtypes.contains(.photoLive)
    }

    private func assetClassification(
        _ asset: PHAsset,
        screenPixelSize: CGSize
    ) -> PhotoLibraryAssetClassification {
        PhotoLibraryAssetClassification.resolve(
            mediaType: asset.mediaType,
            mediaSubtypes: asset.mediaSubtypes,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            screenPixelSize: screenPixelSize,
            isFavorite: asset.isFavorite
        )
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
        networkAccessAllowed: Bool = false,
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
        options.isNetworkAccessAllowed = networkAccessAllowed
        options.isSynchronous = false
        if networkAccessAllowed {
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

                let isWaitingForCloudDownload = networkAccessAllowed && image == nil && isInCloud && error == nil
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
    func loadHighQualityPreview(
        for asset: PHAsset,
        size: CGSize,
        networkAccessAllowed: Bool = false,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID? {
        let cacheKey = imageCacheKey(for: asset, purpose: "hq", size: size)

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        options.isNetworkAccessAllowed = networkAccessAllowed
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

                if let image, !isDegraded {
                    self?.cacheImage(image, forKey: cacheKey, isDegraded: isDegraded)
                    completion(image)
                } else if image != nil {
                    return
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
        networkAccessAllowed: Bool = false,
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
        options.isNetworkAccessAllowed = networkAccessAllowed
        options.isSynchronous = false
        if networkAccessAllowed {
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
        }

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

                let isWaitingForCloudDownload = networkAccessAllowed && image == nil && isInCloud
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
    func loadLivePhotoResult(
        for asset: PHAsset,
        size: CGSize,
        networkAccessAllowed: Bool = false,
        completion: @escaping (PhotoLibraryLivePhotoResult) -> Void
    ) -> PHImageRequestID? {
        guard isLivePhoto(asset) else {
            completion(PhotoLibraryLivePhotoResult(
                livePhoto: nil,
                isDegraded: false,
                isInCloud: false,
                isFinal: true
            ))
            return nil
        }

        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .opportunistic
        options.version = .current
        options.isNetworkAccessAllowed = networkAccessAllowed

        return imageManager.requestLivePhoto(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { livePhoto, info in
            DispatchQueue.main.async {
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                guard !isCancelled else { return }
                let isWaitingForCloudDownload = networkAccessAllowed && livePhoto == nil && isInCloud

                completion(PhotoLibraryLivePhotoResult(
                    livePhoto: livePhoto,
                    isDegraded: isDegraded,
                    isInCloud: isInCloud,
                    isFinal: !isDegraded && !isWaitingForCloudDownload
                ))
            }
        }
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
        plan: VideoCompressionPlan,
        progressHandler: (@MainActor @Sendable (Double, String) -> Void)? = nil
    ) async throws -> VideoCompressionResult {
        try Task.checkCancellation()
        guard hasPhotoLibraryAccess else {
            throw VideoCompressionError.noLibraryAccess
        }

        guard asset.mediaType == .video else {
            throw VideoCompressionError.notVideo
        }

        await progressHandler?(0.04, L10n.string("正在读取原视频信息"))
        try Task.checkCancellation()
        let videoAsset = try await requestVideoAsset(for: asset)
        try Task.checkCancellation()
        let originalSizeMB = try await actualVideoFileSizeMB(for: asset, preferredVideoAsset: videoAsset)
        try Task.checkCancellation()
        await progressHandler?(0.12, L10n.string("正在准备压缩参数"))
        let originalDimensions = try await displayDimensions(for: videoAsset)
        try Task.checkCancellation()
        let output = try await exportCompressedVideo(
            from: videoAsset,
            originalSizeMB: originalSizeMB,
            plan: plan,
            progressHandler: progressHandler
        )
        try Task.checkCancellation()
        defer {
            try? FileManager.default.removeItem(at: output.url)
        }

        let compressedSizeMB = try compressedFileSizeMB(at: output.url)
        try Task.checkCancellation()
        await progressHandler?(0.9, L10n.string("正在保存压缩副本"))
        try Task.checkCancellation()
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

    func compressImage(
        _ asset: PHAsset,
        plan: ImageCompressionPlan,
        progressHandler: (@MainActor @Sendable (Double, String) -> Void)? = nil
    ) async throws -> ImageCompressionResult {
        guard hasPhotoLibraryAccess else {
            throw ImageCompressionError.noLibraryAccess
        }

        guard asset.mediaType == .image else {
            throw ImageCompressionError.notImage
        }

        guard !asset.mediaSubtypes.contains(.photoLive) else {
            throw ImageCompressionError.livePhotoUnsupported
        }

        await progressHandler?(0.04, L10n.string("正在读取原图信息"))
        let imageData = try await requestImageData(for: asset)
        let originalSizeMB = max(Double(imageData.count) / 1_048_576, 0)
        await progressHandler?(0.22, L10n.string("正在准备压缩参数"))
        let output = try await exportCompressedImage(
            from: imageData,
            originalAsset: asset,
            plan: plan,
            progressHandler: progressHandler
        )
        defer {
            try? FileManager.default.removeItem(at: output.url)
        }

        let compressedSizeMB = try compressedImageFileSizeMB(at: output.url)
        guard compressedSizeMB < originalSizeMB else {
            throw ImageCompressionError.notWorthCompressing
        }

        await progressHandler?(0.88, L10n.string("正在保存压缩副本"))
        let createdAssetIdentifier = try await saveCompressedImage(at: output.url, originalAsset: asset)
        await progressHandler?(1, L10n.string("压缩副本已保存"))
        return ImageCompressionResult(
            originalAssetIdentifier: asset.localIdentifier,
            createdAssetIdentifier: createdAssetIdentifier,
            originalSizeMB: originalSizeMB,
            compressedSizeMB: compressedSizeMB,
            originalDimensions: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
            outputDimensions: output.outputDimensions
        )
    }

    func videoFileSizeEstimate(for asset: PHAsset) async throws -> VideoFileSizeEstimate {
        guard asset.mediaType == .video else {
            throw VideoCompressionError.notVideo
        }

        do {
            let request = try await requestVideoAssetForSizeEstimate(for: asset)
            guard let videoAsset = request.asset else {
                return VideoFileSizeEstimate(
                    sizeMB: 0,
                    source: request.isInCloud ? .iCloud : .unavailable
                )
            }
            let sizeMB = try await actualVideoFileSizeMB(
                for: asset,
                networkAccessAllowed: false,
                preferredVideoAsset: videoAsset
            )
            return VideoFileSizeEstimate(sizeMB: sizeMB, source: .assetResource)
        } catch is CancellationError {
            throw CancellationError()
        } catch {}

        return VideoFileSizeEstimate(sizeMB: 0, source: .unavailable)
    }

    func estimatedVideoFileSizeMB(for asset: PHAsset) async throws -> Double {
        let estimate = try await videoFileSizeEstimate(for: asset)
        guard estimate.isReliable else {
            throw VideoCompressionError.videoUnavailable
        }
        return estimate.sizeMB
    }

    private func requestVideoAssetForSizeEstimate(
        for asset: PHAsset
    ) async throws -> (asset: AVAsset?, isInCloud: Bool) {
        let cancellation = PhotoLibraryImageRequestCancellation(manager: imageManager)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let options = PHVideoRequestOptions()
                options.deliveryMode = .automatic
                options.isNetworkAccessAllowed = false

                let requestID = imageManager.requestAVAsset(forVideo: asset, options: options) { videoAsset, _, info in
                    let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                    guard !isCancelled, !cancellation.wasCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                    if let videoAsset {
                        continuation.resume(returning: (videoAsset, isInCloud))
                        return
                    }

                    if let error = info?[PHImageErrorKey] as? Error, !isInCloud {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: (nil, isInCloud))
                }
                cancellation.setRequestID(requestID)
            }
        } onCancel: {
            cancellation.cancel()
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
        options.isNetworkAccessAllowed = false

        imageManager.startCachingImages(
            for: assetsToPreload,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        )
    }

    func preloadSwipePreviewsForAssets(_ assets: [PHAsset], size: CGSize, maxCount: Int = 3) {
        let assetsToPreload = Array(assets.prefix(maxCount))
        let targetKeys = Set(assetsToPreload.map { swipePreviewPreloadKey(for: $0, size: size) })
        cancelSwipePreviewPreloads(excluding: targetKeys)
        guard !assetsToPreload.isEmpty else { return }

        for asset in assetsToPreload {
            let preloadKey = swipePreviewPreloadKey(for: asset, size: size)
            guard swipePreviewPreloadRequests[preloadKey] == nil else { continue }

            let requestID = loadSwipePreviewResult(
                for: asset,
                size: size,
                networkAccessAllowed: false
            ) { [weak self] result in
                guard result.isFinal else { return }
                self?.swipePreviewPreloadRequests[preloadKey] = nil
            }

            if let requestID {
                swipePreviewPreloadRequests[preloadKey] = SwipePreviewPreloadRequest(requestID: requestID)
            }
        }
    }

    func cancelSwipePreviewPreloads() {
        cancelSwipePreviewPreloads(excluding: [])
    }

    private func cancelSwipePreviewPreloads(excluding retainedKeys: Set<String>) {
        let keysToCancel = swipePreviewPreloadRequests.keys.filter { !retainedKeys.contains($0) }
        for key in keysToCancel {
            guard let preloadRequest = swipePreviewPreloadRequests[key] else { continue }
            imageManager.cancelImageRequest(preloadRequest.requestID)
            swipePreviewPreloadRequests[key] = nil
        }
    }

    private func swipePreviewPreloadKey(for asset: PHAsset, size: CGSize) -> String {
        "\(asset.localIdentifier)_\(Int(size.width))x\(Int(size.height))"
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
        cancelSwipePreviewPreloads()
        imageCache.removeAllObjects()
        imageManager.stopCachingImagesForAllAssets()
    }

    func stopCachingImages(_ assets: [PHAsset], size: CGSize) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
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
        options.isNetworkAccessAllowed = false

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
                    completion(nil)
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

    private func requestVideoAsset(
        for asset: PHAsset,
        networkAccessAllowed: Bool = true
    ) async throws -> AVAsset {
        let cancellation = PhotoLibraryImageRequestCancellation(manager: imageManager)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let options = PHVideoRequestOptions()
                options.deliveryMode = networkAccessAllowed ? .highQualityFormat : .automatic
                options.isNetworkAccessAllowed = networkAccessAllowed

                let requestID = imageManager.requestAVAsset(forVideo: asset, options: options) { videoAsset, _, info in
                    let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                    guard !isCancelled, !cancellation.wasCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    guard let videoAsset else {
                        continuation.resume(throwing: VideoCompressionError.videoUnavailable)
                        return
                    }

                    continuation.resume(returning: videoAsset)
                }
                cancellation.setRequestID(requestID)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func actualVideoFileSizeMB(
        for asset: PHAsset,
        networkAccessAllowed: Bool = true,
        preferredVideoAsset: AVAsset? = nil
    ) async throws -> Double {
        if let preferredVideoAsset,
           let sizeMB = try? localVideoFileSizeMB(for: preferredVideoAsset) {
            return sizeMB
        }

        // List screens must not read an entire video merely to calculate its size.
        // Full resource reads remain available to explicit compression operations.
        if preferredVideoAsset != nil, !networkAccessAllowed {
            throw VideoCompressionError.videoUnavailable
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizeVideo }) ??
            resources.first(where: { $0.type == .video }) else {
            throw VideoCompressionError.videoUnavailable
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = networkAccessAllowed

        let counterLock = NSLock()
        var byteCount: Int64 = 0

        let resourceManager = PHAssetResourceManager.default()
        let cancellation = PhotoLibraryResourceDataRequestCancellation(manager: resourceManager)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let requestID = resourceManager.requestData(
                    for: resource,
                    options: options,
                    dataReceivedHandler: { data in
                        counterLock.lock()
                        byteCount += Int64(data.count)
                        counterLock.unlock()
                    },
                    completionHandler: { error in
                        if cancellation.wasCancelled {
                            continuation.resume(throwing: CancellationError())
                            return
                        }

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
                cancellation.setRequestID(requestID)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func localVideoFileSizeMB(for asset: AVAsset) throws -> Double {
        guard let urlAsset = asset as? AVURLAsset, urlAsset.url.isFileURL else {
            throw VideoCompressionError.videoUnavailable
        }

        let values = try urlAsset.url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey])
        if let bytes = values.totalFileSize ?? values.fileSize {
            return max(Double(bytes) / 1_048_576, 0)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: urlAsset.url.path)
        guard let bytes = attributes[.size] as? NSNumber else {
            throw VideoCompressionError.videoUnavailable
        }
        return max(bytes.doubleValue / 1_048_576, 0)
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
        plan: VideoCompressionPlan,
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
        let outputDisplaySize = evenDisplayDimensions(from: plan.resolution.targetDisplaySize(for: displaySize))
        let encodedSize = outputEncodedDimensions(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            outputDisplaySize: outputDisplaySize
        )
        let sourceBitrate = sourceVideoBitrate(
            estimatedDataRate: Double(estimatedDataRate),
            originalSizeMB: originalSizeMB,
            duration: duration
        )
        let targetBitrate = targetVideoBitrate(
            sourceBitrate: sourceBitrate,
            sourceDisplaySize: displaySize,
            outputDisplaySize: outputDisplaySize,
            quality: plan.quality
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

        return VideoCompressionOutput(url: outputURL, outputDimensions: outputDisplaySize)
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
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
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
        let cancellation = VideoCompressionExportSessionCancellation()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let session = VideoCompressionExportSession(
                    reader: reader,
                    writer: writer,
                    videoInput: videoInput,
                    videoOutput: videoOutput,
                    audioInput: audioInput,
                    audioOutput: audioOutput,
                    duration: duration,
                    progressHandler: progressHandler,
                    continuation: continuation
                )
                cancellation.setSession(session)
                guard !cancellation.wasCancelled else { return }
                session.start()
            }
        } onCancel: {
            cancellation.cancel()
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

    private func evenDisplayDimensions(from displaySize: CGSize) -> CGSize {
        evenEncodedDimensions(from: displaySize)
    }

    private func outputEncodedDimensions(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        outputDisplaySize: CGSize
    ) -> CGSize {
        if transformSwapsAxes(preferredTransform) {
            return evenEncodedDimensions(from: CGSize(width: outputDisplaySize.height, height: outputDisplaySize.width))
        }

        let sourceDisplaySize = displayDimensions(naturalSize: naturalSize, transform: preferredTransform)
        let sourceAspect = sourceDisplaySize.width / max(sourceDisplaySize.height, 1)
        let naturalAspect = abs(naturalSize.width) / max(abs(naturalSize.height), 1)
        if abs(sourceAspect - naturalAspect) > 0.05 {
            return evenEncodedDimensions(from: CGSize(width: outputDisplaySize.height, height: outputDisplaySize.width))
        }

        return evenEncodedDimensions(from: outputDisplaySize)
    }

    private func transformSwapsAxes(_ transform: CGAffineTransform) -> Bool {
        abs(transform.b) > 0.5 || abs(transform.c) > 0.5
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
        sourceDisplaySize: CGSize,
        outputDisplaySize: CGSize,
        quality: VideoCompressionQuality
    ) -> Int {
        let pixelCount = max(outputDisplaySize.width * outputDisplaySize.height, 1)
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

        let sourcePixelCount = max(sourceDisplaySize.width * sourceDisplaySize.height, 1)
        let pixelRatio = min(max(pixelCount / sourcePixelCount, 0.08), 1)
        let bitrateFromQuality = sourceBitrate * pixelRatio * quality.targetVideoBitrateMultiplier
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
        try Task.checkCancellation()
        guard hasPhotoLibraryAccess else {
            throw VideoCompressionError.noLibraryAccess
        }

        let cancellation = PhotoLibraryWriteCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                var createdAssetIdentifier: String?
                guard !cancellation.wasCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                expectLocalLibraryChange()
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = originalAsset.creationDate
                    request.location = originalAsset.location
                    request.addResource(with: .video, fileURL: url, options: nil)
                    createdAssetIdentifier = request.placeholderForCreatedAsset?.localIdentifier
                }) { success, _ in
                    if cancellation.wasCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    if success {
                        continuation.resume(returning: createdAssetIdentifier)
                    } else {
                        continuation.resume(throwing: VideoCompressionError.saveFailed)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func requestImageData(for asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.version = .current
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                guard !isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                guard let data, !data.isEmpty else {
                    continuation.resume(throwing: ImageCompressionError.imageUnavailable)
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    private func exportCompressedImage(
        from imageData: Data,
        originalAsset: PHAsset,
        plan: ImageCompressionPlan,
        progressHandler: (@MainActor @Sendable (Double, String) -> Void)?
    ) async throws -> ImageCompressionOutput {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw ImageCompressionError.imageUnavailable
        }

        let originalSize = imagePixelSize(from: source, fallbackAsset: originalAsset)
        let targetSize = plan.size.targetPixelSize(for: originalSize)
        let maxPixelSize = max(Int(max(targetSize.width, targetSize.height).rounded()), 1)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoDelete-Image-Compressed-\(UUID().uuidString)")
            .appendingPathExtension("jpg")

        try? FileManager.default.removeItem(at: outputURL)

        await progressHandler?(0.42, L10n.string("正在压缩图片"))
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let outputImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            throw ImageCompressionError.exportFailed
        }

        let destinationProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: plan.quality.jpegQuality
        ]
        CGImageDestinationAddImage(destination, outputImage, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageCompressionError.exportFailed
        }

        await progressHandler?(0.78, L10n.string("正在确认压缩结果"))
        return ImageCompressionOutput(
            url: outputURL,
            outputDimensions: CGSize(width: outputImage.width, height: outputImage.height)
        )
    }

    private func imagePixelSize(from source: CGImageSource, fallbackAsset asset: PHAsset) -> CGSize {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? Double(asset.pixelWidth)
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? Double(asset.pixelHeight)
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    private func compressedImageFileSizeMB(at url: URL) throws -> Double {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = attributes[.size] as? NSNumber else {
            throw ImageCompressionError.exportFailed
        }
        return max(bytes.doubleValue / 1_048_576, 0)
    }

    private func saveCompressedImage(at url: URL, originalAsset: PHAsset) async throws -> String? {
        guard hasPhotoLibraryAccess else {
            throw ImageCompressionError.noLibraryAccess
        }

        return try await withCheckedThrowingContinuation { continuation in
            var createdAssetIdentifier: String?
            let resourceOptions = PHAssetResourceCreationOptions()
            resourceOptions.uniformTypeIdentifier = UTType.jpeg.identifier

            expectLocalLibraryChange()
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = originalAsset.creationDate
                request.location = originalAsset.location
                request.addResource(with: .photo, fileURL: url, options: resourceOptions)
                createdAssetIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }) { success, _ in
                if success {
                    continuation.resume(returning: createdAssetIdentifier)
                } else {
                    continuation.resume(throwing: ImageCompressionError.saveFailed)
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
            scheduleRebuildCachedAssets(from: changes.fetchResultAfterChanges)
            return
        }
        cancelPendingRebuildCachedAssets()

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
        reloadPhotoLibraryAfterCurrentLoadIfNeeded()
    }

    private func cancelPendingRebuildCachedAssets() {
        rebuildCachedAssetsWorkItem?.cancel()
        rebuildCachedAssetsWorkItem = nil
        rebuildCachedAssetsGeneration += 1
    }

    private func scheduleRebuildCachedAssets(
        from fetchResult: PHFetchResult<PHAsset>,
        delay: TimeInterval = 0.35,
        completion: (() -> Void)? = nil
    ) {
        rebuildCachedAssetsWorkItem?.cancel()
        rebuildCachedAssetsGeneration += 1
        let generation = rebuildCachedAssetsGeneration
        let workItem = DispatchWorkItem { [weak self] in
            self?.rebuildCachedAssets(from: fetchResult, generation: generation, completion: completion)
        }
        rebuildCachedAssetsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func rebuildCachedAssets(
        from fetchResult: PHFetchResult<PHAsset>,
        generation: Int? = nil,
        completion: (() -> Void)? = nil
    ) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            var photos: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                photos.append(asset)
            }

            let screenPixelSize = Self.currentScreenPixelSize()
            self.categorizePhotos(photos, screenPixelSize: screenPixelSize) { videos, screenshots, livePhotos, favorites in
                DispatchQueue.main.async {
                    if let generation, self.rebuildCachedAssetsGeneration != generation {
                        return
                    }
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
                    if let generation, self.rebuildCachedAssetsGeneration == generation {
                        self.rebuildCachedAssetsWorkItem = nil
                    }
                    self.onLibraryDataChanged?()
                    completion?()
                    self.reloadPhotoLibraryAfterCurrentLoadIfNeeded()
                }
            }
        }
    }

    private func reloadPhotoLibraryAfterCurrentLoadIfNeeded() {
        guard needsPhotoLibraryReloadAfterCurrentLoad else { return }
        guard hasPhotoLibraryAccess else {
            needsPhotoLibraryReloadAfterCurrentLoad = false
            return
        }
        guard !isLoading, !isRestoringSnapshot else { return }

        needsPhotoLibraryReloadAfterCurrentLoad = false
        loadPhotos(preserveExistingData: true)
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
        cachedCounts = PhotoLibraryCachedCounts(
            totalPhotos: allPhotos.count,
            videos: videos.count,
            screenshots: screenshots.count,
            livePhotos: livePhotos.count,
            favorites: favorites.count
        )
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

    func addPhotosToAlbum(_ assets: [PHAsset], album: PHAssetCollection, completion: @escaping (Bool, Int, Error?) -> Void) {
        guard hasPhotoLibraryAccess else {
            completion(false, 0, PhotoLibraryWriteError.noLibraryAccess)
            return
        }

        guard album.assetCollectionType == .album, album.canPerform(.addContent) else {
            completion(false, 0, PhotoLibraryWriteError.unsupportedAlbumAdd)
            return
        }

        let uniqueAssets = uniqueAssets(assets)
        guard !uniqueAssets.isEmpty else {
            completion(true, 0, nil)
            return
        }

        let albumAssets = PHAsset.fetchAssets(in: album, options: nil)
        var existingAssetIDs: Set<String> = []
        albumAssets.enumerateObjects { asset, _, _ in
            existingAssetIDs.insert(asset.localIdentifier)
        }
        let assetsToAdd = uniqueAssets.filter { !existingAssetIDs.contains($0.localIdentifier) }
        guard !assetsToAdd.isEmpty else {
            completion(true, 0, nil)
            return
        }

        PHPhotoLibrary.shared().performChanges({
            if let addAssetRequest = PHAssetCollectionChangeRequest(for: album) {
                addAssetRequest.addAssets(assetsToAdd as NSArray)
            }
        }) { success, error in
            DispatchQueue.main.async {
                let verifiedSuccess = success && self.album(
                    withIdentifier: album.localIdentifier,
                    containsAllAssetIdentifiers: assetsToAdd.map(\.localIdentifier)
                )
                completion(
                    verifiedSuccess,
                    verifiedSuccess ? assetsToAdd.count : 0,
                    verifiedSuccess ? nil : (error ?? PhotoLibraryWriteError.unsupportedAlbumAdd)
                )
            }
        }
    }

    func removePhotosFromAlbum(_ assets: [PHAsset], album: PHAssetCollection, completion: @escaping (Bool, Error?) -> Void) {
        guard hasPhotoLibraryAccess else {
            completion(false, PhotoLibraryWriteError.noLibraryAccess)
            return
        }

        guard album.assetCollectionType == .album, album.canPerform(.removeContent) else {
            completion(false, PhotoLibraryWriteError.unsupportedAlbumRemove)
            return
        }

        let uniqueAssets = uniqueAssets(assets)
        guard !uniqueAssets.isEmpty else {
            completion(true, nil)
            return
        }

        let albumAssets = PHAsset.fetchAssets(in: album, options: nil)
        var existingAssetIDs: Set<String> = []
        albumAssets.enumerateObjects { asset, _, _ in
            existingAssetIDs.insert(asset.localIdentifier)
        }
        let assetsToRemove = uniqueAssets.filter { existingAssetIDs.contains($0.localIdentifier) }
        guard !assetsToRemove.isEmpty else {
            completion(true, nil)
            return
        }

        PHPhotoLibrary.shared().performChanges({
            if let removeAssetRequest = PHAssetCollectionChangeRequest(for: album) {
                removeAssetRequest.removeAssets(assetsToRemove as NSArray)
            }
        }) { success, error in
            DispatchQueue.main.async {
                let verifiedSuccess = success && self.album(
                    withIdentifier: album.localIdentifier,
                    excludesAllAssetIdentifiers: assetsToRemove.map(\.localIdentifier)
                )
                completion(verifiedSuccess, verifiedSuccess ? nil : (error ?? PhotoLibraryWriteError.unsupportedAlbumRemove))
            }
        }
    }

    private func album(withIdentifier identifier: String, containsAllAssetIdentifiers assetIdentifiers: [String]) -> Bool {
        guard let collection = fetchAlbum(withIdentifier: identifier) else { return false }
        let fetchResult = PHAsset.fetchAssets(in: collection, options: nil)
        var containedIdentifiers: Set<String> = []
        fetchResult.enumerateObjects { asset, _, _ in
            containedIdentifiers.insert(asset.localIdentifier)
        }
        return assetIdentifiers.allSatisfy { containedIdentifiers.contains($0) }
    }

    private func album(withIdentifier identifier: String, excludesAllAssetIdentifiers assetIdentifiers: [String]) -> Bool {
        guard let collection = fetchAlbum(withIdentifier: identifier) else { return false }
        let fetchResult = PHAsset.fetchAssets(in: collection, options: nil)
        var containedIdentifiers: Set<String> = []
        fetchResult.enumerateObjects { asset, _, _ in
            containedIdentifiers.insert(asset.localIdentifier)
        }
        return assetIdentifiers.allSatisfy { !containedIdentifiers.contains($0) }
    }

    private func fetchAlbum(withIdentifier identifier: String) -> PHAssetCollection? {
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier],
            options: nil
        )
        return collections.firstObject
    }

    // MARK: - Statistics

    var totalPhotosCount: Int { allPhotos.count }
    var videosCount: Int { videos.count }
    var screenshotsCount: Int { screenshots.count }
    var livePhotosCount: Int { livePhotos.count }
    var favoritesCount: Int { favorites.count }

    var displayTotalPhotosCount: Int {
        PhotoLibraryDisplayCountResolver.count(
            current: totalPhotosCount,
            cached: cachedCounts?.totalPhotos,
            hasLoadedPhotoLibrary: hasLoadedPhotoLibrary
        )
    }

    var displayVideosCount: Int {
        PhotoLibraryDisplayCountResolver.count(
            current: videosCount,
            cached: cachedCounts?.videos,
            hasLoadedPhotoLibrary: hasLoadedPhotoLibrary
        )
    }

    var displayScreenshotsCount: Int {
        PhotoLibraryDisplayCountResolver.count(
            current: screenshotsCount,
            cached: cachedCounts?.screenshots,
            hasLoadedPhotoLibrary: hasLoadedPhotoLibrary
        )
    }

    var displayLivePhotosCount: Int {
        PhotoLibraryDisplayCountResolver.count(
            current: livePhotosCount,
            cached: cachedCounts?.livePhotos,
            hasLoadedPhotoLibrary: hasLoadedPhotoLibrary
        )
    }

    var displayFavoritesCount: Int {
        PhotoLibraryDisplayCountResolver.count(
            current: favoritesCount,
            cached: cachedCounts?.favorites,
            hasLoadedPhotoLibrary: hasLoadedPhotoLibrary
        )
    }

    private func uniqueAssets(_ assets: [PHAsset]) -> [PHAsset] {
        var seenIdentifiers = Set<String>()
        return assets.filter { asset in
            seenIdentifiers.insert(asset.localIdentifier).inserted
        }
    }

}

private final class PhotoLibraryImageRequestCancellation: @unchecked Sendable {
    private let manager: PHImageManager
    private let lock = NSLock()
    private var requestID: PHImageRequestID?
    private var isCancelled = false

    init(manager: PHImageManager) {
        self.manager = manager
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    func setRequestID(_ requestID: PHImageRequestID) {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = isCancelled
        lock.unlock()

        if shouldCancel {
            manager.cancelImageRequest(requestID)
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        lock.unlock()

        if let requestID {
            manager.cancelImageRequest(requestID)
        }
    }
}

private final class PhotoLibraryResourceDataRequestCancellation: @unchecked Sendable {
    private let manager: PHAssetResourceManager
    private let lock = NSLock()
    private var requestID: PHAssetResourceDataRequestID?
    private var isCancelled = false

    init(manager: PHAssetResourceManager) {
        self.manager = manager
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    func setRequestID(_ requestID: PHAssetResourceDataRequestID) {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = isCancelled
        lock.unlock()

        if shouldCancel {
            manager.cancelDataRequest(requestID)
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        lock.unlock()

        if let requestID {
            manager.cancelDataRequest(requestID)
        }
    }
}

private final class PhotoLibraryWriteCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }
}

private final class VideoCompressionExportSessionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var session: VideoCompressionExportSession?
    private var isCancelled = false

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    func setSession(_ session: VideoCompressionExportSession) {
        lock.lock()
        self.session = session
        let shouldCancel = isCancelled
        lock.unlock()

        if shouldCancel {
            session.cancel()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let session = session
        lock.unlock()

        session?.cancel()
    }
}

// AVFoundation drives these non-Sendable reader/writer objects through its own serial media queues.
private final class VideoCompressionExportSession: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let videoOutput: AVAssetReaderTrackOutput
    private let audioInput: AVAssetWriterInput?
    private let audioOutput: AVAssetReaderTrackOutput?
    private let durationSeconds: Double
    private let progressHandler: (@MainActor @Sendable (Double, String) -> Void)?
    private let continuation: CheckedContinuation<Void, Error>

    private let stateLock = NSLock()
    private var didComplete = false
    private var isFinishing = false
    private var videoFinished = false
    private var audioFinished: Bool
    private var lastProgressUpdate = Date.distantPast

    init(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        videoOutput: AVAssetReaderTrackOutput,
        audioInput: AVAssetWriterInput?,
        audioOutput: AVAssetReaderTrackOutput?,
        duration: CMTime,
        progressHandler: (@MainActor @Sendable (Double, String) -> Void)?,
        continuation: CheckedContinuation<Void, Error>
    ) {
        self.reader = reader
        self.writer = writer
        self.videoInput = videoInput
        self.videoOutput = videoOutput
        self.audioInput = audioInput
        self.audioOutput = audioOutput
        self.durationSeconds = max(CMTimeGetSeconds(duration), 1)
        self.progressHandler = progressHandler
        self.continuation = continuation
        self.audioFinished = audioInput == nil || audioOutput == nil
    }

    func start() {
        guard !hasCompleted else { return }
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

        let videoQueue = DispatchQueue(label: "PhotoDelete.VideoCompression.video")
        videoInput.requestMediaDataWhenReady(on: videoQueue) { [self] in
            drainVideoSamples()
        }

        guard let audioInput else {
            return
        }

        let audioQueue = DispatchQueue(label: "PhotoDelete.VideoCompression.audio")
        audioInput.requestMediaDataWhenReady(on: audioQueue) { [self] in
            drainAudioSamples()
        }
    }

    func cancel() {
        reader.cancelReading()
        writer.cancelWriting()
        complete(.failure(CancellationError()))
    }

    private func drainVideoSamples() {
        while videoInput.isReadyForMoreMediaData {
            guard !hasCompleted else { return }
            guard let sampleBuffer = videoOutput.copyNextSampleBuffer() else {
                videoInput.markAsFinished()
                markVideoFinished()
                return
            }

            guard !hasCompleted else { return }
            guard videoInput.append(sampleBuffer) else {
                fail(writer.error ?? VideoCompressionError.exportFailed)
                return
            }

            reportProgressIfNeeded(for: sampleBuffer)
        }
    }

    private func drainAudioSamples() {
        guard !hasCompleted else { return }
        guard let audioInput, let audioOutput else {
            markAudioFinished()
            return
        }

        while audioInput.isReadyForMoreMediaData {
            guard !hasCompleted else { return }
            guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
                audioInput.markAsFinished()
                markAudioFinished()
                return
            }

            guard !hasCompleted else { return }
            guard audioInput.append(sampleBuffer) else {
                fail(writer.error ?? VideoCompressionError.exportFailed)
                return
            }
        }
    }

    private var hasCompleted: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return didComplete
    }

    private func reportProgressIfNeeded(for sampleBuffer: CMSampleBuffer) {
        let now = Date.now
        guard now.timeIntervalSince(lastProgressUpdate) >= 0.2 else {
            return
        }

        lastProgressUpdate = now
        let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let exportProgress = min(max(seconds / durationSeconds, 0), 1)
        let displayedProgress = 0.16 + exportProgress * 0.7
        let handler = progressHandler

        Task { @MainActor in
            handler?(displayedProgress, L10n.string("正在压缩视频"))
        }
    }

    private func markVideoFinished() {
        stateLock.lock()
        videoFinished = true
        stateLock.unlock()
        finishIfReady()
    }

    private func markAudioFinished() {
        stateLock.lock()
        audioFinished = true
        stateLock.unlock()
        finishIfReady()
    }

    private func fail(_ error: Error) {
        reader.cancelReading()
        writer.cancelWriting()
        complete(.failure(error))
    }

    private func finishIfReady() {
        stateLock.lock()
        let shouldFinish = videoFinished && audioFinished && !didComplete && !isFinishing
        if shouldFinish {
            isFinishing = true
        }
        stateLock.unlock()

        guard shouldFinish else { return }
        writer.finishWriting { [self] in
            if writer.status == .completed {
                complete(.success(()))
            } else if writer.status == .cancelled {
                complete(.failure(CancellationError()))
            } else {
                complete(.failure(writer.error ?? VideoCompressionError.exportFailed))
            }
        }
    }

    private func complete(_ result: Result<Void, Error>) {
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
}

private enum PhotoLibraryWriteError: LocalizedError {
    case noLibraryAccess
    case unsupportedDelete
    case unsupportedFavorite
    case unsupportedAlbumAdd
    case unsupportedAlbumRemove
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
        case .unsupportedAlbumRemove:
            return L10n.string("这个相册不支持移出照片。")
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

private enum ImageCompressionError: LocalizedError {
    case noLibraryAccess
    case notImage
    case livePhotoUnsupported
    case imageUnavailable
    case exportFailed
    case notWorthCompressing
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noLibraryAccess:
            return L10n.string("当前照片权限不可用")
        case .notImage:
            return L10n.string("这个项目不是图片")
        case .livePhotoUnsupported:
            return L10n.string("实况照片暂不参与图片压缩")
        case .imageUnavailable:
            return L10n.string("无法读取这张图片")
        case .exportFailed:
            return L10n.string("图片压缩失败，请稍后再试。")
        case .notWorthCompressing:
            return L10n.string("这张图片已经足够小")
        case .saveFailed:
            return L10n.string("无法保存压缩图片")
        }
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension PhotoLibraryManager: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            if self.isLoading || self.isRestoringSnapshot {
                let hasTrackedFetchResult = self.allPhotosResult != nil
                let hasChangeDetails = self.allPhotosResult.flatMap {
                    changeInstance.changeDetails(for: $0)
                } != nil
                if PhotoLibraryDeferredReloadPolicy.shouldDeferReload(
                    isLoading: self.isLoading,
                    isRestoringSnapshot: self.isRestoringSnapshot,
                    hasTrackedFetchResult: hasTrackedFetchResult,
                    hasChangeDetails: hasChangeDetails
                ) {
                    self.needsPhotoLibraryReloadAfterCurrentLoad = true
                }
                return
            }

            // Before the first fetch starts, the upcoming scan already reads the latest library state.
            guard self.hasLoadedPhotoLibrary else { return }

            guard let fetchResult = self.allPhotosResult else {
                self.onLibraryDataChanged?()
                return
            }

            guard let changes = changeInstance.changeDetails(for: fetchResult) else {
                self.onLibraryDataChanged?()
                return
            }

            self.allPhotosResult = changes.fetchResultAfterChanges

            let isExpectedLocalChange = self.shouldApplyChangeIncrementally()

            if changes.hasIncrementalChanges && !changes.hasMoves {
                self.applyIncrementalPhotoChanges(changes)
            } else if isExpectedLocalChange {
                self.applyIncrementalPhotoChanges(changes)
            } else {
                self.scheduleRebuildCachedAssets(from: changes.fetchResultAfterChanges)
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
