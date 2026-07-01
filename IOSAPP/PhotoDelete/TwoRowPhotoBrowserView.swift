import SwiftUI
import Photos
import AVFoundation
import UIKit

struct TwoRowPhotoBrowserView: UIViewRepresentable {
    let assets: [PHAsset]
    let photoLibraryManager: PhotoLibraryManager
    let currentIndex: Int
    let reviewedAssetIDs: Set<String>
    let pendingReviewedAssetIDs: Set<String>
    let deleteCandidateIDs: Set<String>
    let favoriteCandidateIDs: Set<String>
    let albumFilingAssetIDs: Set<String>
    let albumFiledAssetIDs: Set<String>
    let playingVideoAssetID: String?
    let rowHeight: CGFloat
    let thumbnailTargetSize: CGSize
    let selectedTargetSize: CGSize
    let onSelectIndex: (Int) -> Void
    let onOpenAsset: (PHAsset) -> Void
    let onSwipeUpToDelete: (PHAsset, Int) -> Void
    let onCancelDelete: (PHAsset, Int) -> Void
    let onStopVideoPlayback: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(view: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = TwoRowPhotoBrowserLayout()
        layout.configure(
            metrics: Self.metrics(for: assets),
            rowHeight: rowHeight,
            rowSpacing: 12,
            itemSpacing: 12,
            horizontalInset: 18,
            verticalInset: 4,
            bottomRowInset: min(rowHeight * 0.34, 64)
        )

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.decelerationRate = .fast
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.prefetchDataSource = context.coordinator
        collectionView.register(TwoRowPhotoBrowserCell.self, forCellWithReuseIdentifier: TwoRowPhotoBrowserCell.reuseIdentifier)
        context.coordinator.collectionView = collectionView
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.update(view: self, collectionView: collectionView)
    }

    private static func metrics(for assets: [PHAsset]) -> [TwoRowPhotoBrowserLayout.ItemMetric] {
        assets.map { asset in
            let aspectRatio: CGFloat
            if asset.pixelHeight > 0 {
                aspectRatio = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
            } else {
                aspectRatio = 0.78
            }
            return TwoRowPhotoBrowserLayout.ItemMetric(aspectRatio: aspectRatio)
        }
    }

    struct AssetSignature: Equatable {
        let count: Int
        let firstID: String?
        let lastID: String?

