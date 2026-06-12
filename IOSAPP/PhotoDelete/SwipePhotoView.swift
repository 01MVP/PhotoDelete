//
//  SwipePhotoView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import SwiftUI
import AVKit
import Photos
#if canImport(UIKit)
import UIKit
#endif

struct SwipePhotoView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @AppStorage(AppConstants.leftSwipeActionKey) private var leftSwipeActionValue = SwipeGesturePreset.standard.leftAction.rawValue
    @AppStorage(AppConstants.rightSwipeActionKey) private var rightSwipeActionValue = SwipeGesturePreset.standard.rightAction.rawValue
    @AppStorage(AppConstants.upSwipeActionKey) private var upSwipeActionValue = SwipeGesturePreset.standard.upAction.rawValue
    @AppStorage(AppConstants.reviewModeKey) private var reviewModeValue = PhotoReviewMode.card.rawValue

    let selectedCategory: PhotoCategory?
    let selectedTimeGroup: String?
    let selectedAlbumInfo: AlbumInfo?
    let selectedDate: Date?
    let selectedAdvancedTimeScope: AdvancedTimeScope?
    let selectedAdvancedCleanup: AdvancedCleanupKind?

    @State private var dragOffset = CGSize.zero
    @State private var rotationAngle: Double = 0
    @State private var showBatchConfirm = false
    @State private var currentPhotoIndex = 0
    @State private var showCompletionMessage = false
    @State private var actionHistory: [SwipeAction] = []
    @State private var sessionPhotos: [PHAsset] = []
    @State private var sessionReviewedCount = 0
    @State private var shouldDismissAfterBatch = false
    @State private var feedbackToast: PhotoDeleteToast?
    @State private var didInitializeSession = false
    @State private var preloadedAssets: [PHAsset] = []
    @State private var pendingDeleteCount = 0
    @State private var pendingFavoriteCount = 0
    @State private var pendingSwipeMutations: [String: PendingSwipeMutation] = [:]
    @State private var browserRows = BrowserPhotoRows.empty
    @State private var browserPreloadedAssets: [PHAsset] = []
    @State private var browserPreloadTargetSize: CGSize?
    @State private var previewAsset: CandidatePreviewAsset?

    init(
        selectedCategory: PhotoCategory?,
        selectedTimeGroup: String?,
        selectedAlbumInfo: AlbumInfo?,
        selectedDate: Date? = nil,
        selectedAdvancedTimeScope: AdvancedTimeScope? = nil,
        selectedAdvancedCleanup: AdvancedCleanupKind? = nil
    ) {
        self.selectedCategory = selectedCategory
        self.selectedTimeGroup = selectedTimeGroup
        self.selectedAlbumInfo = selectedAlbumInfo
        self.selectedDate = selectedDate
        self.selectedAdvancedTimeScope = selectedAdvancedTimeScope
        self.selectedAdvancedCleanup = selectedAdvancedCleanup
    }

    enum SwipeDirection {
        case left, right, up, down
    }

    private enum SwipeAction {
        case delete(PHAsset, originalIndex: Int, wasReviewed: Bool)
        case favorite(PHAsset, originalIndex: Int, wasReviewed: Bool)
        case skip(PHAsset, originalIndex: Int, wasReviewed: Bool)
    }

    private struct PendingSwipeMutation {
        let asset: PHAsset
        let action: SwipeGestureAction
        let token: UUID
    }

    private struct BrowserPhotoRows {
        var top: [BrowserPhotoItem]
        var bottom: [BrowserPhotoItem]

        static let empty = BrowserPhotoRows(top: [], bottom: [])
    }

    private struct BrowserPhotoItem: Identifiable {
        let index: Int
        let asset: PHAsset
        let aspectRatio: CGFloat
        let isScreenshot: Bool
        let isVideo: Bool

        var id: String { asset.localIdentifier }
    }

    private var currentRealPhoto: PHAsset? {
        guard !sessionPhotos.isEmpty, currentPhotoIndex >= 0, currentPhotoIndex < sessionPhotos.count else {
            return nil
        }
        return sessionPhotos[currentPhotoIndex]
    }

    private var filteredRealPhotos: [PHAsset] {
        guard dataManager.photoLibraryManager.hasPhotoLibraryAccess else {
            return []
        }

        if let albumInfo = selectedAlbumInfo {
            return dataManager.getPhotosForAlbum(albumInfo)
        } else if let selectedDate, let selectedAdvancedTimeScope {
            return dataManager.getPhotosForPeriod(selectedAdvancedTimeScope, containing: selectedDate)
        } else if let selectedDate {
            return dataManager.getPhotosForDay(selectedDate)
        } else if let selectedAdvancedCleanup {
            return dataManager.getPhotosForAdvancedCleanup(selectedAdvancedCleanup)
        } else if let category = selectedCategory {
            return dataManager.getRealPhotos(for: category)
        } else if let timeGroupString = selectedTimeGroup,
                  let timeGroup = TimeGroup.fromIdentifier(timeGroupString) {
            return dataManager.getPhotosForTimeGroup(timeGroup)
        } else {
            return dataManager.photoLibraryManager.allPhotos
        }
    }

    private var totalPhotosCount: Int {
        return sessionPhotos.count
    }

    private var currentProgress: Int {
        return min(currentPhotoIndex + 1, totalPhotosCount)
    }

    private var organizedProgress: Int {
        guard totalPhotosCount > 0 else { return 0 }
        return showCompletionMessage ? totalPhotosCount : min(sessionReviewedCount, totalPhotosCount)
    }

    private var progressFraction: Double {
        guard totalPhotosCount > 0 else { return 0 }
        return Double(organizedProgress) / Double(totalPhotosCount)
    }

    private var isAlbumMode: Bool {
        return selectedAlbumInfo != nil
    }

    private var isCurrentPhotoFavorited: Bool {
        guard let asset = currentRealPhoto else { return false }
        return asset.isFavorite || isAssetQueuedForFavorite(asset)
    }

    private var isCurrentPhotoQueuedForDelete: Bool {
        guard let asset = currentRealPhoto else { return false }
        return isAssetQueuedForDelete(asset)
    }

    private var canPerformPhotoAction: Bool {
        currentRealPhoto != nil && !showCompletionMessage
    }

    private var reviewMode: PhotoReviewMode {
        PhotoReviewMode.normalized(reviewModeValue)
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height && geometry.size.width > AppConstants.landscapeBreakpoint

                ZStack(alignment: .bottom) {
                    if isLandscape {
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                navigationHeader
                                photoArea
                            }
                            .frame(width: geometry.size.width * 0.64)

                            landscapeSidebar
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        VStack(spacing: 0) {
                            navigationHeader
                            photoArea
                            bottomControls
                        }
                    }

                    if let feedbackToast {
                        PhotoDeleteToastView(toast: feedbackToast) {
                            handleUndoAction()
                            resetCardPosition()
                        }
                        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                        .padding(.bottom, isLandscape ? 24 : portraitToastBottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $previewAsset) { previewAsset in
            CandidatePhotoPreviewView(
                asset: previewAsset.asset,
                photoLibraryManager: dataManager.photoLibraryManager
            )
        }
        .fullScreenCover(isPresented: $showBatchConfirm, onDismiss: {
            didInitializeSession = false
            syncPendingOperationCounts()
        }) {
            BatchConfirmView(albumInfo: selectedAlbumInfo) {
                if shouldDismissAfterBatch {
                    dismiss()
                }
            }
                .environmentObject(dataManager)
        }
        .onDisappear {
            flushPendingSwipeMutations()
            dataManager.photoLibraryManager.stopCachingImages(
                preloadedAssets,
                size: swipeImageTargetSize
            )
            preloadedAssets.removeAll()
            stopPreloadingBrowserThumbnails()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            // 处理内存警告
            dataManager.photoLibraryManager.handleMemoryWarning()
        }
        .onAppear {
            syncPendingOperationCounts()
            initializeSessionIfNeeded()
        }
        .onChange(of: dataManager.photoLibraryManager.isLoading) { _ in
            initializeSessionIfNeeded()
        }
        .onChange(of: dataManager.isPreparingLibrary) { _ in
            initializeSessionIfNeeded()
        }
        .onChange(of: currentPhotoIndex) { _ in
            persistSessionProgressIfPossible()
        }
    }

    // MARK: - 导航栏
    private var navigationHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: handleBackAction) {
                    ZStack {
                        Circle()
                            .fill(PhotoDeleteStyle.elevatedSurface)
                            .frame(width: 40, height: 40)

                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(PhotoDeleteStyle.primaryText)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 116, alignment: .leading)

                Spacer()

                VStack(spacing: 2) {
                    Text(sessionModeTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(progressSubtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer()

                HStack(spacing: 8) {
                    ReviewModeToggleButton(mode: reviewMode, action: toggleReviewMode)
                    PendingDeleteCounter(count: pendingDeleteCount)
                }
                .frame(width: 116, alignment: .trailing)
            }

            if totalPhotosCount > 0 {
                ProgressView(value: progressFraction)
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    .frame(height: 4)
                    .clipShape(Capsule(style: .continuous))
                    .animation(.easeOut(duration: 0.22), value: organizedProgress)
            }
        }
        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(PhotoDeleteStyle.background.opacity(0.86))
        .overlay(
            Rectangle()
                .fill(PhotoDeleteStyle.hairline)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - 照片区域
    private var photoArea: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()

                if !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                    PhotoAuthorizationCard(
                        subtitle: "请允许访问您的照片库来开始整理照片",
                        onRequestAccess: { dataManager.requestPhotoLibraryAccess() }
                    )
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                } else if let realPhoto = currentRealPhoto {
                    ZStack {
                        switch reviewMode {
                        case .card:
                            cardPhotoArea(asset: realPhoto, in: geometry.size)
                        case .browser:
                            browserPhotoArea(in: geometry.size)
                        }

                        if showCompletionMessage {
                            completionOverlay
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if shouldShowInitialPreparingState {
                    PhotoSelectionLoadingCard(
                        title: "正在读取照片",
                        message: "读取完成后会直接进入当前整理。",
                        progress: activeLibraryLoadingProgress
                    )
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                } else if shouldShowBackgroundLoadingState {
                    PhotoSelectionLoadingCard(
                        title: "正在读取当前相册",
                        message: "照片很多时可能需要几秒，完成后会自动开始。",
                        progress: activeLibraryLoadingProgress
                    )
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                } else {
                    // 没有更多照片
                    VStack(spacing: 20) {
                        if totalPhotosCount == 0 {
                            // 没有照片的情况
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 60, weight: .medium))
                                .foregroundColor(PhotoDeleteStyle.accent)

                            Text(L10n.string("这里还没有可整理的照片"))
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)

                            Text(L10n.string("您可以返回选择其他分类，或稍后在系统照片中添加更多照片后再回来。"))
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)

                            Button(action: { dismiss() }) {
                                Text(L10n.string("返回主页"))
                                    .frame(maxWidth: 180)
                            }
                            .photoDeleteSecondaryButton()
                        } else {
                            // 整理完成的情况
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60, weight: .medium))
                                .foregroundColor(PhotoDeleteStyle.positive)

                            Text(L10n.string("整理完成！"))
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)

                            Text(L10n.string("您已经整理完所有照片"))
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)

                            Button(action: { dismiss() }) {
                                Text(L10n.string("返回主页"))
                                    .frame(maxWidth: 180)
                            }
                            .photoDeleteSecondaryButton()
                        }
                    }
                    .padding(24)
                    .photoDeleteCard()
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                }

                Spacer()
            }
        }
    }

    private func cardPhotoArea(asset: PHAsset, in containerSize: CGSize) -> some View {
        let cardSize = photoCardSize(in: containerSize)

        return ZStack {
            SwipePhotoCardFrame(
                asset: asset,
                photoLibraryManager: dataManager.photoLibraryManager,
                isInDeleteCandidates: isAssetQueuedForDelete(asset),
                isInFavoriteCandidates: isAssetQueuedForFavorite(asset),
                displaySize: cardSize,
                targetSize: imageTargetSize(for: cardSize)
            )
            .id(asset.localIdentifier)
            .overlay {
                if let feedback = dragFeedback(for: dragOffset) {
                    PhotoSwipeDragFeedbackView(feedback: feedback)
                        .allowsHitTesting(false)
                }
            }
            .offset(dragOffset)
            .rotationEffect(.degrees(rotationAngle))
            .scaleEffect(1.0 - abs(dragOffset.width) / 1000)
            .gesture(createDragGesture())
            .simultaneousGesture(TapGesture().onEnded {
                openAssetPreview(asset)
            })
            .accessibilityAction(named: Text(L10n.string("加入待删除"))) {
                handleDeleteAction()
                resetCardPosition()
            }
            .accessibilityAction(named: Text(isCurrentPhotoFavorited ? L10n.string("已收藏") : L10n.string("加入收藏"))) {
                handleFavoriteAction()
                resetCardPosition()
            }
            .accessibilityAction(named: Text(L10n.string("跳过"))) {
                handleSkipAction()
                resetCardPosition()
            }

            if let previewDirection = dominantSwipeDirection(for: dragOffset, threshold: 50) {
                SwipeIndicator(
                    direction: previewDirection,
                    action: configuredAction(for: previewDirection)
                )
            }
        }
    }

    private func dragFeedback(for translation: CGSize) -> PhotoSwipeDragFeedbackState? {
        let previewStart: CGFloat = 14
        let commitDistance: CGFloat = 100
        guard let direction = dominantSwipeDirection(for: translation, threshold: previewStart) else {
            return nil
        }
        guard direction != .down else { return nil }

        let distance: CGFloat
        switch direction {
        case .left, .right:
            distance = abs(translation.width)
        case .up, .down:
            distance = abs(translation.height)
        }

        let progress = min(max((distance - previewStart) / (commitDistance - previewStart), 0), 1)
        guard progress > 0 else { return nil }

        return PhotoSwipeDragFeedbackState(
            direction: direction,
            action: configuredAction(for: direction),
            progress: progress
        )
    }

    private func browserPhotoArea(in containerSize: CGSize) -> some View {
        let tileHeight = browserTileHeight(in: containerSize)
        let thumbnailTargetSize = browserThumbnailTargetSize(in: containerSize, tileHeight: tileHeight)
        let rowSpacing: CGFloat = 12

        return VStack(spacing: 12) {
            browserStatusStrip

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        browserPhotoRow(
                            items: browserRows.top,
                            tileHeight: tileHeight,
                            containerWidth: containerSize.width,
                            thumbnailTargetSize: thumbnailTargetSize
                        )

                        browserPhotoRow(
                            items: browserRows.bottom,
                            tileHeight: tileHeight,
                            containerWidth: containerSize.width,
                            thumbnailTargetSize: thumbnailTargetSize
                        )
                        .padding(.leading, min(tileHeight * 0.34, 64))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .frame(height: tileHeight * 2 + rowSpacing + 8)
                .onAppear {
                    preloadBrowserThumbnails(from: currentPhotoIndex, targetSize: thumbnailTargetSize)
                    scrollBrowserToCurrentPhoto(with: proxy, animated: false)
                }
                .onChange(of: currentPhotoIndex) { _ in
                    preloadBrowserThumbnails(from: currentPhotoIndex, targetSize: thumbnailTargetSize)
                }
                .onChange(of: thumbnailTargetSize) { targetSize in
                    preloadBrowserThumbnails(from: currentPhotoIndex, targetSize: targetSize)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
    }

    private func browserPhotoRow(
        items: [BrowserPhotoItem],
        tileHeight: CGFloat,
        containerWidth: CGFloat,
        thumbnailTargetSize: CGSize
    ) -> some View {
        LazyHStack(alignment: .center, spacing: 12) {
            ForEach(items.indices, id: \.self) { itemPosition in
                let item = items[itemPosition]
                let asset = item.asset
                let tileSize = browserTileSize(for: item, baseHeight: tileHeight, containerWidth: containerWidth)

                BrowserPhotoTile(
                    asset: asset,
                    photoLibraryManager: dataManager.photoLibraryManager,
                    isSelected: item.index == currentPhotoIndex,
                    isReviewed: isAssetLocallyReviewed(asset),
                    isInDeleteCandidates: isAssetQueuedForDelete(asset),
                    isInFavoriteCandidates: isAssetQueuedForFavorite(asset),
                    isScreenshot: item.isScreenshot,
                    isVideo: item.isVideo,
                    displaySize: tileSize,
                    targetSize: thumbnailTargetSize,
                    selectedTargetSize: browserSelectedImageTargetSize(for: tileSize),
                    prefersHighQualityPreview: shouldLoadHighQualityBrowserPreview(for: item.index),
                    onSelect: {
                        if item.index == currentPhotoIndex {
                            openAssetPreview(asset)
                        } else {
                            selectBrowserPhoto(at: item.index)
                        }
                    },
                    onSwipeUpToDelete: {
                        handleBrowserSwipeUpDelete(asset, at: item.index)
                    },
                    onCancelDelete: {
                        cancelDeleteCandidate(asset, at: item.index)
                    }
                )
                .id(asset.localIdentifier)
            }
        }
    }

    private var browserStatusStrip: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Label(L10n.string("左右浏览"), systemImage: "arrow.left.and.right")
                    .foregroundColor(PhotoDeleteStyle.accent)

                Label(L10n.string("上滑删除"), systemImage: "arrow.up")
                    .foregroundColor(PhotoDeleteStyle.destructive)

                Spacer(minLength: 8)

                Text("\(L10n.string("位置")) \(currentProgress)/\(totalPhotosCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            ProgressView(value: progressFraction)
                .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                .frame(height: 4)
                .clipShape(Capsule(style: .continuous))

            HStack(spacing: 10) {
                Text("\(L10n.string("已整理")) \(organizedProgress)/\(totalPhotosCount)")
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Spacer(minLength: 8)

                Text(L10n.string("待删除 \(pendingDeleteCount) 张"))
                    .foregroundColor(pendingDeleteCount > 0 ? PhotoDeleteStyle.destructive : PhotoDeleteStyle.secondaryText)
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(PhotoDeleteStyle.surface)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                )
        )
        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
    }

    private var completionOverlay: some View {
        ZStack {
            PhotoDeleteStyle.background.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.positive)

                Text(L10n.string("整理完成！"))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(L10n.string("您已经浏览完所有照片"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)

                HStack(spacing: 12) {
                    if hasUnreviewedPhotos {
                        Button(L10n.string("继续整理")) {
                            continueToNextUnreviewedPhoto()
                            showCompletionMessage = false
                        }
                        .photoDeleteSecondaryButton()
                    }

                    Button(L10n.string("完成整理")) {
                        handleFinishAction()
                        showCompletionMessage = false
                    }
                    .photoDeletePrimaryButton()
                }
            }
            .padding(24)
            .photoDeleteCard()
            .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
        }
        .transition(.opacity)
    }

    // MARK: - 底部控制区域
    private var bottomControls: some View {
        VStack(spacing: 10) {
            albumShortcutStrip(horizontalPadding: PhotoDeleteStyle.screenHorizontalPadding)
            actionToolbar
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [
                    PhotoDeleteStyle.background.opacity(0.08),
                    PhotoDeleteStyle.background.opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(PhotoDeleteStyle.hairline.opacity(0.65).frame(height: 1), alignment: .top)
        )
    }

    private var landscapeSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            sessionSummaryPanel
            gestureGuidePanel
            albumShortcutStrip(horizontalPadding: 0)

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                SidebarActionButton(
                    icon: "heart",
                    title: isCurrentPhotoFavorited ? L10n.string("已收藏") : L10n.string("收藏"),
                    color: PhotoDeleteStyle.iconTint(for: "favorite")
                ) {
                    handleFavoriteAction()
                    resetCardPosition()
                }

                SidebarActionButton(
                    icon: "trash",
                    title: L10n.string("待删除"),
                    color: PhotoDeleteStyle.destructive
                ) {
                    handleDeleteAction()
                    resetCardPosition()
                }

                SidebarActionButton(
                    icon: "arrow.right",
                    title: L10n.string("跳过"),
                    color: PhotoDeleteStyle.accent
                ) {
                    handleSkipAction()
                    resetCardPosition()
                }

                HStack(spacing: 10) {
                    SidebarActionButton(
                        icon: "arrow.uturn.backward",
                        title: L10n.string("撤销"),
                        color: PhotoDeleteStyle.secondaryText,
                        isCompact: true
                    ) {
                        handleUndoAction()
                        resetCardPosition()
                    }

                    SidebarActionButton(
                        icon: "checkmark",
                        title: "完成",
                        color: PhotoDeleteStyle.positive,
                        isCompact: true
                    ) {
                        handleFinishAction()
                        resetCardPosition()
                    }
                }
            }
            .disabled(!canPerformPhotoAction)
            .opacity(canPerformPhotoAction ? 1 : 0.45)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            PhotoDeleteStyle.background.opacity(0.92)
                .overlay(PhotoDeleteStyle.hairline.frame(width: 1), alignment: .leading)
        )
    }

    private var sessionSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(getDisplayTitle())
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .lineLimit(1)

            Text(progressSubtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)

            if totalPhotosCount > 0 {
                ProgressView(value: progressFraction)
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    .clipShape(Capsule(style: .continuous))
            }

            HStack(spacing: 12) {
                Label("\(pendingDeleteCount)", systemImage: "trash")
                    .foregroundColor(PhotoDeleteStyle.destructive)
                Label("\(pendingFavoriteCount)", systemImage: "heart")
                    .foregroundColor(PhotoDeleteStyle.iconTint(for: "favorite"))
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .padding(16)
        .photoDeleteCard()
    }

    private var gestureGuidePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("手势"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)

            if reviewMode == .browser {
                GestureGuideRow(
                    icon: "arrow.left.and.right",
                    title: L10n.string("左右浏览"),
                    detail: L10n.string("浏览照片"),
                    color: PhotoDeleteStyle.accent
                )

                GestureGuideRow(
                    icon: "arrow.up",
                    title: L10n.string("上滑"),
                    detail: L10n.string("加入待删除"),
                    color: PhotoDeleteStyle.destructive
                )
            } else {
                ForEach(SwipeGestureDirection.allCases) { direction in
                    let action = configuredAction(for: direction)
                    GestureGuideRow(
                        icon: direction.icon,
                        title: direction.title,
                        detail: action.detailTitle,
                        color: action.tint
                    )
                }
            }
        }
        .padding(16)
        .photoDeleteCard()
    }

    @ViewBuilder
    private func albumShortcutStrip(horizontalPadding: CGFloat) -> some View {
        if !isAlbumMode && canPerformPhotoAction && !dataManager.userAlbums.isEmpty {
            let rows = albumShortcutRows

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        ForEach(rows.top) { albumInfo in
                            AlbumMicroButton(title: albumInfo.title) {
                                handleAddToAlbum(albumInfo)
                            }
                        }
                    }

                    HStack(spacing: 7) {
                        ForEach(rows.bottom) { albumInfo in
                            AlbumMicroButton(title: albumInfo.title) {
                                handleAddToAlbum(albumInfo)
                            }
                        }
                    }
                    .padding(.leading, rows.bottom.isEmpty ? 0 : 24)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(height: 67)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.94),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    private var actionToolbar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ActionButton(icon: "arrow.uturn.backward", title: "撤销", color: PhotoDeleteStyle.secondaryText, style: .quiet) {
                handleUndoAction()
                resetCardPosition()
            }
            Spacer(minLength: 0)
            ActionButton(icon: isCurrentPhotoFavorited ? "heart.fill" : "heart", title: "收藏", color: PhotoDeleteStyle.iconTint(for: "favorite")) {
                handleFavoriteAction()
                resetCardPosition()
            }
            Spacer(minLength: 0)
            ActionButton(
                icon: isCurrentPhotoQueuedForDelete ? "xmark" : "trash",
                title: isCurrentPhotoQueuedForDelete ? "取消" : "删除",
                color: isCurrentPhotoQueuedForDelete ? PhotoDeleteStyle.secondaryText : PhotoDeleteStyle.destructive
            ) {
                handleDeleteAction()
                resetCardPosition()
            }
            Spacer(minLength: 0)
            ActionButton(icon: "arrow.right", title: "跳过", color: PhotoDeleteStyle.accent) {
                handleSkipAction()
                resetCardPosition()
            }
            Spacer(minLength: 0)
            ActionButton(icon: "checkmark", title: "完成", color: PhotoDeleteStyle.positive, style: .solid) {
                handleFinishAction()
                resetCardPosition()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PhotoDeleteStyle.surface.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                )
        )
        .shadow(color: PhotoDeleteStyle.floatingShadow, radius: 8, x: 0, y: 3)
        .padding(.horizontal, 18)
        .disabled(!canPerformPhotoAction)
        .opacity(canPerformPhotoAction ? 1 : 0.45)
    }

    // MARK: - 手势处理
    private var shouldShowInitialPreparingState: Bool {
        !didInitializeSession &&
            sessionPhotos.isEmpty &&
            dataManager.isPreparingLibrary
    }

    private var shouldShowBackgroundLoadingState: Bool {
        !didInitializeSession &&
            sessionPhotos.isEmpty &&
            !dataManager.isPreparingLibrary &&
            dataManager.photoLibraryManager.isLoading &&
            !dataManager.photoLibraryManager.hasLoadedPhotoLibrary
    }

    private var activeLibraryLoadingProgress: Double {
        min(max(dataManager.photoLibraryManager.loadingProgress, 0), 1)
    }

    private var progressSubtitle: String {
        guard totalPhotosCount > 0 else {
            return L10n.string("\(getDisplayTitle()) · 0 张照片")
        }

        return L10n.string("\(getDisplayTitle()) · 已整理 \(organizedProgress)/\(totalPhotosCount)")
    }

    private var portraitToastBottomPadding: CGFloat {
        if !isAlbumMode && canPerformPhotoAction && !dataManager.userAlbums.isEmpty {
            return 160
        }
        return 100
    }

    private var albumShortcutRows: (top: [AlbumInfo], bottom: [AlbumInfo]) {
        var top: [AlbumInfo] = []
        var bottom: [AlbumInfo] = []
        for (index, album) in dataManager.userAlbums.enumerated() {
            if index.isMultiple(of: 2) {
                top.append(album)
            } else {
                bottom.append(album)
            }
        }
        return (top, bottom)
    }

    private var hasUnreviewedPhotos: Bool {
        sessionReviewedCount < totalPhotosCount
    }

    private func initializeSessionIfNeeded() {
        guard !didInitializeSession else { return }

        let photos = filteredRealPhotos
        if photos.isEmpty && (dataManager.photoLibraryManager.isLoading || dataManager.isPreparingLibrary) {
            return
        }

        refreshSessionPhotos(photos)
        didInitializeSession = true
    }

    private func refreshSessionPhotos(_ photos: [PHAsset]? = nil) {
        let photos = photos ?? filteredRealPhotos
        sessionPhotos = photos
        rebuildBrowserRows(for: photos)
        sessionReviewedCount = dataManager.reviewedCount(in: photos)
        if didInitializeSession {
            currentPhotoIndex = min(currentPhotoIndex, max(photos.count - 1, 0))
        } else if let restoredIndex = restoredSessionProgressIndex(in: photos) {
            currentPhotoIndex = firstLocallyUnreviewedPhotoIndex(startingAt: restoredIndex) ?? restoredIndex
        } else if let firstUnreviewedIndex = photos.firstIndex(where: { !dataManager.isReviewed($0) }) {
            currentPhotoIndex = firstUnreviewedIndex
        } else {
            currentPhotoIndex = 0
            showCompletionMessage = !photos.isEmpty
        }
        preloadUpcomingImages(from: currentPhotoIndex)
        persistSessionProgressIfPossible()
    }

    private func rebuildBrowserRows(for photos: [PHAsset]) {
        guard !photos.isEmpty else {
            browserRows = .empty
            return
        }

        let screenshotIDs = Set(dataManager.photoLibraryManager.screenshots.map(\.localIdentifier))
        var top: [BrowserPhotoItem] = []
        var bottom: [BrowserPhotoItem] = []
        top.reserveCapacity((photos.count + 1) / 2)
        bottom.reserveCapacity(photos.count / 2)

        for (index, asset) in photos.enumerated() {
            let aspectRatio = asset.pixelHeight > 0 ? CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight) : 0.78
            let item = BrowserPhotoItem(
                index: index,
                asset: asset,
                aspectRatio: aspectRatio,
                isScreenshot: screenshotIDs.contains(asset.localIdentifier) || asset.mediaSubtypes.contains(.photoScreenshot),
                isVideo: asset.mediaType == .video
            )

            if index.isMultiple(of: 2) {
                top.append(item)
            } else {
                bottom.append(item)
            }
        }

        browserRows = BrowserPhotoRows(top: top, bottom: bottom)
    }

    private func preloadUpcomingImages(from index: Int) {
        guard index < sessionPhotos.count else { return }

        guard reviewMode != .browser else {
            dataManager.photoLibraryManager.stopCachingImages(
                preloadedAssets,
                size: swipeImageTargetSize
            )
            preloadedAssets.removeAll()
            return
        }

        let upcomingPhotos = Array(sessionPhotos.dropFirst(index).prefix(6))
        let currentIDs = preloadedAssets.map(\.localIdentifier)
        let nextIDs = upcomingPhotos.map(\.localIdentifier)
        guard currentIDs != nextIDs else { return }

        dataManager.photoLibraryManager.stopCachingImages(
            preloadedAssets,
            size: swipeImageTargetSize
        )
        dataManager.photoLibraryManager.preloadImagesForAssets(
            upcomingPhotos,
            size: swipeImageTargetSize,
            maxCount: 6
        )
        preloadedAssets = upcomingPhotos
    }

    private var swipeImageTargetSize: CGSize {
        let scale = displayScale
        return CGSize(width: 380 * scale, height: 520 * scale)
    }

    private func photoCardSize(in containerSize: CGSize) -> CGSize {
        let availableWidth = max(containerSize.width - 40, 180)
        let availableHeight = max(containerSize.height - 72, 220)
        let width = min(availableWidth, 390)
        let height = min(availableHeight, 590)
        return CGSize(width: width, height: height)
    }

    private func imageTargetSize(for displaySize: CGSize) -> CGSize {
        let scale = displayScale
        return CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
    }

    private func browserTileHeight(in containerSize: CGSize) -> CGFloat {
        let reservedHeight: CGFloat = 92
        let rowSpacing: CGFloat = 12
        let availableHeight = max(containerSize.height - reservedHeight, 260)
        return min(232, max(126, (availableHeight - rowSpacing) / 2))
    }

    private func browserTileSize(for item: BrowserPhotoItem, baseHeight: CGFloat, containerWidth: CGFloat) -> CGSize {
        let normalizedAspect = min(max(item.aspectRatio, 0.56), 1.72)
        let width = min(max(baseHeight * normalizedAspect, baseHeight * 0.58), min(containerWidth * 0.72, baseHeight * 1.72))
        return CGSize(width: width, height: baseHeight)
    }

    private func browserThumbnailTargetSize(in containerSize: CGSize, tileHeight: CGFloat) -> CGSize {
        let scale = min(displayScale, 1.55)
        let maxTileWidth = min(containerSize.width * 0.72, tileHeight * 1.72)
        return CGSize(
            width: min(maxTileWidth * scale, 480),
            height: min(tileHeight * scale, 420)
        )
    }

    private func browserSelectedImageTargetSize(for displaySize: CGSize) -> CGSize {
        let scale = min(displayScale, 2)
        return CGSize(
            width: min(displaySize.width * scale, 860),
            height: min(displaySize.height * scale, 860)
        )
    }

    private func shouldLoadHighQualityBrowserPreview(for index: Int) -> Bool {
        abs(index - currentPhotoIndex) <= 4
    }

    private func preloadBrowserThumbnails(from index: Int, targetSize: CGSize) {
        guard reviewMode == .browser, !sessionPhotos.isEmpty else {
            stopPreloadingBrowserThumbnails()
            return
        }

        let lowerBound = max(0, index - 8)
        let upperBound = min(sessionPhotos.count, index + 22)
        guard lowerBound < upperBound else {
            stopPreloadingBrowserThumbnails()
            return
        }

        let assets = Array(sessionPhotos[lowerBound..<upperBound])
        let currentIDs = browserPreloadedAssets.map(\.localIdentifier)
        let nextIDs = assets.map(\.localIdentifier)
        guard browserPreloadTargetSize != targetSize || currentIDs != nextIDs else { return }

        stopPreloadingBrowserThumbnails()
        dataManager.photoLibraryManager.preloadGridThumbnailsForAssets(
            assets,
            size: targetSize,
            maxCount: assets.count
        )
        browserPreloadedAssets = assets
        browserPreloadTargetSize = targetSize
    }

    private func stopPreloadingBrowserThumbnails() {
        if let targetSize = browserPreloadTargetSize, !browserPreloadedAssets.isEmpty {
            dataManager.photoLibraryManager.stopCachingGridThumbnails(
                browserPreloadedAssets,
                size: targetSize
            )
        }
        browserPreloadedAssets.removeAll()
        browserPreloadTargetSize = nil
    }

    private func selectBrowserPhoto(at index: Int) {
        guard isValidPhotoIndex(index) else { return }
        currentPhotoIndex = index
        preloadUpcomingImages(from: index)
    }

    private func scrollBrowserToCurrentPhoto(with proxy: ScrollViewProxy, animated: Bool) {
        guard let asset = currentRealPhoto else { return }
        let scrollAction = {
            proxy.scrollTo(asset.localIdentifier, anchor: .center)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.22), scrollAction)
        } else {
            scrollAction()
        }
    }

    private func handleBrowserSwipeUpDelete(_ asset: PHAsset, at index: Int) {
        guard !showCompletionMessage else { return }
        selectBrowserPhoto(at: index)

        if isAssetQueuedForDelete(asset) {
            cancelDeleteCandidate(asset, at: index)
            return
        }

        markDeleteCandidate(asset)
        moveToNextPhoto()
    }

    private func toggleReviewMode() {
        let nextMode = reviewMode.toggled
        reviewModeValue = nextMode.rawValue
        resetCardPosition()
        if nextMode == .card {
            stopPreloadingBrowserThumbnails()
        }
        preloadUpcomingImages(from: currentPhotoIndex)
        HapticManager.impact(.light)
        showFeedback(nextMode.switchAnnouncement, icon: nextMode.icon, style: .neutral, duration: 1.6)
    }

    private func openAssetPreview(_ asset: PHAsset) {
        previewAsset = CandidatePreviewAsset(asset: asset)
    }

    private func createDragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                rotationAngle = Double(value.translation.width / 20)
            }
            .onEnded { value in
                handleSwipeGesture(translation: value.translation)
            }
    }

    private func handleSwipeGesture(translation: CGSize) {
        let threshold: CGFloat = 100

        // 如果显示完成消息，允许滑动操作
        if showCompletionMessage {
            if abs(translation.width) > threshold {
                if translation.width < 0 {
                    // 左滑：显示批量确认
                    presentBatchConfirmation(dismissAfter: false)
                    showCompletionMessage = false
                } else {
                    // 右滑：关闭完成提示
                    showCompletionMessage = false
                }
            }
            resetCardPosition()
            return
        }

        guard let asset = currentRealPhoto, isValidPhotoIndex(currentPhotoIndex) else {
            resetCardPosition()
            return
        }

        if let direction = dominantSwipeDirection(for: translation, threshold: threshold) {
            performGestureAction(configuredAction(for: direction), asset: asset)
            moveToNextPhoto()
        }

        resetCardPosition()
    }

    private func dominantSwipeDirection(for translation: CGSize, threshold: CGFloat) -> SwipeDirection? {
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)

        if horizontalDistance >= verticalDistance, horizontalDistance > threshold {
            return translation.width < 0 ? .left : .right
        }

        if verticalDistance > threshold {
            return translation.height < 0 ? .up : .down
        }

        return nil
    }

    private func configuredAction(for direction: SwipeDirection) -> SwipeGestureAction {
        switch direction {
        case .left:
            return configuredAction(for: SwipeGestureDirection.left)
        case .right:
            return configuredAction(for: SwipeGestureDirection.right)
        case .up:
            return configuredAction(for: SwipeGestureDirection.up)
        case .down:
            return .keep
        }
    }

    private func configuredAction(for direction: SwipeGestureDirection) -> SwipeGestureAction {
        switch direction {
        case .left:
            return SwipeGesturePreferences.normalizedAction(leftSwipeActionValue, fallback: SwipeGesturePreferences.defaultAction(for: .left))
        case .right:
            return SwipeGesturePreferences.normalizedAction(rightSwipeActionValue, fallback: SwipeGesturePreferences.defaultAction(for: .right))
        case .up:
            return SwipeGesturePreferences.normalizedAction(upSwipeActionValue, fallback: SwipeGesturePreferences.defaultAction(for: .up))
        }
    }

    private func performGestureAction(_ action: SwipeGestureAction, asset: PHAsset) {
        switch action {
        case .delete:
            markDeleteCandidate(asset)
        case .keep:
            markSkip(asset)
        case .favorite:
            markFavoriteCandidate(asset)
        }
    }

    private func moveToNextPhoto() {
        guard !sessionPhotos.isEmpty else { return }

        let nextSearchStart = currentPhotoIndex + 1
        let newIndex = firstLocallyUnreviewedPhotoIndex(startingAt: nextSearchStart) ?? nextSearchStart
        if newIndex < sessionPhotos.count {
            if reviewMode == .browser {
                currentPhotoIndex = newIndex
            } else {
                withAnimation(.easeOut(duration: 0.15)) {
                    currentPhotoIndex = newIndex
                }
            }
            preloadUpcomingImages(from: newIndex)
        } else {
            showCompletionMessage = true
        }
    }

    private func moveToPreviousPhoto() {
        guard currentPhotoIndex > 0 else { return }
        currentPhotoIndex -= 1
    }

    private func restorePhotoPosition(_ asset: PHAsset, preferredIndex: Int) {
        if isValidPhotoIndex(preferredIndex),
           sessionPhotos[preferredIndex].localIdentifier == asset.localIdentifier {
            currentPhotoIndex = preferredIndex
        } else if let index = sessionPhotos.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            currentPhotoIndex = index
        } else {
            moveToPreviousPhoto()
        }
        showCompletionMessage = false
        preloadUpcomingImages(from: currentPhotoIndex)
    }

    private func continueToNextUnreviewedPhoto() {
        flushPendingSwipeMutations()
        guard let nextIndex = firstLocallyUnreviewedPhotoIndex(startingAt: 0) else {
            return
        }
        currentPhotoIndex = nextIndex
        preloadUpcomingImages(from: nextIndex)
    }

    private func firstLocallyUnreviewedPhotoIndex(startingAt startIndex: Int) -> Int? {
        guard startIndex < sessionPhotos.count else { return nil }
        return sessionPhotos[startIndex...].firstIndex { !isAssetLocallyReviewed($0) }
    }

    private func restoredSessionProgressIndex(in photos: [PHAsset]) -> Int? {
        guard let savedAssetID = persistedProgressMap()[sessionProgressScopeID] else {
            return nil
        }
        return photos.firstIndex { $0.localIdentifier == savedAssetID }
    }

    private func persistSessionProgressIfPossible() {
        guard didInitializeSession, let asset = currentRealPhoto else { return }
        var progressMap = persistedProgressMap()
        progressMap[sessionProgressScopeID] = asset.localIdentifier
        UserDefaults.standard.set(progressMap, forKey: AppConstants.reviewProgressByScopeKey)
    }

    private func persistedProgressMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: AppConstants.reviewProgressByScopeKey) as? [String: String] ?? [:]
    }

    private var sessionProgressScopeID: String {
        if let albumInfo = selectedAlbumInfo {
            return "album:\(albumInfo.id)"
        }

        if let selectedDate, let selectedAdvancedTimeScope {
            let intervalStart = Calendar.current.dateInterval(for: selectedAdvancedTimeScope, containing: selectedDate).start
            return "period:\(selectedAdvancedTimeScope.rawValue):\(Int(intervalStart.timeIntervalSince1970))"
        }

        if let selectedDate {
            let dayStart = Calendar.current.startOfDay(for: selectedDate)
            return "day:\(Int(dayStart.timeIntervalSince1970))"
        }

        if let selectedAdvancedCleanup {
            return "advanced:\(selectedAdvancedCleanup.rawValue)"
        }

        if let selectedCategory {
            return "category:\(selectedCategory.rawValue)"
        }

        if let selectedTimeGroup {
            return "timeGroup:\(selectedTimeGroup)"
        }

        return "category:\(PhotoCategory.all.rawValue)"
    }

    private func isValidPhotoIndex(_ index: Int) -> Bool {
        return index >= 0 && index < sessionPhotos.count
    }

    private func isAssetQueuedForDelete(_ asset: PHAsset) -> Bool {
        pendingSwipeMutations[asset.localIdentifier]?.action == .delete ||
            dataManager.isInDeleteCandidates(asset)
    }

    private func isAssetQueuedForFavorite(_ asset: PHAsset) -> Bool {
        pendingSwipeMutations[asset.localIdentifier]?.action == .favorite ||
            dataManager.isInFavoriteCandidates(asset)
    }

    private func isAssetLocallyReviewed(_ asset: PHAsset) -> Bool {
        pendingSwipeMutations[asset.localIdentifier] != nil ||
            dataManager.isReviewed(asset) ||
            dataManager.isInDeleteCandidates(asset) ||
            dataManager.isInFavoriteCandidates(asset)
    }

    private func handleFavoriteAction() {
        guard !showCompletionMessage, let asset = currentRealPhoto else { return }
        markFavoriteCandidate(asset)
        moveToNextPhoto()
    }

    private func handleDeleteAction() {
        guard !showCompletionMessage, let asset = currentRealPhoto else { return }
        if isAssetQueuedForDelete(asset) {
            cancelDeleteCandidate(asset, at: currentPhotoIndex)
            return
        }

        markDeleteCandidate(asset)
        moveToNextPhoto()
    }

    private func handleSkipAction() {
        guard !showCompletionMessage, let asset = currentRealPhoto else { return }
        markSkip(asset)
        moveToNextPhoto()
    }

    private func handleFinishAction() {
        flushPendingSwipeMutations()
        if hasPendingOperations {
            presentBatchConfirmation(dismissAfter: true)
        } else {
            dismiss()
        }
    }

    private func handleUndoAction() {
        guard let lastAction = actionHistory.popLast() else {
            HapticManager.impact(.light)
            showFeedback(L10n.string("没有可撤销的操作"), icon: "arrow.uturn.backward", style: .neutral)
            return
        }

        switch lastAction {
        case .delete(let asset, let originalIndex, let wasReviewed):
            cancelPendingSwipeMutation(for: asset)
            pendingDeleteCount = max(pendingDeleteCount - 1, 0)
            dataManager.removeFromDeleteCandidates(asset)
            dataManager.restoreReviewedState(asset, wasReviewed: wasReviewed)
            restoreSessionReviewedCount(wasReviewed: wasReviewed)
            restorePhotoPosition(asset, preferredIndex: originalIndex)
        case .favorite(let asset, let originalIndex, let wasReviewed):
            cancelPendingSwipeMutation(for: asset)
            pendingFavoriteCount = max(pendingFavoriteCount - 1, 0)
            dataManager.removeFromFavoriteCandidates(asset)
            dataManager.restoreReviewedState(asset, wasReviewed: wasReviewed)
            restoreSessionReviewedCount(wasReviewed: wasReviewed)
            restorePhotoPosition(asset, preferredIndex: originalIndex)
        case .skip(let asset, let originalIndex, let wasReviewed):
            cancelPendingSwipeMutation(for: asset)
            dataManager.restoreReviewedState(asset, wasReviewed: wasReviewed)
            restoreSessionReviewedCount(wasReviewed: wasReviewed)
            restorePhotoPosition(asset, preferredIndex: originalIndex)
        }
        HapticManager.notify(.success)
        showFeedback(L10n.string("已撤销上一步"), icon: "arrow.uturn.backward", style: .positive)
    }

    private func cancelDeleteCandidate(_ asset: PHAsset, at index: Int) {
        guard isAssetQueuedForDelete(asset) else { return }

        cancelPendingSwipeMutation(for: asset)
        dataManager.removeFromDeleteCandidates(asset)
        pendingDeleteCount = max(pendingDeleteCount - 1, 0)

        if let originalAction = removeLatestDeleteAction(for: asset) {
            dataManager.restoreReviewedState(asset, wasReviewed: originalAction.wasReviewed)
            restoreSessionReviewedCount(wasReviewed: originalAction.wasReviewed)
        }

        if isValidPhotoIndex(index) {
            currentPhotoIndex = index
        }
        persistSessionProgressIfPossible()
        HapticManager.impact(.light)
        showFeedback(L10n.string("已取消删除"), icon: "xmark.circle.fill", style: .neutral)
    }

    private func removeLatestDeleteAction(for asset: PHAsset) -> (originalIndex: Int, wasReviewed: Bool)? {
        let assetID = asset.localIdentifier
        for index in actionHistory.indices.reversed() {
            if case .delete(let actionAsset, let originalIndex, let wasReviewed) = actionHistory[index],
               actionAsset.localIdentifier == assetID {
                actionHistory.remove(at: index)
                return (originalIndex, wasReviewed)
            }
        }
        return nil
    }

    private func markDeleteCandidate(_ asset: PHAsset) {
        let originalIndex = currentPhotoIndex
        let wasReviewed = dataManager.isReviewed(asset)
        recordSessionReviewedChange(wasReviewed: wasReviewed)
        updateLocalPendingCountsForDelete(asset)
        scheduleSwipeMutation(asset, action: .delete)
        actionHistory.append(.delete(asset, originalIndex: originalIndex, wasReviewed: wasReviewed))
        HapticManager.impact(.medium)
        showFeedback(L10n.string("已加入待删除"), icon: "trash", style: .destructive, showsUndo: true)
    }

    private func markFavoriteCandidate(_ asset: PHAsset) {
        guard !asset.isFavorite else {
            markSkip(asset, message: L10n.string("已经是收藏"))
            return
        }

        let originalIndex = currentPhotoIndex
        let wasReviewed = dataManager.isReviewed(asset)
        recordSessionReviewedChange(wasReviewed: wasReviewed)
        updateLocalPendingCountsForFavorite(asset)
        scheduleSwipeMutation(asset, action: .favorite)
        actionHistory.append(.favorite(asset, originalIndex: originalIndex, wasReviewed: wasReviewed))
        HapticManager.impact(.light)
        showFeedback(L10n.string("已加入待收藏"), icon: "heart.fill", style: .favorite, showsUndo: true)
    }

    private func markSkip(_ asset: PHAsset, message: String? = nil) {
        let originalIndex = currentPhotoIndex
        let wasReviewed = dataManager.isReviewed(asset)
        recordSessionReviewedChange(wasReviewed: wasReviewed)
        scheduleSwipeMutation(asset, action: .keep)
        actionHistory.append(.skip(asset, originalIndex: originalIndex, wasReviewed: wasReviewed))
        HapticManager.impact(.light)
        showFeedback(message ?? L10n.string("已跳过"), icon: "arrow.right", style: .neutral)
    }

    private func handleAddToAlbum(_ albumInfo: AlbumInfo) {
        guard !showCompletionMessage,
              let asset = currentRealPhoto,
              let assetCollection = albumInfo.assetCollection else {
            showFeedback(L10n.string("无法归类到这个相册"), icon: "exclamationmark.triangle", style: .warning)
            return
        }

        // 将照片添加到指定相册
        let wasReviewed = dataManager.markReviewed(asset)
        recordSessionReviewedChange(wasReviewed: wasReviewed)
        HapticManager.impact(.light)
        showFeedback(L10n.string("正在归类到 \(albumInfo.title)"), icon: "tray.and.arrow.down", style: .neutral, duration: 1.0)
        dataManager.addPhotoToAlbum(asset, album: assetCollection) { success in
            DispatchQueue.main.async {
                if success {
                    // 添加成功后移动到下一张照片
                    HapticManager.notify(.success)
                    self.showFeedback(L10n.string("已归类到 \(albumInfo.title)"), icon: "checkmark.circle.fill", style: .positive)
                    self.moveToNextPhoto()
                } else {
                    self.dataManager.restoreReviewedState(asset, wasReviewed: wasReviewed)
                    self.restoreSessionReviewedCount(wasReviewed: wasReviewed)
                    HapticManager.notify(.error)
                    self.showFeedback(L10n.string("归类失败，请再试一次"), icon: "exclamationmark.triangle", style: .warning)
                }
            }
        }

        resetCardPosition()
    }

    private func resetCardPosition() {
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
            dragOffset = .zero
            rotationAngle = 0
        }
    }

    private func recordSessionReviewedChange(wasReviewed: Bool) {
        guard !wasReviewed else { return }
        sessionReviewedCount = min(sessionReviewedCount + 1, totalPhotosCount)
    }

    private func restoreSessionReviewedCount(wasReviewed: Bool) {
        guard !wasReviewed else { return }
        sessionReviewedCount = max(sessionReviewedCount - 1, 0)
    }

    private func syncPendingOperationCounts() {
        let committedDeleteIDs = Set(dataManager.deleteCandidates.map(\.localIdentifier))
        let committedFavoriteIDs = Set(dataManager.favoriteCandidates.map(\.localIdentifier))
        let pendingDeleteIDs = Set(
            pendingSwipeMutations.values
                .filter { $0.action == .delete }
                .map { $0.asset.localIdentifier }
        )
        let pendingFavoriteIDs = Set(
            pendingSwipeMutations.values
                .filter { $0.action == .favorite }
                .map { $0.asset.localIdentifier }
        )

        pendingDeleteCount = committedDeleteIDs.union(pendingDeleteIDs).count
        pendingFavoriteCount = committedFavoriteIDs.union(pendingFavoriteIDs).count
    }

    private func updateLocalPendingCountsForDelete(_ asset: PHAsset) {
        let assetID = asset.localIdentifier
        let currentPendingAction = pendingSwipeMutations[assetID]?.action
        let alreadyPendingDelete = currentPendingAction == .delete || dataManager.isInDeleteCandidates(asset)
        let wasPendingFavorite = currentPendingAction == .favorite || dataManager.isInFavoriteCandidates(asset)

        if !alreadyPendingDelete {
            pendingDeleteCount += 1
        }
        if wasPendingFavorite {
            pendingFavoriteCount = max(pendingFavoriteCount - 1, 0)
        }
    }

    private func updateLocalPendingCountsForFavorite(_ asset: PHAsset) {
        let assetID = asset.localIdentifier
        let currentPendingAction = pendingSwipeMutations[assetID]?.action
        let alreadyPendingFavorite = currentPendingAction == .favorite || dataManager.isInFavoriteCandidates(asset)
        let wasPendingDelete = currentPendingAction == .delete || dataManager.isInDeleteCandidates(asset)

        if !alreadyPendingFavorite {
            pendingFavoriteCount += 1
        }
        if wasPendingDelete {
            pendingDeleteCount = max(pendingDeleteCount - 1, 0)
        }
    }

    private func scheduleSwipeMutation(_ asset: PHAsset, action: SwipeGestureAction) {
        let assetID = asset.localIdentifier
        let token = UUID()
        pendingSwipeMutations[assetID] = PendingSwipeMutation(asset: asset, action: action, token: token)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard let mutation = pendingSwipeMutations[assetID], mutation.token == token else { return }
            applySwipeMutation(mutation)
            pendingSwipeMutations.removeValue(forKey: assetID)
            syncPendingOperationCounts()
        }
    }

    private func cancelPendingSwipeMutation(for asset: PHAsset) {
        pendingSwipeMutations.removeValue(forKey: asset.localIdentifier)
    }

    private func flushPendingSwipeMutations() {
        guard !pendingSwipeMutations.isEmpty else { return }
        let mutations = Array(pendingSwipeMutations.values)
        pendingSwipeMutations.removeAll()
        for mutation in mutations {
            applySwipeMutation(mutation)
        }
        syncPendingOperationCounts()
    }

    private func applySwipeMutation(_ mutation: PendingSwipeMutation) {
        _ = dataManager.markReviewed(mutation.asset)
        switch mutation.action {
        case .delete:
            dataManager.addToDeleteCandidates(mutation.asset)
        case .favorite:
            dataManager.addToFavoriteCandidates(mutation.asset)
        case .keep:
            break
        }
    }

    private func presentBatchConfirmation(dismissAfter: Bool) {
        flushPendingSwipeMutations()
        syncPendingOperationCounts()
        shouldDismissAfterBatch = dismissAfter
        showBatchConfirm = true
    }

    private func handleBackAction() {
        flushPendingSwipeMutations()
        // 如果有待处理的删除操作，显示确认对话框
        if hasPendingOperations {
            presentBatchConfirmation(dismissAfter: true)
        } else {
            dismiss()
        }
    }

    private var hasPendingOperations: Bool {
        pendingDeleteCount > 0 ||
            pendingFavoriteCount > 0 ||
            !dataManager.deleteCandidates.isEmpty ||
            !dataManager.favoriteCandidates.isEmpty
    }

    private var sessionModeTitle: String {
        if selectedAlbumInfo != nil {
            return L10n.string("相册整理")
        }
        if selectedDate != nil || selectedAdvancedTimeScope != nil {
            return L10n.string("日期整理")
        }
        if selectedAdvancedCleanup != nil {
            return L10n.string("智能清理")
        }
        return L10n.string("照片整理")
    }

    private func getDisplayTitle() -> String {
        if let albumInfo = selectedAlbumInfo {
            return albumInfo.title
        } else if let selectedDate, let selectedAdvancedTimeScope {
            return AdvancedSwipeDateFormatter.title(for: selectedAdvancedTimeScope, containing: selectedDate)
        } else if let selectedDate {
            return AdvancedSwipeDateFormatter.dayTitle.string(from: selectedDate)
        } else if let selectedAdvancedCleanup {
            return selectedAdvancedCleanup.title
        } else if let category = selectedCategory {
            return category.title
        } else if let timeGroup = selectedTimeGroup {
            return TimeGroup.fromIdentifier(timeGroup)?.title ?? timeGroup
        } else {
            return PhotoCategory.all.title
        }
    }

    private func showFeedback(
        _ message: String,
        icon: String,
        style: PhotoDeleteToastStyle,
        showsUndo: Bool = false,
        duration: TimeInterval = 3.0
    ) {
        let toast = PhotoDeleteToast(message: message, icon: icon, style: style, showsUndo: showsUndo)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            feedbackToast = toast
        }

        let visibleDuration = showsUndo ? max(duration, 4.5) : duration
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleDuration) {
            guard feedbackToast?.id == toast.id else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                feedbackToast = nil
            }
        }
    }
}

private struct BrowserPhotoTile: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let isSelected: Bool
    let isReviewed: Bool
    let isInDeleteCandidates: Bool
    let isInFavoriteCandidates: Bool
    let isScreenshot: Bool
    let isVideo: Bool
    let displaySize: CGSize
    let targetSize: CGSize
    let selectedTargetSize: CGSize
    let prefersHighQualityPreview: Bool
    let onSelect: () -> Void
    let onSwipeUpToDelete: () -> Void
    let onCancelDelete: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var thumbnailRequestID: PHImageRequestID?
    @State private var previewRequestID: PHImageRequestID?
    @State private var loadingAssetIdentifier: String?
    @State private var verticalOffset: CGFloat = 0
    @State private var showsDeleteCue = false

    private let cornerRadius: CGFloat = 18

    var body: some View {
        ZStack {
            tileImage

            topBadges
                .padding(9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            stateOverlay

            if showsDeleteCue {
                deleteCueOverlay
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isSelected ? PhotoDeleteStyle.accent : PhotoDeleteStyle.hairline, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? .black.opacity(0.18) : .clear, radius: isSelected ? 6 : 0, x: 0, y: isSelected ? 3 : 0)
        .offset(y: verticalOffset)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(deleteGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("浏览照片"))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text(L10n.string("选择"))) {
            onSelect()
        }
        .accessibilityAction(named: Text(L10n.string("加入待删除"))) {
            onSwipeUpToDelete()
        }
        .accessibilityAction(named: Text(L10n.string("取消删除这张照片"))) {
            if isInDeleteCandidates {
                onCancelDelete()
            }
        }
        .onAppear(perform: loadImage)
        .onChange(of: prefersHighQualityPreview) { shouldLoadPreview in
            if shouldLoadPreview {
                loadHighQualityPreview()
            } else {
                cancelHighQualityPreview()
            }
        }
        .onChange(of: targetSize) { _ in
            loadImage()
        }
        .onDisappear {
            photoLibraryManager.cancelImageRequest(thumbnailRequestID)
            photoLibraryManager.cancelImageRequest(previewRequestID)
            loadingAssetIdentifier = nil
        }
    }

    @ViewBuilder
    private var tileImage: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: displaySize.width, height: displaySize.height)
                .clipped()
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            PhotoDeleteStyle.surface,
                            PhotoDeleteStyle.elevatedSurface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.secondaryText.opacity(isLoading ? 0.34 : 0.7))
                }
        }
    }

    @ViewBuilder
    private var topBadges: some View {
        VStack(spacing: 7) {
            if isVideo {
                BrowserPhotoBadge(icon: "play.fill", color: .black.opacity(0.56))
            }

            if isScreenshot {
                BrowserPhotoBadge(icon: "camera.viewfinder", color: .black.opacity(0.56))
            }
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if isInDeleteCandidates || isInFavoriteCandidates {
            ZStack {
                PhotoDeleteStyle.background.opacity(0.74)

                VStack(spacing: 9) {
                    Image(systemName: isInDeleteCandidates ? "trash.fill" : "heart.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(isInDeleteCandidates ? PhotoDeleteStyle.destructive : PhotoDeleteStyle.iconTint(for: "favorite"))

                    Text(isInDeleteCandidates ? L10n.string("待删除") : L10n.string("待收藏"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    if isInDeleteCandidates {
                        Button(action: onCancelDelete) {
                            Label(L10n.string("取消"), systemImage: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(PhotoDeleteStyle.surface.opacity(0.82))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
    }

    private var deleteCueOverlay: some View {
        ZStack {
            PhotoDeleteStyle.destructive.opacity(0.74)

            VStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)

                Text(L10n.string("上滑删除"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    private var deleteGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                let horizontalDistance = abs(value.translation.width)
                let verticalDistance = abs(value.translation.height)
                let isUpwardDelete = value.translation.height < 0 && verticalDistance > horizontalDistance

                guard isUpwardDelete else { return }
                verticalOffset = max(value.translation.height * 0.35, -46)
                showsDeleteCue = verticalDistance > 26
            }
            .onEnded { value in
                let horizontalDistance = abs(value.translation.width)
                let verticalDistance = abs(value.translation.height)
                let shouldDelete = value.translation.height < -58 && verticalDistance > horizontalDistance * 1.15

                withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
                    verticalOffset = 0
                    showsDeleteCue = false
                }

                if shouldDelete {
                    onSwipeUpToDelete()
                }
            }
    }

    private var accessibilityValue: String {
        var values: [String] = []
        values.append(isVideo ? L10n.string("视频") : L10n.string("照片"))

        if isSelected {
            values.append(L10n.string("当前照片"))
        }

        if isScreenshot {
            values.append(L10n.string("截图"))
        }

        if isInDeleteCandidates {
            values.append(L10n.string("待删除"))
        } else if isInFavoriteCandidates {
            values.append(L10n.string("待收藏"))
        } else if isReviewed {
            values.append(L10n.string("已整理"))
        }

        return values.joined(separator: "，")
    }

    private func loadImage() {
        photoLibraryManager.cancelImageRequest(thumbnailRequestID)
        photoLibraryManager.cancelImageRequest(previewRequestID)
        let requestedAssetID = asset.localIdentifier
        loadingAssetIdentifier = requestedAssetID
        image = nil
        isLoading = true

        thumbnailRequestID = photoLibraryManager.loadGridThumbnail(for: asset, size: targetSize) { loadedImage in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            if let loadedImage {
                image = loadedImage
            }
            isLoading = false
            thumbnailRequestID = nil

            if prefersHighQualityPreview {
                loadHighQualityPreview()
            }
        }

        if prefersHighQualityPreview {
            loadHighQualityPreview()
        }
    }

    private func loadHighQualityPreview() {
        guard loadingAssetIdentifier == asset.localIdentifier else { return }
        guard previewRequestID == nil else { return }

        let requestedAssetID = asset.localIdentifier
        previewRequestID = photoLibraryManager.loadBrowserPreview(for: asset, size: selectedTargetSize) { loadedImage in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            if let loadedImage {
                image = loadedImage
            }
            previewRequestID = nil
        }
    }

    private func cancelHighQualityPreview() {
        photoLibraryManager.cancelImageRequest(previewRequestID)
        previewRequestID = nil
    }
}

private struct BrowserPhotoBadge: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(PhotoDeleteStyle.background.opacity(0.72), lineWidth: 1))
    }
}

private struct SwipePhotoCardFrame: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let isInDeleteCandidates: Bool
    let isInFavoriteCandidates: Bool
    let displaySize: CGSize
    let targetSize: CGSize

    var body: some View {
        RealPhotoCard(
            asset: asset,
            photoLibraryManager: photoLibraryManager,
            isInDeleteCandidates: isInDeleteCandidates,
            isInFavoriteCandidates: isInFavoriteCandidates,
            displaySize: displaySize,
            targetSize: targetSize
        )
    }
}

private struct PhotoSwipeDragFeedbackState {
    let direction: SwipePhotoView.SwipeDirection
    let action: SwipeGestureAction
    let progress: CGFloat
}

private struct PhotoSwipeDragFeedbackView: View {
    let feedback: PhotoSwipeDragFeedbackState

    var body: some View {
        ZStack {
            feedbackGlow
            directionStripe
            directionStroke
            hint
        }
        .opacity(0.28 + feedback.progress * 0.72)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var feedbackGlow: some View {
        switch feedback.direction {
        case .left:
            HStack(spacing: 0) {
                LinearGradient(
                    colors: glowColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: glowWidth)

                Spacer(minLength: 0)
            }
        case .right:
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                LinearGradient(
                    colors: glowColors.reversed(),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: glowWidth)
            }
        case .up:
            VStack(spacing: 0) {
                LinearGradient(
                    colors: glowColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 72 + feedback.progress * 34)

                Spacer(minLength: 0)
            }
        case .down:
            EmptyView()
        }
    }

    @ViewBuilder
    private var hint: some View {
        switch feedback.direction {
        case .left:
            VStack {
                Spacer()
                HStack {
                    SwipeEdgeHint(
                        icon: SwipeGestureDirection.left.icon,
                        title: "\(SwipeGestureDirection.left.title)\(feedback.action.title)",
                        color: feedback.action.tint
                    )
                    .padding(.leading, 14)
                    .padding(.bottom, 16)
                    .offset(x: -10 + feedback.progress * 10)
                    Spacer()
                }
            }
        case .right:
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    SwipeEdgeHint(
                        icon: SwipeGestureDirection.right.icon,
                        title: "\(SwipeGestureDirection.right.title)\(feedback.action.title)",
                        color: feedback.action.tint,
                        iconPlacement: .trailing
                    )
                    .padding(.trailing, 14)
                    .padding(.bottom, 16)
                    .offset(x: 10 - feedback.progress * 10)
                }
            }
        case .up:
            VStack {
                SwipeEdgeHint(
                    icon: SwipeGestureDirection.up.icon,
                    title: "\(SwipeGestureDirection.up.title)\(feedback.action.title)",
                    color: feedback.action.tint
                )
                .padding(.top, 16)
                .offset(y: -10 + feedback.progress * 10)
                Spacer()
            }
        case .down:
            EmptyView()
        }
    }

    private var glowColors: [Color] {
        [
            feedback.action.tint.opacity(0.24 + feedback.progress * 0.42),
            feedback.action.tint.opacity(0.08 + feedback.progress * 0.2),
            .clear
        ]
    }

    private var glowWidth: CGFloat {
        48 + feedback.progress * 58
    }

    @ViewBuilder
    private var directionStripe: some View {
        switch feedback.direction {
        case .left:
            HStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(feedback.action.tint)
                    .frame(width: 5 + feedback.progress * 5)
                    .padding(.vertical, 18)
                    .padding(.leading, 7)
                Spacer()
            }
        case .right:
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(feedback.action.tint)
                    .frame(width: 5 + feedback.progress * 5)
                    .padding(.vertical, 18)
                    .padding(.trailing, 7)
            }
        case .up:
            VStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(feedback.action.tint)
                    .frame(height: 5 + feedback.progress * 5)
                    .padding(.horizontal, 26)
                    .padding(.top, 7)
                Spacer()
            }
        case .down:
            EmptyView()
        }
    }

    private var directionStroke: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(feedback.action.tint.opacity(0.24 + feedback.progress * 0.34), lineWidth: 1 + feedback.progress * 1.4)
    }
}