        init(assets: [PHAsset]) {
            count = assets.count
            firstID = assets.first?.localIdentifier
            lastID = assets.last?.localIdentifier
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
        private var assets: [PHAsset]
        private var assetSignature: AssetSignature
        private var photoLibraryManager: PhotoLibraryManager
        private var currentIndex: Int
        private var reviewedAssetIDs: Set<String>
        private var pendingReviewedAssetIDs: Set<String>
        private var deleteCandidateIDs: Set<String>
        private var favoriteCandidateIDs: Set<String>
        private var albumFilingAssetIDs: Set<String>
        private var albumFiledAssetIDs: Set<String>
        private var playingVideoAssetID: String?
        private var rowHeight: CGFloat
        private var thumbnailTargetSize: CGSize
        private var selectedTargetSize: CGSize
        private var onSelectIndex: (Int) -> Void
        private var onOpenAsset: (PHAsset) -> Void
        private var onSwipeUpToDelete: (PHAsset, Int) -> Void
        private var onCancelDelete: (PHAsset, Int) -> Void
        private var onStopVideoPlayback: () -> Void
        private var suppressNextProgrammaticScroll = false

        weak var collectionView: UICollectionView?

        init(view: TwoRowPhotoBrowserView) {
            assets = view.assets
            assetSignature = AssetSignature(assets: view.assets)
            photoLibraryManager = view.photoLibraryManager
            currentIndex = view.currentIndex
            reviewedAssetIDs = view.reviewedAssetIDs
            pendingReviewedAssetIDs = view.pendingReviewedAssetIDs
            deleteCandidateIDs = view.deleteCandidateIDs
            favoriteCandidateIDs = view.favoriteCandidateIDs
            albumFilingAssetIDs = view.albumFilingAssetIDs
            albumFiledAssetIDs = view.albumFiledAssetIDs
            playingVideoAssetID = view.playingVideoAssetID
            rowHeight = view.rowHeight
            thumbnailTargetSize = view.thumbnailTargetSize
            selectedTargetSize = view.selectedTargetSize
            onSelectIndex = view.onSelectIndex
            onOpenAsset = view.onOpenAsset
            onSwipeUpToDelete = view.onSwipeUpToDelete
            onCancelDelete = view.onCancelDelete
            onStopVideoPlayback = view.onStopVideoPlayback
            super.init()
        }

        func update(view: TwoRowPhotoBrowserView, collectionView: UICollectionView) {
            let nextSignature = AssetSignature(assets: view.assets)
            let assetsChanged = nextSignature != assetSignature
            let rowHeightChanged = rowHeight != view.rowHeight
            let targetSizeChanged = thumbnailTargetSize != view.thumbnailTargetSize ||
                selectedTargetSize != view.selectedTargetSize
            let currentIndexChanged = currentIndex != view.currentIndex

            photoLibraryManager = view.photoLibraryManager
            reviewedAssetIDs = view.reviewedAssetIDs
            pendingReviewedAssetIDs = view.pendingReviewedAssetIDs
            deleteCandidateIDs = view.deleteCandidateIDs
            favoriteCandidateIDs = view.favoriteCandidateIDs
            albumFilingAssetIDs = view.albumFilingAssetIDs
            albumFiledAssetIDs = view.albumFiledAssetIDs
            playingVideoAssetID = view.playingVideoAssetID
            onSelectIndex = view.onSelectIndex
            onOpenAsset = view.onOpenAsset
            onSwipeUpToDelete = view.onSwipeUpToDelete
            onCancelDelete = view.onCancelDelete
            onStopVideoPlayback = view.onStopVideoPlayback

            if assetsChanged {
                assets = view.assets
                assetSignature = nextSignature
            }

            currentIndex = view.currentIndex
            rowHeight = view.rowHeight
            thumbnailTargetSize = view.thumbnailTargetSize
            selectedTargetSize = view.selectedTargetSize

            if let layout = collectionView.collectionViewLayout as? TwoRowPhotoBrowserLayout,
               assetsChanged || rowHeightChanged {
                layout.configure(
                    metrics: assetsChanged ? TwoRowPhotoBrowserView.metrics(for: view.assets) : layout.metrics,
                    rowHeight: view.rowHeight,
                    rowSpacing: 12,
                    itemSpacing: 12,
                    horizontalInset: 18,
                    verticalInset: 4,
                    bottomRowInset: min(view.rowHeight * 0.34, 64)
                )
            }

            if assetsChanged {
                collectionView.reloadData()
                collectionView.layoutIfNeeded()
                scrollToCurrentPhoto(in: collectionView, animated: false)
                return
            }

            if targetSizeChanged {
                configureVisibleCells(in: collectionView)
            } else {
                configureVisibleCells(in: collectionView)
            }

            if currentIndexChanged {
                guard !suppressNextProgrammaticScroll else {
                    suppressNextProgrammaticScroll = false
                    return
                }
                scrollToCurrentPhoto(in: collectionView, animated: collectionView.window != nil)
            }
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            assets.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: TwoRowPhotoBrowserCell.reuseIdentifier,
                for: indexPath
            )

            guard let photoCell = cell as? TwoRowPhotoBrowserCell else {
                return cell
            }
            configure(photoCell, at: indexPath.item)
            return photoCell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard assets.indices.contains(indexPath.item) else { return }
            let asset = assets[indexPath.item]
            if indexPath.item == currentIndex {
                onOpenAsset(asset)
            } else {
                onSelectIndex(indexPath.item)
            }
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let prefetchAssets = indexPaths.compactMap { indexPath in
                assets.indices.contains(indexPath.item) ? assets[indexPath.item] : nil
            }
            photoLibraryManager.preloadGridThumbnailsForAssets(
                prefetchAssets,
                size: thumbnailTargetSize,
                maxCount: min(prefetchAssets.count, 18)
            )
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            let cancelledAssets = indexPaths.compactMap { indexPath in
                assets.indices.contains(indexPath.item) ? assets[indexPath.item] : nil
            }
            photoLibraryManager.stopCachingGridThumbnails(cancelledAssets, size: thumbnailTargetSize)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            selectCenteredVisibleItemIfNeeded()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                selectCenteredVisibleItemIfNeeded()
            }
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            configureVisibleCells(in: scrollView as? UICollectionView ?? collectionView)
        }

        private func configureVisibleCells(in collectionView: UICollectionView?) {
            guard let collectionView else { return }
            for case let cell as TwoRowPhotoBrowserCell in collectionView.visibleCells {
                guard let indexPath = collectionView.indexPath(for: cell) else { continue }
                configure(cell, at: indexPath.item)
            }
        }

        private func configure(_ cell: TwoRowPhotoBrowserCell, at index: Int) {
            guard assets.indices.contains(index) else { return }
            let asset = assets[index]
            let id = asset.localIdentifier
            let thumbnailRequestTargetSize = requestTargetSize(
                forItemAt: index,
                maximumTargetSize: thumbnailTargetSize
            )
            let selectedRequestTargetSize = requestTargetSize(
                forItemAt: index,
                maximumTargetSize: selectedTargetSize
            )
            cell.configure(
                asset: asset,
                index: index,
                photoLibraryManager: photoLibraryManager,
                isSelected: index == currentIndex,
                isReviewed: reviewedAssetIDs.contains(id) || pendingReviewedAssetIDs.contains(id),
                isInDeleteCandidates: deleteCandidateIDs.contains(id),
                isInFavoriteCandidates: favoriteCandidateIDs.contains(id),
                isBeingFiledToAlbum: albumFilingAssetIDs.contains(id),
                isFiledToAlbum: albumFiledAssetIDs.contains(id),
                isScreenshot: photoLibraryManager.isScreenshot(asset),
                isVideo: asset.mediaType == .video,
                isVideoPlaying: playingVideoAssetID == id,
                thumbnailTargetSize: thumbnailRequestTargetSize,
                selectedTargetSize: selectedRequestTargetSize,
                prefersHighQualityPreview: abs(index - currentIndex) <= 1,
                onSwipeUpToDelete: { [weak self] asset, index in
                    self?.onSwipeUpToDelete(asset, index)
                },
                onCancelDelete: { [weak self] asset, index in
                    self?.onCancelDelete(asset, index)
                },
                onStopVideoPlayback: { [weak self] in
                    self?.onStopVideoPlayback()
                }
            )
        }