private struct SwipeEdgeHint: View {
    enum IconPlacement {
        case leading
        case trailing
    }

    let icon: String
    let title: String
    let color: Color
    var iconPlacement: IconPlacement = .leading

    var body: some View {
        HStack(spacing: 6) {
            if iconPlacement == .leading {
                iconView
            }

            Text(title.appLocalized)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if iconPlacement == .trailing {
                iconView
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.16 + 0.1))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(color.opacity(0.46), lineWidth: 1)
                )
        )
        .shadow(color: PhotoDeleteStyle.floatingShadow, radius: 8, x: 0, y: 4)
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(color)
    }
}

private enum AdvancedSwipeDateFormatter {
    static func title(for scope: AdvancedTimeScope, containing date: Date) -> String {
        switch scope {
        case .day:
            return dayTitle.string(from: date)
        case .week:
            let components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return L10n.string("\(components.yearForWeekOfYear ?? 0) 年第 \(components.weekOfYear ?? 0) 周")
        case .month:
            return monthTitle.string(from: date)
        case .year:
            return yearTitle.string(from: date)
        }
    }

    static let dayTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMEd")
        return formatter
    }()

    private static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("y年M月")
        return formatter
    }()

    private static let yearTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("y年")
        return formatter
    }()
}

// MARK: - 真实照片卡片
struct RealPhotoCard: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let isInDeleteCandidates: Bool
    let isInFavoriteCandidates: Bool
    let displaySize: CGSize
    let targetSize: CGSize

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var thumbnailRequestID: PHImageRequestID?
    @State private var previewRequestID: PHImageRequestID?
    @State private var fallbackRequestID: PHImageRequestID?
    @State private var loadingAssetIdentifier: String?

    var body: some View {
        ZStack {
            if let image = image {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.22))

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displaySize.width, height: displaySize.height)
                }
                    .frame(width: displaySize.width, height: displaySize.height)
                    .clipped()
                    .cornerRadius(20)
                    .overlay(
                        overlayContent,
                        alignment: .topTrailing
                    )
                    .overlay(
                        candidateOverlay,
                        alignment: .center
                    )
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                PhotoDeleteStyle.surface,
                                PhotoDeleteStyle.elevatedSurface
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: displaySize.width, height: displaySize.height)
                    .cornerRadius(20)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                                    .scaleEffect(1.2)
                            } else {
                                VStack(spacing: 10) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                                        .scaleEffect(1.0)
                                }
                            }
                        }
                    )
                    .frame(width: displaySize.width, height: displaySize.height)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
        )
        .shadow(color: PhotoDeleteStyle.floatingShadow, radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("当前照片"))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(L10n.string("可使用可访问性操作加入待删除、加入收藏或跳过。"))
        .onAppear {
            loadImage()
        }
        .onDisappear {
            photoLibraryManager.cancelImageRequest(thumbnailRequestID)
            photoLibraryManager.cancelImageRequest(previewRequestID)
            photoLibraryManager.cancelImageRequest(fallbackRequestID)
            loadingAssetIdentifier = nil
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        VStack(spacing: 8) {
            if asset.mediaType == .video {
                ZStack {
                    Circle()
                        .fill(PhotoDeleteStyle.background.opacity(0.62))
                        .frame(width: 30, height: 30)

                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
            }

            if photoLibraryManager.isScreenshot(asset) {
                ZStack {
                    Circle()
                        .fill(PhotoDeleteStyle.background.opacity(0.62))
                        .frame(width: 30, height: 30)

                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var candidateOverlay: some View {
        if isInDeleteCandidates || isInFavoriteCandidates {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PhotoDeleteStyle.background.opacity(0.72))

                VStack(spacing: 12) {
                    Image(systemName: isInDeleteCandidates ? "trash.fill" : "heart.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundColor(isInDeleteCandidates ? PhotoDeleteStyle.destructive : PhotoDeleteStyle.iconTint(for: "favorite"))

                    Text(isInDeleteCandidates ? L10n.string("待删除") : L10n.string("待收藏"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            .cornerRadius(20)
        }
    }

    private func loadImage() {
        photoLibraryManager.cancelImageRequest(thumbnailRequestID)
        photoLibraryManager.cancelImageRequest(previewRequestID)
        photoLibraryManager.cancelImageRequest(fallbackRequestID)
        isLoading = true
        image = nil
        fallbackRequestID = nil
        let requestedAssetID = asset.localIdentifier
        loadingAssetIdentifier = requestedAssetID

        let thumbnailSize = CGSize(
            width: min(targetSize.width, 1_100),
            height: min(targetSize.height, 1_500)
        )

        thumbnailRequestID = photoLibraryManager.loadFastThumbnail(for: asset, size: thumbnailSize) { loadedImage in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            if let loadedImage {
                self.image = loadedImage
                self.isLoading = false
            }
            self.thumbnailRequestID = nil
        }

        previewRequestID = photoLibraryManager.loadSwipePreview(for: asset, size: targetSize) { loadedImage in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            if let loadedImage {
                self.image = loadedImage
                self.isLoading = false
            } else if self.image == nil {
                self.loadFallbackImage(for: requestedAssetID)
            }
            self.previewRequestID = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            guard loadingAssetIdentifier == requestedAssetID, image == nil else { return }
            loadFallbackImage(for: requestedAssetID)
        }
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if asset.mediaType == .video {
            values.append(L10n.string("视频"))
        } else {
            values.append(L10n.string("照片"))
        }

        if photoLibraryManager.isScreenshot(asset) {
            values.append(L10n.string("截图"))
        }

        if asset.isFavorite || isInFavoriteCandidates {
            values.append(L10n.string("收藏"))
        }

        if isInDeleteCandidates {
            values.append(L10n.string("待删除"))
        } else if isInFavoriteCandidates {
            values.append(L10n.string("待收藏"))
        }

        return values.joined(separator: "，")
    }

    private func loadFallbackImage(for requestedAssetID: String) {
        guard fallbackRequestID == nil else { return }

        fallbackRequestID = photoLibraryManager.loadHighQualityPreview(for: asset, size: targetSize) { loadedImage in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            if let loadedImage {
                self.image = loadedImage
                self.isLoading = false
            }
            self.fallbackRequestID = nil
        }
    }
}

private struct PhotoSelectionLoadingCard: View {
    let title: String
    let message: String
    let progress: Double

    var body: some View {
        VStack(spacing: 16) {
            if progress > 0.01 {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                        .frame(maxWidth: 230)
                        .clipShape(Capsule(style: .continuous))

                    Text(L10n.percent(Int(progress * 100)))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.tertiaryText)
                }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    .scaleEffect(1.05)
            }

            VStack(spacing: 7) {
                Text(title.appLocalized)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(message.appLocalized)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .photoDeleteCard()
    }
}

private struct AlbumMicroButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.appLocalized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .truncationMode(.tail)
                .frame(width: 82)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(PhotoDeleteStyle.surface.opacity(0.64))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(PhotoDeleteStyle.hairline.opacity(0.78), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PhotoDeletePressScaleButtonStyle())
        .accessibilityLabel(Text(L10n.string("归类到 \(title)")))
    }
}

private struct PhotoDeletePressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

// MARK: - 滑动指示器
struct SwipeIndicator: View {
    let direction: SwipePhotoView.SwipeDirection
    let action: SwipeGestureAction

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: directionIcon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(action.tint)

            Image(systemName: action.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(action.tint)

            Text(action.detailTitle.appLocalized)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(PhotoDeleteStyle.background.opacity(0.82))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(action.tint.opacity(0.38), lineWidth: 1)
                )
        )
        .offset(indicatorOffset)
    }

    private var directionIcon: String {
        switch direction {
        case .left:
            return "arrow.left"
        case .right:
            return "arrow.right"
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        }
    }

    private var indicatorOffset: CGSize {
        switch direction {
        case .left:
            return CGSize(width: -100, height: 0)
        case .right:
            return CGSize(width: 100, height: 0)
        case .up:
            return CGSize(width: 0, height: -100)
        case .down:
            return CGSize(width: 0, height: 100)
        }
    }
}

// MARK: - 功能按钮
enum PhotoDeleteActionButtonStyle {
    case quiet
    case soft
    case solid
}

struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    var style: PhotoDeleteActionButtonStyle = .soft
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(buttonBackground)

                Text(title.appLocalized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 60)
        }
        .buttonStyle(PhotoDeletePressScaleButtonStyle())
    }

    private var buttonSize: CGFloat {
        style == .quiet ? 42 : 46
    }

    private var iconColor: Color {
        style == .solid ? .white : color
    }

    private var labelColor: Color {
        style == .solid ? PhotoDeleteStyle.primaryText : PhotoDeleteStyle.secondaryText
    }

    private var buttonBackground: some View {
        Circle()
            .fill(backgroundFill)
            .overlay(
                Circle()
                    .stroke(strokeColor, lineWidth: 1)
            )
    }

    private var backgroundFill: Color {
        switch style {
        case .quiet:
            return PhotoDeleteStyle.elevatedSurface.opacity(0.72)
        case .soft:
            return color.opacity(0.13)
        case .solid:
            return color
        }
    }

    private var strokeColor: Color {
        switch style {
        case .quiet:
            return PhotoDeleteStyle.hairline
        case .soft:
            return color.opacity(0.18)
        case .solid:
            return color.opacity(0.0)
        }
    }
}

private struct ReviewModeToggleButton: View {
    let mode: PhotoReviewMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.string("整理模式"), systemImage: mode.toolbarIcon)
                .labelStyle(.iconOnly)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(PhotoDeleteStyle.surface)
                        .overlay(
                            Circle()
                                .stroke(PhotoDeleteStyle.accent.opacity(0.28), lineWidth: 1)
                        )
                )
                .photoDeleteMinimumTapTarget()
        }
        .buttonStyle(PhotoDeletePressScaleButtonStyle())
        .accessibilityValue(mode.accessibilityTitle)
        .accessibilityHint(mode.toggleAccessibilityHint)
    }
}

private struct PendingDeleteCounter: View {
    let count: Int

    private var isActive: Bool {
        count > 0
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isActive ? PhotoDeleteStyle.destructive : PhotoDeleteStyle.tertiaryText)

            Text("\(count)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isActive ? PhotoDeleteStyle.primaryText : PhotoDeleteStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(width: 50, height: 38)
        .background(
            Capsule(style: .continuous)
                .fill(isActive ? PhotoDeleteStyle.destructive.opacity(0.12) : PhotoDeleteStyle.surface)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isActive ? PhotoDeleteStyle.destructive.opacity(0.26) : PhotoDeleteStyle.cardStroke, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("待删除 \(count) 张"))
    }
}