        private func requestTargetSize(forItemAt index: Int, maximumTargetSize: CGSize) -> CGSize {
            let displaySize: CGSize
            if let collectionView,
               let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) {
                displaySize = attributes.bounds.size
            } else {
                displaySize = CGSize(width: rowHeight, height: rowHeight)
            }

            return TwoRowPhotoBrowserImageSizing.requestTargetSize(
                displaySize: displaySize,
                maximumTargetSize: maximumTargetSize,
                rowHeight: rowHeight
            )
        }

        private func scrollToCurrentPhoto(in collectionView: UICollectionView, animated: Bool) {
            guard assets.indices.contains(currentIndex) else { return }
            let indexPath = IndexPath(item: currentIndex, section: 0)
            collectionView.layoutIfNeeded()
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
        }

        private func selectCenteredVisibleItemIfNeeded() {
            guard let collectionView, !assets.isEmpty else { return }
            let centerX = collectionView.bounds.midX + collectionView.contentOffset.x
            let visibleAttributes = collectionView.indexPathsForVisibleItems.compactMap {
                collectionView.layoutAttributesForItem(at: $0)
            }
            guard let centered = visibleAttributes.min(by: {
                abs($0.frame.midX - centerX) < abs($1.frame.midX - centerX)
            }) else {
                return
            }

            let index = centered.indexPath.item
            guard index != currentIndex, assets.indices.contains(index) else { return }
            suppressNextProgrammaticScroll = true
            onSelectIndex(index)
        }
    }
}

final class TwoRowPhotoBrowserLayout: UICollectionViewLayout {
    struct ItemMetric: Equatable {
        let aspectRatio: CGFloat
    }

    private(set) var metrics: [ItemMetric] = []
    private var frames: [CGRect] = []
    private var laneIndices: [[Int]] = [[], []]
    private var contentSize: CGSize = .zero
    private var maxItemWidth: CGFloat = 0
    private var cachedBoundsWidth: CGFloat = 0

    private var rowHeight: CGFloat = 160
    private var rowSpacing: CGFloat = 12
    private var itemSpacing: CGFloat = 12
    private var horizontalInset: CGFloat = 18
    private var verticalInset: CGFloat = 4
    private var bottomRowInset: CGFloat = 48

    func configure(
        metrics: [ItemMetric],
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        itemSpacing: CGFloat,
        horizontalInset: CGFloat,
        verticalInset: CGFloat,
        bottomRowInset: CGFloat
    ) {
        self.metrics = metrics
        self.rowHeight = rowHeight
        self.rowSpacing = rowSpacing
        self.itemSpacing = itemSpacing
        self.horizontalInset = horizontalInset
        self.verticalInset = verticalInset
        self.bottomRowInset = bottomRowInset
        invalidateLayout()
    }

    override func prepare() {
        super.prepare()
        let boundsWidth = collectionView?.bounds.width ?? cachedBoundsWidth
        guard frames.count != metrics.count || cachedBoundsWidth != boundsWidth else { return }
        cachedBoundsWidth = boundsWidth
        let placement = TwoRowPhotoBrowserPlacement.makeFrames(
            aspectRatios: metrics.map(\.aspectRatio),
            containerWidth: boundsWidth,
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            itemSpacing: itemSpacing,
            horizontalInset: horizontalInset,
            verticalInset: verticalInset,
            bottomRowInset: bottomRowInset
        )
        frames = placement.frames
        laneIndices = placement.laneIndices
        contentSize = placement.contentSize
        maxItemWidth = placement.maxItemWidth
    }

    override var collectionViewContentSize: CGSize {
        contentSize
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard !frames.isEmpty else { return [] }
        var attributes: [UICollectionViewLayoutAttributes] = []
        attributes.reserveCapacity(32)

        let searchMinX = rect.minX - maxItemWidth - itemSpacing
        let searchMaxX = rect.maxX + itemSpacing
        for lane in laneIndices {
            var lanePosition = lowerBound(in: lane, minX: searchMinX)
            while lanePosition < lane.count {
                let itemIndex = lane[lanePosition]
                let frame = frames[itemIndex]
                if frame.minX > searchMaxX {
                    break
                }
                if frame.intersects(rect) {
                    attributes.append(layoutAttributes(for: itemIndex, frame: frame))
                }
                lanePosition += 1
            }
        }

        return attributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard frames.indices.contains(indexPath.item) else { return nil }
        return layoutAttributes(for: indexPath.item, frame: frames[indexPath.item])
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != cachedBoundsWidth
    }