struct GestureGuideRow: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 18)

            Text(title.appLocalized)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            Spacer()

            Text(detail.appLocalized)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
        }
    }
}

struct SidebarActionButton: View {
    let icon: String
    let title: String
    let color: Color
    var isCompact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 20)

                Text(title.appLocalized)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if !isCompact {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PhotoDeleteStyle.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(color.opacity(0.32), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 批量确认视图
struct BatchConfirmView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var previewAsset: CandidatePreviewAsset?
    @State private var completedCelebration: CleanupCelebration?
    @State private var showAchievements = false
    let albumInfo: AlbumInfo?
    let onComplete: (() -> Void)?

    init(albumInfo: AlbumInfo? = nil, onComplete: (() -> Void)? = nil) {
        self.albumInfo = albumInfo
        self.onComplete = onComplete
    }

    private var hasPendingOperations: Bool {
        !dataManager.deleteCandidates.isEmpty || !dataManager.favoriteCandidates.isEmpty
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            if let completedCelebration {
                BatchCleanupCompletionView(
                    celebration: completedCelebration,
                    onViewAchievements: { showAchievements = true },
                    onContinue: finishCompletedFlow
                )
                .transition(.opacity)
            } else {
                let deleteAssets = sortedAssets(Array(dataManager.deleteCandidates))
                let favoriteAssets = sortedAssets(Array(dataManager.favoriteCandidates))
                let estimatedSpaceSaved = deleteAssets.reduce(0) { $0 + dataManager.estimatedSizeMB(for: $1) }

                confirmationContent(
                    deleteAssets: deleteAssets,
                    favoriteAssets: favoriteAssets,
                    estimatedSpaceSaved: estimatedSpaceSaved
                )
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: completedCelebration?.id)
        .sheet(item: $previewAsset) { previewAsset in
            CandidatePhotoPreviewView(
                asset: previewAsset.asset,
                photoLibraryManager: dataManager.photoLibraryManager
            )
        }
        .fullScreenCover(isPresented: $showAchievements) {
            NavigationStack {
                CleanupAchievementsView(
                    statsStore: dataManager.cleanupStatsStore,
                    showsDoneButton: true
                )
            }
        }
    }

    private func confirmationContent(
        deleteAssets: [PHAsset],
        favoriteAssets: [PHAsset],
        estimatedSpaceSaved: Double
    ) -> some View {
        VStack(spacing: 22) {
            VStack(spacing: 16) {
                Image(systemName: dataManager.deleteCandidates.isEmpty ? "checkmark.circle.fill" : "trash.circle.fill")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundColor(dataManager.deleteCandidates.isEmpty ? PhotoDeleteStyle.positive : PhotoDeleteStyle.destructive)

                Text(L10n.string("确认清理"))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                VStack(spacing: 8) {
                    if !dataManager.deleteCandidates.isEmpty {
                        Text(L10n.string("删除 \(dataManager.deleteCandidates.count) 张照片"))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.destructive)

                        Text(L10n.string("预计节省 \(CleanupStatsFormatter.space(estimatedSpaceSaved))"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.positive)
                    }

                    if !dataManager.favoriteCandidates.isEmpty {
                        Text(L10n.string("收藏 \(dataManager.favoriteCandidates.count) 张照片"))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.iconTint(for: "favorite"))
                    }

                    if !hasPendingOperations {
                        Text(L10n.string("没有待执行的操作"))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.warning)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
            }

            if hasPendingOperations {
                ScrollView {
                    VStack(spacing: 18) {
                        if !deleteAssets.isEmpty {
                            CandidatePreviewSection(
                                title: L10n.string("将删除"),
                                assets: deleteAssets,
                                color: PhotoDeleteStyle.destructive,
                                icon: "trash.fill",
                                photoLibraryManager: dataManager.photoLibraryManager,
                                removeAccessibilityLabel: L10n.string("取消删除这张照片"),
                                onPreview: { previewAsset = CandidatePreviewAsset(asset: $0) },
                                onRemove: { dataManager.removeFromDeleteCandidates($0) }
                            )
                        }

                        if !favoriteAssets.isEmpty {
                            CandidatePreviewSection(
                                title: L10n.string("将收藏"),
                                assets: favoriteAssets,
                                color: PhotoDeleteStyle.iconTint(for: "favorite"),
                                icon: "heart.fill",
                                photoLibraryManager: dataManager.photoLibraryManager,
                                removeAccessibilityLabel: L10n.string("取消收藏这张照片"),
                                onPreview: { previewAsset = CandidatePreviewAsset(asset: $0) },
                                onRemove: { dataManager.removeFromFavoriteCandidates($0) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 330)
            }

            VStack(spacing: 12) {
                Button(action: executeBatchOperations) {
                    Text(isProcessing ? L10n.string("正在执行...") : L10n.string("确认执行"))
                }
                .photoDeletePrimaryButton()
                .disabled(isProcessing || !hasPendingOperations)

                Button(action: cancelOperations) {
                    Text(L10n.string("取消操作"))
                }
                .photoDeleteSecondaryButton()
                .disabled(isProcessing)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .photoDeleteCard()
        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
    }

    private func executeBatchOperations() {
        guard hasPendingOperations else {
            dismiss()
            return
        }

        isProcessing = true
        errorMessage = nil
        let deletedAssets = Array(dataManager.deleteCandidates)
        let favoriteAssets = Array(dataManager.favoriteCandidates)
        let estimatedSpaceSaved = deletedAssets.reduce(0) { $0 + dataManager.estimatedSizeMB(for: $1) }
        dataManager.executeBatchOperations { success, error, celebration in
            DispatchQueue.main.async {
                isProcessing = false
                if success {
                    dataManager.recordDeletedPhotosFromAlbum(
                        albumID: albumInfo?.id,
                        deletedAssets: deletedAssets
                    )
                    completedCelebration = celebration ?? CleanupCelebration(
                        deletedPhotos: deletedAssets.count,
                        favoritedPhotos: favoriteAssets.count,
                        organizedPhotos: deletedAssets.count + favoriteAssets.count,
                        estimatedSpaceSavedMB: estimatedSpaceSaved,
                        totalDeletedPhotos: dataManager.cleanupStatsStore.summary.deletedPhotos,
                        totalSpaceSavedMB: dataManager.cleanupStatsStore.summary.estimatedSpaceSavedMB,
                        currentStreakDays: dataManager.cleanupStatsStore.currentStreakDays,
                        nextAchievementProgress: dataManager.cleanupStatsStore.nextAchievementProgress
                    )
                    HapticManager.notify(.success)
                } else {
                    errorMessage = error?.localizedDescription ?? L10n.string("操作失败，请稍后重试。")
                }
            }
        }
    }

    private func finishCompletedFlow() {
        dismiss()
        onComplete?()
    }

    private func cancelOperations() {
        dataManager.cancelAllOperations()
        dismiss()
    }

    private func sortedAssets(_ assets: [PHAsset]) -> [PHAsset] {
        assets.sorted { lhs, rhs in
            let lhsDate = lhs.creationDate ?? .distantPast
            let rhsDate = rhs.creationDate ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.localIdentifier < rhs.localIdentifier
            }
            return lhsDate > rhsDate
        }
    }
}

private struct BatchCleanupCompletionView: View {
    let celebration: CleanupCelebration
    let onViewAchievements: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false
    @State private var progressFill = 0.0

    private let particleColors: [Color] = [
        PhotoDeleteStyle.accent,
        PhotoDeleteStyle.positive,
        PhotoDeleteStyle.warning,
        PhotoDeleteStyle.destructive
    ]
    private let particleCount = 12

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 14) {
                    celebrationVisual
                        .opacity(animate ? 1 : 0)
                        .offset(y: animate ? 0 : 10)
                        .animation(entranceAnimation(delay: 0), value: animate)

                    completionHeader
                        .opacity(animate ? 1 : 0)
                        .offset(y: animate ? 0 : 10)
                        .animation(entranceAnimation(delay: 0.06), value: animate)

                    cleanupSummarySection
                        .opacity(animate ? 1 : 0)
                        .offset(y: animate ? 0 : 14)
                        .animation(entranceAnimation(delay: 0.12), value: animate)

                    progressSnapshotSection
                        .opacity(animate ? 1 : 0)
                        .offset(y: animate ? 0 : 14)
                        .animation(entranceAnimation(delay: 0.18), value: animate)

                    completionActions
                        .opacity(animate ? 1 : 0)
                        .offset(y: animate ? 0 : 14)
                        .animation(entranceAnimation(delay: 0.24), value: animate)
                }
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, max(28, geometry.safeAreaInsets.top + 18))
                .padding(.bottom, max(34, geometry.safeAreaInsets.bottom + 28))
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            let targetProgress = celebration.nextAchievementProgress?.progress ?? 1
            if reduceMotion {
                animate = true
                progressFill = targetProgress
            } else {
                progressFill = 0
                withAnimation(.spring(response: 0.54, dampingFraction: 0.86)) {
                    animate = true
                }
                withAnimation(.easeOut(duration: 0.72).delay(0.34)) {
                    progressFill = targetProgress
                }
            }
        }
    }

    private var celebrationVisual: some View {
        ZStack {
            if reduceMotion {
                Image(systemName: "sparkles")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.warning)
            } else {
                ForEach(0..<particleCount, id: \.self) { index in
                    particle(index)
                }

                Circle()
                    .fill(PhotoDeleteStyle.accent.opacity(0.1))
                    .frame(width: 112, height: 112)
                    .scaleEffect(animate ? 1 : 0.74)
                    .opacity(animate ? 1 : 0)

                Circle()
                    .stroke(PhotoDeleteStyle.warning.opacity(0.22), lineWidth: 1)
                    .frame(width: 92, height: 92)
                    .scaleEffect(animate ? 1.08 : 0.78)
                    .opacity(animate ? 1 : 0)

                Image(systemName: "sparkles")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.warning)
                    .scaleEffect(animate ? 1 : 0.76)
                    .rotationEffect(.degrees(animate ? 0 : -8))
            }
        }
        .frame(height: 124)
        .animation(.spring(response: 0.58, dampingFraction: 0.78), value: animate)
    }

    private var completionHeader: some View {
        Text(L10n.string("清理完成"))
            .font(.system(size: 30, weight: .bold))
            .foregroundColor(PhotoDeleteStyle.primaryText)
    }

    private var cleanupSummarySection: some View {
        HStack(spacing: 12) {
            summaryItem(
                icon: "trash.fill",
                title: L10n.string("本次删除"),
                value: L10n.shortPhotoCount(celebration.deletedPhotos),
                detail: "\(L10n.string("节省")) \(celebration.formattedSpaceSaved)",
                tint: PhotoDeleteStyle.destructive
            )

            Divider()
                .frame(height: 34)
                .background(PhotoDeleteStyle.hairline)

            summaryItem(
                icon: "chart.bar.fill",
                title: L10n.string("累计删除"),
                value: L10n.shortPhotoCount(celebration.totalDeletedPhotos),
                detail: "\(L10n.string("节省")) \(celebration.formattedTotalSpaceSaved)",
                tint: PhotoDeleteStyle.accent
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PhotoDeleteStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PhotoDeleteStyle.cardStroke, lineWidth: 1)
                )
        )
    }

    private func summaryItem(icon: String, title: String, value: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(detail)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completionActions: some View {
        VStack(spacing: 10) {
            Button(action: onViewAchievements) {
                Label(L10n.string("查看成就"), systemImage: "seal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundColor(PhotoDeleteStyle.primaryText)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PhotoDeleteStyle.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(PhotoDeleteStyle.cardStroke, lineWidth: 1)
                    )
            )

            Button(action: onContinue) {
                Text(L10n.string("继续整理"))
            }
            .photoDeletePrimaryButton()
        }
    }

    private var progressSnapshotSection: some View {
        VStack(spacing: 0) {
            if let newestAchievement = celebration.newAchievements.first {
                compactStatusRow(
                    icon: newestAchievement.systemImage,
                    tint: newestAchievement.tint.color,
                    title: L10n.string("新徽章：\(newestAchievement.title)"),
                    subtitle: newestAchievement.subtitle
                )

                Divider()
                    .padding(.leading, 48)
            }

            compactStatusRow(
                icon: "flame.fill",
                tint: PhotoDeleteStyle.warning,
                title: L10n.string("连续整理 \(streakDaysForDisplay) 天"),
                subtitle: L10n.string("保持节奏，相册会越来越轻。")
            )

            Divider()
                .padding(.leading, 48)

            if let nextAchievementProgress = celebration.nextAchievementProgress {
                compactNextGoalRow(nextAchievementProgress)
            } else {
                compactStatusRow(
                    icon: "checkmark.seal.fill",
                    tint: PhotoDeleteStyle.positive,
                    title: L10n.string("全部徽章已完成"),
                    subtitle: L10n.string("可以在成就页回看完整记录。")
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(PhotoDeleteStyle.cardStroke, lineWidth: 1)
                )
        )
    }

    private func compactStatusRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(
                icon: icon,
                tint: tint,
                size: 34,
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer()
        }
        .padding(14)
    }

    private var streakDaysForDisplay: Int {
        max(celebration.currentStreakDays, celebration.organizedPhotos > 0 ? 1 : 0)
    }

    private func compactNextGoalRow(_ progress: CleanupAchievementProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PhotoDeleteIconTile(
                    icon: progress.achievement.systemImage,
                    tint: progress.achievement.tint.color,
                    size: 34,
                    cornerRadius: 10
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("下一个目标：\(progress.achievement.title)"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(progress.remainingDescription)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(PhotoDeleteStyle.hairline)

                    Capsule(style: .continuous)
                        .fill(progress.achievement.tint.color)
                        .frame(width: max(0, proxy.size.width * progressFill))
                }
            }
            .frame(height: 7)
        }
        .padding(14)
    }

    private func particle(_ index: Int) -> some View {
        let angle = Double(index) / Double(particleCount) * Double.pi * 2
        let distance = CGFloat(34 + (index % 4) * 13)
        let x = CGFloat(cos(angle)) * distance
        let y = CGFloat(sin(angle)) * distance
        let size = CGFloat(4 + (index % 3) * 2)

        return Circle()
            .fill(particleColors[index % particleColors.count])
            .frame(width: size, height: size)
            .offset(x: animate ? x : x * 0.22, y: animate ? y : y * 0.22)
            .opacity(animate ? 0.74 : 0)
            .scaleEffect(animate ? 1 : 0.45)
            .animation(
                .spring(response: 0.58, dampingFraction: 0.82)
                    .delay(Double(index) * 0.018),
                value: animate
            )
    }

    private func entranceAnimation(delay: Double) -> Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12).delay(delay)
        }
        return .spring(response: 0.5, dampingFraction: 0.86).delay(delay)
    }
}

private struct CandidatePreviewSection: View {
    let title: String
    let assets: [PHAsset]
    let color: Color
    let icon: String
    let photoLibraryManager: PhotoLibraryManager
    let removeAccessibilityLabel: String
    let onPreview: (PHAsset) -> Void
    let onRemove: (PHAsset) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 64, maximum: 76), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)

                Text(L10n.string("\(title) \(assets.count) 张"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Spacer()
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    CandidateThumbnailView(
                        asset: asset,
                        photoLibraryManager: photoLibraryManager,
                        badgeColor: color,
                        badgeIcon: icon,
                        removeAccessibilityLabel: removeAccessibilityLabel,
                        onPreview: { onPreview(asset) },
                        onRemove: { onRemove(asset) }
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PhotoDeleteStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(color.opacity(0.24), lineWidth: 1)
                )
        )
    }
}

private struct CandidateThumbnailView: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let badgeColor: Color
    let badgeIcon: String
    let removeAccessibilityLabel: String
    let onPreview: () -> Void
    let onRemove: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var requestID: PHImageRequestID?
    @State private var loadingAssetIdentifier: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: onPreview) {
                thumbnailContent
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("放大查看照片"))

            Image(systemName: badgeIcon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(badgeColor))
                .overlay(Circle().stroke(PhotoDeleteStyle.background.opacity(0.8), lineWidth: 1.5))
                .offset(x: -53, y: -53)

            Button(action: onRemove) {
                Label(removeAccessibilityLabel, systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(PhotoDeleteStyle.background.opacity(0.9)))
                    .overlay(Circle().stroke(PhotoDeleteStyle.primaryText.opacity(0.18), lineWidth: 1))
                    .photoDeleteMinimumTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.string("从本次批量操作中移除"))
            .offset(x: 3, y: 3)
        }
        .frame(width: 76, height: 76)
        .onAppear(perform: loadImage)
        .onDisappear {
            photoLibraryManager.cancelImageRequest(requestID)
            loadingAssetIdentifier = nil
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(PhotoDeleteStyle.elevatedSurface)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                            .scaleEffect(0.72)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                    }
                }
        }
    }

    private func loadImage() {
        photoLibraryManager.cancelImageRequest(requestID)
        let requestedAssetID = asset.localIdentifier
        loadingAssetIdentifier = requestedAssetID
        image = nil
        isLoading = true

        requestID = photoLibraryManager.loadFastThumbnail(for: asset, size: CGSize(width: 150, height: 150)) { loadedImage in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            image = loadedImage
            isLoading = false
            requestID = nil
            loadingAssetIdentifier = nil
        }
    }
}