    private func layoutAttributes(for itemIndex: Int, frame: CGRect) -> UICollectionViewLayoutAttributes {
        let indexPath = IndexPath(item: itemIndex, section: 0)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frame
        return attributes
    }

    private func lowerBound(in lane: [Int], minX: CGFloat) -> Int {
        var low = 0
        var high = lane.count
        while low < high {
            let middle = (low + high) / 2
            if frames[lane[middle]].minX < minX {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}

struct TwoRowPhotoBrowserPlacement {
    let frames: [CGRect]
    let laneIndices: [[Int]]
    let contentSize: CGSize
    let maxItemWidth: CGFloat

    static func makeFrames(
        aspectRatios: [CGFloat],
        containerWidth: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        itemSpacing: CGFloat,
        horizontalInset: CGFloat,
        verticalInset: CGFloat,
        bottomRowInset: CGFloat
    ) -> TwoRowPhotoBrowserPlacement {
        guard !aspectRatios.isEmpty else {
            return TwoRowPhotoBrowserPlacement(
                frames: [],
                laneIndices: [[], []],
                contentSize: CGSize(width: containerWidth, height: rowHeight * 2 + rowSpacing + verticalInset * 2),
                maxItemWidth: 0
            )
        }

        let maxWidth = min(max(containerWidth * 0.72, rowHeight * 0.72), rowHeight * 1.72)
        let minWidth = rowHeight * 0.58
        var laneX: [CGFloat] = [0, bottomRowInset]
        var laneIndices: [[Int]] = [[], []]
        var frames: [CGRect] = []
        frames.reserveCapacity(aspectRatios.count)
        var maxItemWidth: CGFloat = 0

        for (index, aspectRatio) in aspectRatios.enumerated() {
            let normalizedAspect = min(max(aspectRatio, 0.56), 1.72)
            let width = min(max(rowHeight * normalizedAspect, minWidth), maxWidth)
            let lane = laneX[0] <= laneX[1] ? 0 : 1
            let x = horizontalInset + laneX[lane]
            let y = verticalInset + CGFloat(lane) * (rowHeight + rowSpacing)
            frames.append(CGRect(x: x, y: y, width: width, height: rowHeight))
            laneIndices[lane].append(index)
            laneX[lane] += width + itemSpacing
            maxItemWidth = max(maxItemWidth, width)
        }

        let contentWidth = max(laneX[0], laneX[1]) + horizontalInset * 2
        let contentHeight = rowHeight * 2 + rowSpacing + verticalInset * 2
        return TwoRowPhotoBrowserPlacement(
            frames: frames,
            laneIndices: laneIndices,
            contentSize: CGSize(width: max(containerWidth, contentWidth), height: contentHeight),
            maxItemWidth: maxItemWidth
        )
    }
}

enum TwoRowPhotoBrowserImageSizing {
    static func requestTargetSize(
        displaySize: CGSize,
        maximumTargetSize: CGSize,
        rowHeight: CGFloat
    ) -> CGSize {
        guard displaySize.width > 0,
              displaySize.height > 0,
              maximumTargetSize.width > 0,
              maximumTargetSize.height > 0,
              rowHeight > 0 else {
            return maximumTargetSize
        }

        let scale = max(maximumTargetSize.height / rowHeight, 1)
        return CGSize(
            width: min(ceil(displaySize.width * scale), maximumTargetSize.width),
            height: min(ceil(displaySize.height * scale), maximumTargetSize.height)
        )
    }
}

private final class TwoRowPhotoBrowserCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static let reuseIdentifier = "TwoRowPhotoBrowserCell"

    private let containerView = UIView()
    private let imageView = UIImageView()
    private let placeholderView = UIView()
    private let placeholderIcon = UIImageView(image: UIImage(systemName: "photo"))
    private let badgeStackView = UIStackView()
    private let stateOverlayView = UIView()
    private let stateIconView = UIImageView()
    private let stateTitleLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let deleteCueView = UIView()
    private let deleteCueIconView = UIImageView(image: UIImage(systemName: "trash.fill"))
    private let deleteCueLabel = UILabel()
    private let closeVideoButton = UIButton(type: .system)
    private let videoContainerView = UIView()

    private var representedAssetID: String?
    private var representedIndex: Int?
    private var representedAsset: PHAsset?
    private weak var photoLibraryManager: PhotoLibraryManager?
    private var thumbnailRequestID: PHImageRequestID?
    private var fallbackRequestID: PHImageRequestID?
    private var previewRequestID: PHImageRequestID?
    private var previewWorkItem: DispatchWorkItem?
    private var videoRequestID: PHImageRequestID?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loadedThumbnailTargetSize: CGSize = .zero
    private var loadedSelectedTargetSize: CGSize = .zero
    private var loadedHighQualityAssetID: String?
    private var loadedHighQualityTargetSize: CGSize = .zero
    private var prefersHighQualityPreview = false
    private var lastBadgeState: (isVideo: Bool, isScreenshot: Bool)?
    private var isLoadingAsset = false
    private var onSwipeUpToDelete: ((PHAsset, Int) -> Void)?
    private var onCancelDelete: ((PHAsset, Int) -> Void)?
    private var onStopVideoPlayback: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        setupGestures()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelRequests()
        representedAssetID = nil
        representedIndex = nil
        representedAsset = nil
        loadedHighQualityAssetID = nil
        loadedHighQualityTargetSize = .zero
        loadedThumbnailTargetSize = .zero
        loadedSelectedTargetSize = .zero
        lastBadgeState = nil
        imageView.image = nil
        placeholderView.isHidden = false
        stateOverlayView.isHidden = true
        deleteCueView.isHidden = true
        closeVideoButton.isHidden = true
        badgeStackView.arrangedSubviews.forEach { view in
            badgeStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        contentView.transform = .identity
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = videoContainerView.bounds
    }

    func configure(
        asset: PHAsset,
        index: Int,
        photoLibraryManager: PhotoLibraryManager,
        isSelected: Bool,
        isReviewed: Bool,
        isInDeleteCandidates: Bool,
        isInFavoriteCandidates: Bool,
        isBeingFiledToAlbum: Bool,
        isFiledToAlbum: Bool,
        isScreenshot: Bool,
        isVideo: Bool,
        isVideoPlaying: Bool,
        thumbnailTargetSize: CGSize,
        selectedTargetSize: CGSize,
        prefersHighQualityPreview: Bool,
        onSwipeUpToDelete: @escaping (PHAsset, Int) -> Void,
        onCancelDelete: @escaping (PHAsset, Int) -> Void,
        onStopVideoPlayback: @escaping () -> Void
    ) {
        let assetID = asset.localIdentifier
        let assetChanged = representedAssetID != assetID
        let needsImageReload = assetChanged || loadedThumbnailTargetSize != thumbnailTargetSize
        let needsPreviewReload = assetChanged ||
            loadedSelectedTargetSize != selectedTargetSize
        let hasLoadedHighQualityPreview = loadedHighQualityAssetID == assetID &&
            loadedHighQualityTargetSize == selectedTargetSize

        representedAssetID = assetID
        representedIndex = index
        representedAsset = asset
        self.photoLibraryManager = photoLibraryManager
        self.onSwipeUpToDelete = onSwipeUpToDelete
        self.onCancelDelete = onCancelDelete
        self.onStopVideoPlayback = onStopVideoPlayback
        self.prefersHighQualityPreview = prefersHighQualityPreview
        loadedThumbnailTargetSize = thumbnailTargetSize
        loadedSelectedTargetSize = selectedTargetSize
        if needsPreviewReload {
            cancelPreviewRequest()
            loadedHighQualityAssetID = nil
            loadedHighQualityTargetSize = .zero
        }

        updateSelection(isSelected)
        updateBadges(isVideo: isVideo, isScreenshot: isScreenshot)
        updateStateOverlay(
            isReviewed: isReviewed,
            isInDeleteCandidates: isInDeleteCandidates,
            isInFavoriteCandidates: isInFavoriteCandidates,
            isBeingFiledToAlbum: isBeingFiledToAlbum,
            isFiledToAlbum: isFiledToAlbum
        )
        updateAccessibility(
            isSelected: isSelected,
            isReviewed: isReviewed,
            isInDeleteCandidates: isInDeleteCandidates,
            isInFavoriteCandidates: isInFavoriteCandidates,
            isBeingFiledToAlbum: isBeingFiledToAlbum,
            isFiledToAlbum: isFiledToAlbum,
            isScreenshot: isScreenshot,
            isVideo: isVideo
        )

        let hasPendingHighQualityPreview = previewRequestID != nil || previewWorkItem != nil
        if needsImageReload {
            loadThumbnail(asset: asset, targetSize: thumbnailTargetSize, keepingExistingImage: !assetChanged)
        } else if prefersHighQualityPreview,
                  !hasLoadedHighQualityPreview,
                  !hasPendingHighQualityPreview {
            scheduleHighQualityPreview(asset: asset, targetSize: selectedTargetSize)
        } else if !prefersHighQualityPreview {
            cancelPreviewRequest()
        }

        updateVideoPlayback(isVideoPlaying: isVideoPlaying, asset: asset)
    }

    private func setupViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.layer.masksToBounds = false

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = TwoRowBrowserColors.surface
        containerView.layer.cornerRadius = 18
        containerView.layer.cornerCurve = .continuous
        containerView.clipsToBounds = true
        contentView.addSubview(containerView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        containerView.addSubview(imageView)

        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.backgroundColor = TwoRowBrowserColors.surface
        containerView.addSubview(placeholderView)

        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        placeholderIcon.tintColor = TwoRowBrowserColors.secondaryText.withAlphaComponent(0.38)
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderView.addSubview(placeholderIcon)

        videoContainerView.translatesAutoresizingMaskIntoConstraints = false
        videoContainerView.backgroundColor = .black
        videoContainerView.isHidden = true
        videoContainerView.isUserInteractionEnabled = false
        containerView.addSubview(videoContainerView)

        closeVideoButton.translatesAutoresizingMaskIntoConstraints = false
        closeVideoButton.tintColor = .white
        closeVideoButton.backgroundColor = UIColor.black.withAlphaComponent(0.76)
        closeVideoButton.layer.cornerRadius = 15
        closeVideoButton.layer.cornerCurve = .continuous
        closeVideoButton.setImage(UIImage(systemName: "stop.fill"), for: .normal)
        closeVideoButton.accessibilityLabel = L10n.string("停止播放")
        closeVideoButton.isHidden = true
        closeVideoButton.addTarget(self, action: #selector(handleStopVideoPlaybackTap), for: .touchUpInside)
        containerView.addSubview(closeVideoButton)

        badgeStackView.translatesAutoresizingMaskIntoConstraints = false
        badgeStackView.axis = .vertical
        badgeStackView.alignment = .trailing
        badgeStackView.spacing = 7
        containerView.addSubview(badgeStackView)

        setupStateOverlay()
        setupDeleteCue()

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            placeholderView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            placeholderView.topAnchor.constraint(equalTo: containerView.topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            placeholderIcon.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 28),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 28),

            videoContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            videoContainerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            videoContainerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            videoContainerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            closeVideoButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            closeVideoButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            closeVideoButton.widthAnchor.constraint(equalToConstant: 30),
            closeVideoButton.heightAnchor.constraint(equalToConstant: 30),

            badgeStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -9),
            badgeStackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 9)
        ])
    }

    private func setupStateOverlay() {
        stateOverlayView.translatesAutoresizingMaskIntoConstraints = false
        stateOverlayView.backgroundColor = TwoRowBrowserColors.background.withAlphaComponent(0.74)
        stateOverlayView.isHidden = true
        containerView.addSubview(stateOverlayView)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 9
        stateOverlayView.addSubview(stack)

        stateIconView.translatesAutoresizingMaskIntoConstraints = false
        stateIconView.contentMode = .scaleAspectFit
        stack.addArrangedSubview(stateIconView)
        stateIconView.widthAnchor.constraint(equalToConstant: 34).isActive = true
        stateIconView.heightAnchor.constraint(equalToConstant: 34).isActive = true

        stateTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        stateTitleLabel.textColor = TwoRowBrowserColors.primaryText
        stack.addArrangedSubview(stateTitleLabel)

        cancelButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        cancelButton.tintColor = TwoRowBrowserColors.primaryText
        cancelButton.backgroundColor = TwoRowBrowserColors.surface.withAlphaComponent(0.82)
        cancelButton.layer.cornerRadius = 14
        cancelButton.layer.cornerCurve = .continuous
        cancelButton.layer.borderColor = TwoRowBrowserColors.hairline.cgColor
        cancelButton.layer.borderWidth = 1
        var cancelConfiguration = UIButton.Configuration.plain()
        cancelConfiguration.title = L10n.string("取消")
        cancelConfiguration.image = UIImage(systemName: "xmark.circle.fill")
        cancelConfiguration.imagePadding = 4
        cancelConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        cancelButton.configuration = cancelConfiguration
        cancelButton.addTarget(self, action: #selector(cancelDelete), for: .touchUpInside)
        stack.addArrangedSubview(cancelButton)

        NSLayoutConstraint.activate([
            stateOverlayView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stateOverlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stateOverlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stateOverlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: stateOverlayView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: stateOverlayView.centerYAnchor)
        ])
    }

    private func setupDeleteCue() {
        deleteCueView.translatesAutoresizingMaskIntoConstraints = false
        deleteCueView.backgroundColor = TwoRowBrowserColors.destructive.withAlphaComponent(0.74)
        deleteCueView.isHidden = true
        containerView.addSubview(deleteCueView)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        deleteCueView.addSubview(stack)

        deleteCueIconView.tintColor = .white
        deleteCueIconView.contentMode = .scaleAspectFit
        stack.addArrangedSubview(deleteCueIconView)
        deleteCueIconView.widthAnchor.constraint(equalToConstant: 34).isActive = true
        deleteCueIconView.heightAnchor.constraint(equalToConstant: 34).isActive = true

        deleteCueLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        deleteCueLabel.textColor = .white
        deleteCueLabel.text = L10n.string("上滑删除")
        stack.addArrangedSubview(deleteCueLabel)

        NSLayoutConstraint.activate([
            deleteCueView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            deleteCueView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            deleteCueView.topAnchor.constraint(equalTo: containerView.topAnchor),
            deleteCueView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: deleteCueView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: deleteCueView.centerYAnchor)
        ])
    }

    private func setupGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        containerView.addGestureRecognizer(panGesture)
    }

    private func updateSelection(_ isSelected: Bool) {
        containerView.layer.borderColor = (isSelected ? TwoRowBrowserColors.accent : TwoRowBrowserColors.hairline).cgColor
        containerView.layer.borderWidth = isSelected ? 2 : 1
        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOpacity = isSelected ? 0.18 : 0
        contentView.layer.shadowRadius = isSelected ? 6 : 0
        contentView.layer.shadowOffset = CGSize(width: 0, height: isSelected ? 3 : 0)
    }

    private func updateBadges(isVideo: Bool, isScreenshot: Bool) {
        if let lastBadgeState,
           lastBadgeState.isVideo == isVideo,
           lastBadgeState.isScreenshot == isScreenshot {
            return
        }
        lastBadgeState = (isVideo, isScreenshot)

        badgeStackView.arrangedSubviews.forEach { view in
            badgeStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if isVideo {
            badgeStackView.addArrangedSubview(makeBadge(systemName: "play.fill"))
        }
        if isScreenshot {
            badgeStackView.addArrangedSubview(makeBadge(systemName: "camera.viewfinder"))
        }
    }

    private func makeBadge(systemName: String) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.56)
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = TwoRowBrowserColors.background.withAlphaComponent(0.72).cgColor

        let imageView = UIImageView(image: UIImage(systemName: systemName))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 24),
            view.heightAnchor.constraint(equalToConstant: 24),
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12)
        ])
        return view
    }

    private func updateStateOverlay(
        isReviewed: Bool,
        isInDeleteCandidates: Bool,
        isInFavoriteCandidates: Bool,
        isBeingFiledToAlbum: Bool,
        isFiledToAlbum: Bool
    ) {
        _ = isReviewed
        stateOverlayView.isHidden = !(isInDeleteCandidates || isInFavoriteCandidates || isBeingFiledToAlbum || isFiledToAlbum)
        cancelButton.isHidden = !isInDeleteCandidates

        if isInDeleteCandidates {
            stateIconView.image = UIImage(systemName: "trash.fill")
            stateIconView.tintColor = TwoRowBrowserColors.destructive
            stateTitleLabel.text = L10n.string("待删除")
        } else if isInFavoriteCandidates {
            stateIconView.image = UIImage(systemName: "heart.fill")
            stateIconView.tintColor = TwoRowBrowserColors.favorite
            stateTitleLabel.text = L10n.string("待收藏")
        } else if isBeingFiledToAlbum {
            stateIconView.image = UIImage(systemName: "tray.and.arrow.down.fill")
            stateIconView.tintColor = TwoRowBrowserColors.positive
            stateTitleLabel.text = L10n.string("归类中")
        } else if isFiledToAlbum {
            stateIconView.image = UIImage(systemName: "checkmark.circle.fill")
            stateIconView.tintColor = TwoRowBrowserColors.positive
            stateTitleLabel.text = L10n.string("已归类")
        }
    }

    private func updateAccessibility(
        isSelected: Bool,
        isReviewed: Bool,
        isInDeleteCandidates: Bool,
        isInFavoriteCandidates: Bool,
        isBeingFiledToAlbum: Bool,
        isFiledToAlbum: Bool,
        isScreenshot: Bool,
        isVideo: Bool
    ) {
        var values: [String] = [isVideo ? L10n.string("视频") : L10n.string("照片")]
        if isSelected { values.append(L10n.string("当前照片")) }
        if isScreenshot { values.append(L10n.string("截图")) }
        if isInDeleteCandidates {
            values.append(L10n.string("待删除"))
        } else if isInFavoriteCandidates {
            values.append(L10n.string("待收藏"))
        } else if isBeingFiledToAlbum {
            values.append(L10n.string("归类中"))
        } else if isFiledToAlbum {
            values.append(L10n.string("已归类"))
        } else if isReviewed {
            values.append(L10n.string("已整理"))
        }
        accessibilityLabel = L10n.string("浏览照片")
        accessibilityValue = values.joined(separator: "，")
        accessibilityTraits = [.button]
        if isSelected {
            accessibilityTraits.insert(.selected)
        }
    }

    private func loadThumbnail(asset: PHAsset, targetSize: CGSize, keepingExistingImage: Bool) {
        cancelImageRequests(keepingImage: keepingExistingImage)
        let requestedAssetID = asset.localIdentifier
        isLoadingAsset = true
        if imageView.image == nil || !keepingExistingImage {
            placeholderView.isHidden = false
        }

        thumbnailRequestID = photoLibraryManager?.loadGridThumbnail(for: asset, size: targetSize) { [weak self] image in
            guard let self, self.representedAssetID == requestedAssetID else { return }
            if let image {
                self.imageView.image = image
                self.placeholderView.isHidden = true
                self.isLoadingAsset = false
                if self.prefersHighQualityPreview {
                    self.scheduleHighQualityPreview(asset: asset, targetSize: self.loadedSelectedTargetSize)
                }
            } else {
                self.fallbackRequestID = self.photoLibraryManager?.loadFastThumbnail(for: asset, size: targetSize) { [weak self] fallbackImage in
                    guard let self, self.representedAssetID == requestedAssetID else { return }
                    if let fallbackImage {
                        self.imageView.image = fallbackImage
                        self.placeholderView.isHidden = true
                    }
                    self.isLoadingAsset = false
                    self.fallbackRequestID = nil
                    if self.prefersHighQualityPreview {
                        self.scheduleHighQualityPreview(asset: asset, targetSize: self.loadedSelectedTargetSize)
                    }
                }
            }
            self.thumbnailRequestID = nil
        }
    }

    private func scheduleHighQualityPreview(asset: PHAsset, targetSize: CGSize) {
        guard prefersHighQualityPreview, representedAssetID == asset.localIdentifier else { return }
        guard loadedHighQualityAssetID != asset.localIdentifier ||
              loadedHighQualityTargetSize != targetSize else {
            return
        }
        guard previewRequestID == nil, previewWorkItem == nil else { return }

        let requestedAssetID = asset.localIdentifier
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.representedAssetID == requestedAssetID,
                  self.prefersHighQualityPreview,
                  self.previewRequestID == nil else {
                return
            }
            self.previewWorkItem = nil
            self.previewRequestID = self.photoLibraryManager?.loadBrowserPreviewResult(for: asset, size: targetSize) { [weak self] result in
                guard let self, self.representedAssetID == requestedAssetID else { return }
                if let image = result.image {
                    self.imageView.image = image
                    self.placeholderView.isHidden = true
                    self.isLoadingAsset = false
                }
                if result.isFinal {
                    self.loadedHighQualityAssetID = requestedAssetID
                    self.loadedHighQualityTargetSize = targetSize
                    self.previewRequestID = nil
                }
            }
        }
        previewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func updateVideoPlayback(isVideoPlaying: Bool, asset: PHAsset) {
        guard isVideoPlaying else {
            stopVideoPlayback(resetCallback: false)
            return
        }

        guard representedAssetID == asset.localIdentifier, player == nil else {
            videoContainerView.isHidden = false
            closeVideoButton.isHidden = false
            return
        }

        videoContainerView.isHidden = false
        closeVideoButton.isHidden = false
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = videoContainerView.bounds
        videoContainerView.layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer

        let requestedAssetID = asset.localIdentifier
        videoRequestID = photoLibraryManager?.loadPlayerItem(for: asset) { [weak self] playerItem in
            guard let self, self.representedAssetID == requestedAssetID else { return }
            guard let playerItem else { return }
            let player = AVPlayer(playerItem: playerItem)
            self.player = player
            self.playerLayer?.player = player
            player.play()
            self.videoRequestID = nil
        }
    }

    private func cancelImageRequests(keepingImage: Bool) {
        photoLibraryManager?.cancelImageRequest(thumbnailRequestID)
        photoLibraryManager?.cancelImageRequest(fallbackRequestID)
        cancelPreviewRequest()
        thumbnailRequestID = nil
        fallbackRequestID = nil
        if !keepingImage {
            imageView.image = nil
        }
    }

    private func cancelPreviewRequest() {
        previewWorkItem?.cancel()
        previewWorkItem = nil
        photoLibraryManager?.cancelImageRequest(previewRequestID)
        previewRequestID = nil
    }

    private func cancelRequests() {
        cancelImageRequests(keepingImage: false)
        stopVideoPlayback(resetCallback: false)
        isLoadingAsset = false
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: containerView)
        let horizontalDistance = abs(translation.x)
        let verticalDistance = abs(translation.y)
        let isUpwardDelete = translation.y < 0 && verticalDistance > horizontalDistance

        switch gesture.state {
        case .changed:
            guard isUpwardDelete else { return }
            contentView.transform = CGAffineTransform(translationX: 0, y: max(translation.y * 0.35, -46))
            deleteCueView.isHidden = verticalDistance <= 26
        case .ended, .cancelled, .failed:
            let shouldDelete = translation.y < -58 && verticalDistance > horizontalDistance * 1.15
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.contentView.transform = .identity
                self.deleteCueView.isHidden = true
            }
            if shouldDelete, let asset = representedAsset, let index = representedIndex {
                onSwipeUpToDelete?(asset, index)
            }
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func cancelDelete() {
        guard let asset = representedAsset, let index = representedIndex else { return }
        onCancelDelete?(asset, index)
    }

    @objc private func handleStopVideoPlaybackTap() {
        stopVideoPlayback(resetCallback: true)
    }

    private func stopVideoPlayback(resetCallback: Bool) {
        photoLibraryManager?.cancelImageRequest(videoRequestID)
        videoRequestID = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        videoContainerView.isHidden = true
        closeVideoButton.isHidden = true
        if resetCallback {
            onStopVideoPlayback?()
        }
    }
}

private enum TwoRowBrowserColors {
    static var background: UIColor {
        PhotoDeleteTheme.current.uiBackground
    }

    static var surface: UIColor {
        PhotoDeleteTheme.current.uiSurface
    }

    static var hairline: UIColor {
        PhotoDeleteTheme.current.uiHairline
    }

    static let primaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.96)
            : UIColor.label
    }

    static let secondaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.62)
            : UIColor.secondaryLabel
    }

    static var accent: UIColor {
        PhotoDeleteTheme.current.uiAccent
    }

    static var destructive: UIColor {
        PhotoDeleteTheme.current.uiDanger
    }

    static var favorite: UIColor {
        PhotoDeleteTheme.current.uiFavorite
    }

    static var positive: UIColor {
        PhotoDeleteTheme.current.uiSuccess
    }
}