private struct CandidatePreviewAsset: Identifiable {
    let asset: PHAsset

    var id: String {
        asset.localIdentifier
    }
}

struct PhotoAssetVideoPlayerView: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    var autoPlay = true

    @State private var player: AVPlayer?
    @State private var requestID: PHImageRequestID?
    @State private var isLoading = true
    @State private var didFail = false
    @State private var loadingAssetIdentifier: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        if autoPlay {
                            player.play()
                        }
                    }
            } else {
                VStack(spacing: 14) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    } else {
                        Image(systemName: "play.slash")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                    }

                    Text(isLoading ? L10n.string("正在读取视频") : L10n.string("无法播放这个视频"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
        .accessibilityLabel(didFail ? L10n.string("无法播放这个视频") : L10n.string("视频预览"))
        .onAppear(perform: loadPlayer)
        .onDisappear(perform: cleanup)
    }

    private func loadPlayer() {
        guard player == nil, requestID == nil else { return }

        let requestedAssetID = asset.localIdentifier
        loadingAssetIdentifier = requestedAssetID
        isLoading = true
        didFail = false

        requestID = photoLibraryManager.loadPlayerItem(for: asset) { playerItem in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            requestID = nil
            isLoading = false

            guard let playerItem else {
                didFail = true
                return
            }

            let loadedPlayer = AVPlayer(playerItem: playerItem)
            player = loadedPlayer
            if autoPlay {
                loadedPlayer.play()
            }
        }
    }

    private func cleanup() {
        photoLibraryManager.cancelImageRequest(requestID)
        requestID = nil
        loadingAssetIdentifier = nil
        player?.pause()
        player = nil
    }
}

private struct CandidatePhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var requestID: PHImageRequestID?
    @State private var zoomScale: CGFloat = 1
    @State private var settledZoomScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    PhotoDeleteStyle.background.ignoresSafeArea()

                    if asset.mediaType == .video {
                        PhotoAssetVideoPlayerView(
                            asset: asset,
                            photoLibraryManager: photoLibraryManager
                        )
                    } else if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoomScale)
                            .gesture(zoomGesture)
                            .onTapGesture(count: 2, perform: toggleZoom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel(L10n.string("放大的照片"))
                    } else {
                        VStack(spacing: 14) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 36, weight: .medium))
                                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                            }

                            Text(isLoading ? L10n.string("正在读取照片") : L10n.string("无法读取这张照片"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                        }
                    }
                }
                .onAppear {
                    if asset.mediaType != .video {
                        loadImage(in: geometry.size)
                    }
                }
            }
            .navigationTitle(asset.mediaType == .video ? L10n.string("视频预览") : L10n.string("照片预览"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("关闭")) {
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            photoLibraryManager.cancelImageRequest(requestID)
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomScale = min(max(settledZoomScale * value, 1), 4)
            }
            .onEnded { _ in
                settledZoomScale = zoomScale
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            if zoomScale > 1 {
                zoomScale = 1
                settledZoomScale = 1
            } else {
                zoomScale = 2
                settledZoomScale = 2
            }
        }
    }

    private func loadImage(in size: CGSize) {
        guard requestID == nil, image == nil else { return }
        isLoading = true
        let targetSize = CGSize(
            width: max(size.width * displayScale, 800),
            height: max(size.height * displayScale, 1_200)
        )

        requestID = photoLibraryManager.loadHighQualityPreview(for: asset, size: targetSize) { loadedImage in
            image = loadedImage
            isLoading = false
            requestID = nil
        }
    }
}

#Preview {
    SwipePhotoView(selectedCategory: PhotoCategory.all, selectedTimeGroup: nil, selectedAlbumInfo: nil)
        .environmentObject(DataManager())
}
