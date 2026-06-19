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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppConstants.leftSwipeActionKey) private var leftSwipeActionValue = SwipeGesturePreset.standard.leftAction.rawValue
    @AppStorage(AppConstants.rightSwipeActionKey) private var rightSwipeActionValue = SwipeGesturePreset.standard.rightAction.rawValue
    @AppStorage(AppConstants.upSwipeActionKey) private var upSwipeActionValue = SwipeGesturePreset.standard.upAction.rawValue
    @AppStorage(AppConstants.reviewModeKey) private var reviewModeValue = PhotoReviewMode.card.rawValue
    @AppStorage(AppConstants.hasSeenReviewModeHintKey) private var hasSeenReviewModeHint = false
    @AppStorage(AppConstants.hasSeenAlbumShortcutHintKey) private var hasSeenAlbumShortcutHint = false
    @AppStorage(AppConstants.hasSeenDeleteButtonTipKey) private var hasSeenDeleteButtonTip = false

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
    @State private var sessionProgressSaveWorkItem: DispatchWorkItem?
    @State private var previewAsset: CandidatePreviewAsset?
    @State private var inlinePlayingVideoAssetID: String?
    @State private var cardModeReviewActionCount = 0
    @State private var showReviewModeHint = false
    @State private var showAlbumShortcutHint = false
    @State private var showDeleteButtonTip = false
    @State private var sessionDeleteActionCount = 0
    @State private var albumFilingAssetIDs: Set<String> = []
    @State private var recentlyFiledAlbumAssetIDs: Set<String> = []

    private let reviewModeHintThreshold = 5
    private let deleteButtonTipThreshold = 3
    private let albumShortcutTwoRowThreshold = 4
    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

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

    private var isCurrentPhotoBeingFiled: Bool {
        guard let asset = currentRealPhoto else { return false }
        return isAssetBeingFiledToAlbum(asset)
    }

    private var canPerformPhotoAction: Bool {
        currentRealPhoto != nil && !showCompletionMessage && !isCurrentPhotoBeingFiled
    }

    private var reviewMode: PhotoReviewMode {
        PhotoReviewMode.normalized(reviewModeValue)
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            GeometryReader { geometry in
                let usesSidebar = PhotoDeleteAdaptiveLayout.prefersReviewSidebar(
                    in: geometry.size,
                    horizontalSizeClass: horizontalSizeClass
                )
                let sidebarWidth = PhotoDeleteAdaptiveLayout.reviewSidebarWidth(totalWidth: geometry.size.width)

                ZStack(alignment: .bottom) {
                    if usesSidebar {
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                navigationHeader
                                photoArea
                            }
                            .frame(width: geometry.size.width - sidebarWidth)

                            landscapeSidebar
                                .frame(width: sidebarWidth, height: geometry.size.height)
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
                        .padding(.bottom, usesSidebar ? 24 : portraitToastBottomPadding)
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
            stopInlineVideoPlayback()
            flushPendingSwipeMutations()
            flushSessionProgressSave()
            dataManager.photoLibraryManager.stopCachingImages(
                preloadedAssets,
                size: swipeImageTargetSize
            )
            preloadedAssets.removeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            // 处理内存警告
            dataManager.photoLibraryManager.handleMemoryWarning()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            flushSessionProgressSave()
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
            stopInlineVideoPlaybackIfNeeded(forNextIndex: currentPhotoIndex)
            scheduleSessionProgressSave()
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

                    Text(headerProgressSubtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

                Spacer()

                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        ReviewModeToggleButton(mode: reviewMode, action: toggleReviewMode)
                        PendingDeleteCounter(count: pendingDeleteCount)
                    }

                    if showReviewModeHint {
                        ReviewModeHintBubble(action: toggleReviewMode)
                            .offset(y: 43)
                            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
                            .zIndex(1)
                    }
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
                        subtitle: L10n.string("请允许访问您的照片库来开始整理照片"),
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
                        title: L10n.string("正在读取照片"),
                        message: L10n.string("读取完成后会直接进入当前整理。"),
                        progress: activeLibraryLoadingProgress
                    )
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                } else if shouldShowBackgroundLoadingState {
                    PhotoSelectionLoadingCard(
                        title: L10n.string("正在读取当前相册"),
                        message: L10n.string("照片很多时可能需要几秒，完成后会自动开始。"),
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
                isBeingFiledToAlbum: isAssetBeingFiledToAlbum(asset),
                isFiledToAlbum: isAssetFiledToAlbum(asset),
                isVideoPlaying: inlinePlayingVideoAssetID == asset.localIdentifier,
                displaySize: cardSize,
                targetSize: imageTargetSize(for: cardSize),
                onStopVideoPlayback: stopInlineVideoPlayback
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
            .photoDeleteSimultaneousTapGesture(enabled: inlinePlayingVideoAssetID != asset.localIdentifier) {
                openAssetPreview(asset)
            }
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
        let selectedTargetSize = browserSelectedImageTargetSize(in: containerSize, tileHeight: tileHeight)

        return VStack(spacing: 12) {
            browserStatusStrip

            TwoRowPhotoBrowserView(
                assets: sessionPhotos,
                photoLibraryManager: dataManager.photoLibraryManager,
                currentIndex: currentPhotoIndex,
                reviewedAssetIDs: dataManager.reviewedAssetIDs,
                pendingReviewedAssetIDs: browserPendingReviewedAssetIDs,
                deleteCandidateIDs: browserDeleteCandidateIDs,
                favoriteCandidateIDs: browserFavoriteCandidateIDs,
                albumFilingAssetIDs: albumFilingAssetIDs,
                albumFiledAssetIDs: recentlyFiledAlbumAssetIDs,
                playingVideoAssetID: inlinePlayingVideoAssetID,
                rowHeight: tileHeight,
                thumbnailTargetSize: thumbnailTargetSize,
                selectedTargetSize: selectedTargetSize,
                onSelectIndex: selectBrowserPhoto(at:),
                onOpenAsset: openAssetPreview(_:),
                onSwipeUpToDelete: handleBrowserSwipeUpDelete(_:at:),
                onCancelDelete: cancelDeleteCandidate(_:at:),
                onStopVideoPlayback: stopInlineVideoPlayback
            )
            .frame(height: tileHeight * 2 + 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
    }

    private func openAssetPreview(_ asset: PHAsset) {
        if asset.mediaType == .video {
            toggleInlineVideoPlayback(for: asset)
        } else {
            previewAsset = CandidatePreviewAsset(asset: asset)
        }
    }

    private func toggleInlineVideoPlayback(for asset: PHAsset) {
        let assetID = asset.localIdentifier
        if inlinePlayingVideoAssetID == assetID {
            inlinePlayingVideoAssetID = nil
        } else {
            inlinePlayingVideoAssetID = assetID
        }
    }

    private func stopInlineVideoPlayback() {
        inlinePlayingVideoAssetID = nil
    }

    private func stopInlineVideoPlaybackIfNeeded(forNextIndex index: Int) {
        guard let inlinePlayingVideoAssetID,
              isValidPhotoIndex(index),
              sessionPhotos[index].localIdentifier != inlinePlayingVideoAssetID else {
            return
        }
        self.inlinePlayingVideoAssetID = nil
    }
    private var browserStatusStrip: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Label(L10n.string("左右浏览"), systemImage: "arrow.left.and.right")
                    .foregroundColor(PhotoDeleteStyle.accent)

                Label(L10n.string("上滑删除"), systemImage: "arrow.up")
                    .foregroundColor(PhotoDeleteStyle.destructive)

                Spacer(minLength: 8)

                Text("\(L10n.string("位置")) \(formattedCount(currentProgress))/\(formattedCount(totalPhotosCount))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            ProgressView(value: progressFraction)
                .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                .frame(height: 4)
                .clipShape(Capsule(style: .continuous))

            HStack(spacing: 10) {
                Text("\(L10n.string("已整理")) \(formattedCount(organizedProgress))/\(formattedCount(totalPhotosCount))")
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
            if shouldShowAlbumShortcutGuidance {
                AlbumShortcutHintBubble(onDismiss: acknowledgeAlbumShortcutHint)
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            albumShortcutStrip(horizontalPadding: PhotoDeleteStyle.screenHorizontalPadding)
            if showDeleteButtonTip && canPerformPhotoAction {
                ReviewTipBanner(
                    icon: "trash",
                    message: L10n.string("按底部“删除”可连续加入待删除"),
                    onDismiss: acknowledgeDeleteButtonTip
                )
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
            if shouldShowAlbumShortcutGuidance {
                AlbumShortcutHintBubble(onDismiss: acknowledgeAlbumShortcutHint)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            albumShortcutStrip(horizontalPadding: 0)
            if showDeleteButtonTip && canPerformPhotoAction {
                ReviewTipBanner(
                    icon: "trash",
                    message: L10n.string("按“待删除”可连续加入待删除"),
                    onDismiss: acknowledgeDeleteButtonTip
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

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
                        title: L10n.string("完成"),
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
            let usesTwoRows = albumShortcutUsesTwoRows

            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    Group {
                        if usesTwoRows {
                            VStack(alignment: .leading, spacing: 7) {
                                albumShortcutRow(albums: rows.top)
                                albumShortcutRow(albums: rows.bottom)
                            }
                        } else {
                            albumShortcutRow(albums: rows.top)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.05),
                            .init(color: .black, location: 0.94),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                AlbumShortcutManageButton(action: openAlbumsTab)
            }
            .padding(.horizontal, horizontalPadding)
            .frame(height: usesTwoRows ? 67 : 34)
            .onAppear {
                revealAlbumShortcutHintIfNeeded()
            }
            .onDisappear {
                dismissAlbumShortcutHint()
            }
        }
    }

    private var shouldShowAlbumShortcutGuidance: Bool {
        showAlbumShortcutHint &&
            !isAlbumMode &&
            canPerformPhotoAction &&
            !dataManager.userAlbums.isEmpty
    }

    private func albumShortcutRow(albums: [AlbumInfo]) -> some View {
        HStack(spacing: 7) {
            albumShortcutRowContent(albums: albums)
        }
    }

    @ViewBuilder
    private func albumShortcutRowContent(albums: [AlbumInfo]) -> some View {
        ForEach(albums) { albumInfo in
            AlbumMicroButton(title: albumInfo.title) {
                handleAddToAlbum(albumInfo)
            }
        }
    }

    private var albumShortcutUsesTwoRows: Bool {
        dataManager.userAlbums.count > albumShortcutTwoRowThreshold
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

        return L10n.string("\(getDisplayTitle()) · 已整理 \(formattedCount(organizedProgress))/\(formattedCount(totalPhotosCount))")
    }

    private var headerProgressSubtitle: String {
        guard totalPhotosCount > 0 else {
            return L10n.shortPhotoCount(0)
        }

        return "\(L10n.string("已整理")) \(formattedCount(organizedProgress))/\(formattedCount(totalPhotosCount))"
    }

    private func formattedCount(_ count: Int) -> String {
        Self.countFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private var portraitToastBottomPadding: CGFloat {
        var padding: CGFloat = 100
        if !isAlbumMode && canPerformPhotoAction && !dataManager.userAlbums.isEmpty {
            padding = albumShortcutUsesTwoRows ? 160 : 128
        }
        if shouldShowAlbumShortcutGuidance {
            padding += 70
        }
        if showDeleteButtonTip && canPerformPhotoAction {
            padding += 70
        }
        return padding
    }

    private var albumShortcutRows: (top: [AlbumInfo], bottom: [AlbumInfo]) {
        guard albumShortcutUsesTwoRows else {
            return (dataManager.userAlbums, [])
        }

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
        if let inlinePlayingVideoAssetID,
           !photos.contains(where: { $0.localIdentifier == inlinePlayingVideoAssetID }) {
            self.inlinePlayingVideoAssetID = nil
        }
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
        let maxSize = PhotoDeleteAdaptiveLayout.reviewPhotoCardMaxSize(
            in: containerSize,
            horizontalSizeClass: horizontalSizeClass
        )
        let width = min(availableWidth, maxSize.width)
        let height = min(availableHeight, maxSize.height)
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

    private func browserThumbnailTargetSize(in containerSize: CGSize, tileHeight: CGFloat) -> CGSize {
        let scale = min(displayScale, 1.3)
        let maxTileWidth = min(containerSize.width * 0.72, tileHeight * 1.72)
        return CGSize(
            width: min(maxTileWidth * scale, 420),
            height: min(tileHeight * scale, 360)
        )
    }

    private func browserSelectedImageTargetSize(in containerSize: CGSize, tileHeight: CGFloat) -> CGSize {
        let scale = min(displayScale, 1.85)
        let maxTileWidth = min(containerSize.width * 0.72, tileHeight * 1.72)
        return CGSize(
            width: min(maxTileWidth * scale, 820),
            height: min(tileHeight * scale, 820)
        )
    }

    private func selectBrowserPhoto(at index: Int) {
        guard isValidPhotoIndex(index) else { return }
        stopInlineVideoPlaybackIfNeeded(forNextIndex: index)
        currentPhotoIndex = index
        preloadUpcomingImages(from: index)
    }

    private func handleBrowserSwipeUpDelete(_ asset: PHAsset, at index: Int) {
        guard canPerformPhotoAction else { return }
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
        dismissReviewModeHint(markSeen: true)
        reviewModeValue = nextMode.rawValue
        resetCardPosition()
        preloadUpcomingImages(from: currentPhotoIndex)
        HapticManager.impact(.light)
        showFeedback(nextMode.switchAnnouncement, icon: nextMode.icon, style: .neutral, duration: 1.6)
    }

    private func recordReviewModeHintOpportunity() {
        guard reviewMode == .card,
              !hasSeenReviewModeHint,
              !showReviewModeHint,
              sessionPhotos.count >= reviewModeHintThreshold + 1 else {
            return
        }

        cardModeReviewActionCount += 1
        guard cardModeReviewActionCount >= reviewModeHintThreshold else { return }

        hasSeenReviewModeHint = true
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showReviewModeHint = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            dismissReviewModeHint()
        }
    }

    private func dismissReviewModeHint(markSeen: Bool = false) {
        if markSeen {
            hasSeenReviewModeHint = true
        }

        guard showReviewModeHint else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            showReviewModeHint = false
        }
    }

    private func recordDeleteButtonTipOpportunity() {
        guard !hasSeenDeleteButtonTip,
              !showDeleteButtonTip,
              !isAlbumMode,
              sessionPhotos.count >= deleteButtonTipThreshold + 1 else {
            return
        }

        sessionDeleteActionCount += 1
        guard sessionDeleteActionCount >= deleteButtonTipThreshold else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showDeleteButtonTip = true
        }
    }

    private func acknowledgeDeleteButtonTip() {
        hasSeenDeleteButtonTip = true
        guard showDeleteButtonTip else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            showDeleteButtonTip = false
        }
    }

    private func revealAlbumShortcutHintIfNeeded() {
        guard !hasSeenAlbumShortcutHint,
              !showAlbumShortcutHint,
              !isAlbumMode,
              canPerformPhotoAction,
              !dataManager.userAlbums.isEmpty else {
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            showAlbumShortcutHint = true
        }
    }

    private func acknowledgeAlbumShortcutHint() {
        dismissAlbumShortcutHint(markSeen: true)
    }

    private func dismissAlbumShortcutHint(markSeen: Bool = false) {
        if markSeen {
            hasSeenAlbumShortcutHint = true
        }
        guard showAlbumShortcutHint else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            showAlbumShortcutHint = false
        }
    }

    private func openAlbumsTab() {
        HapticManager.impact(.light)
        dismissAlbumShortcutHint(markSeen: true)
        NotificationCenter.default.post(name: AppConstants.openAlbumsTabNotificationName, object: nil)
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

        guard canPerformPhotoAction,
              let asset = currentRealPhoto,
              isValidPhotoIndex(currentPhotoIndex) else {
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

        stopInlineVideoPlayback()
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

    private func scheduleSessionProgressSave() {
        sessionProgressSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            persistSessionProgressIfPossible()
            sessionProgressSaveWorkItem = nil
        }
        sessionProgressSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: workItem)
    }

    private func flushSessionProgressSave() {
        sessionProgressSaveWorkItem?.cancel()
        sessionProgressSaveWorkItem = nil
        persistSessionProgressIfPossible()
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

    private var browserPendingReviewedAssetIDs: Set<String> {
        Set(pendingSwipeMutations.values.map { $0.asset.localIdentifier })
    }

    private var browserDeleteCandidateIDs: Set<String> {
        var ids = Set(dataManager.deleteCandidates.map(\.localIdentifier))
        for mutation in pendingSwipeMutations.values {
            let id = mutation.asset.localIdentifier
            switch mutation.action {
            case .delete:
                ids.insert(id)
            case .favorite, .keep:
                ids.remove(id)
            }
        }
        return ids
    }

    private var browserFavoriteCandidateIDs: Set<String> {
        var ids = Set(dataManager.favoriteCandidates.map(\.localIdentifier))
        for mutation in pendingSwipeMutations.values {
            let id = mutation.asset.localIdentifier
            switch mutation.action {
            case .favorite:
                ids.insert(id)
            case .delete, .keep:
                ids.remove(id)
            }
        }
        return ids
    }

    private func isAssetQueuedForDelete(_ asset: PHAsset) -> Bool {
        pendingSwipeMutations[asset.localIdentifier]?.action == .delete ||
            dataManager.isInDeleteCandidates(asset)
    }

    private func isAssetQueuedForFavorite(_ asset: PHAsset) -> Bool {
        pendingSwipeMutations[asset.localIdentifier]?.action == .favorite ||
            dataManager.isInFavoriteCandidates(asset)
    }

    private func isAssetBeingFiledToAlbum(_ asset: PHAsset) -> Bool {
        albumFilingAssetIDs.contains(asset.localIdentifier)
    }

    private func isAssetFiledToAlbum(_ asset: PHAsset) -> Bool {
        recentlyFiledAlbumAssetIDs.contains(asset.localIdentifier)
    }

    private func isAssetLocallyReviewed(_ asset: PHAsset) -> Bool {
        pendingSwipeMutations[asset.localIdentifier] != nil ||
            dataManager.isReviewed(asset) ||
            dataManager.isInDeleteCandidates(asset) ||
            dataManager.isInFavoriteCandidates(asset)
    }

    private func handleFavoriteAction() {
        guard canPerformPhotoAction, let asset = currentRealPhoto else { return }
        markFavoriteCandidate(asset)
        moveToNextPhoto()
    }

    private func handleDeleteAction() {
        guard canPerformPhotoAction, let asset = currentRealPhoto else { return }
        if isAssetQueuedForDelete(asset) {
            cancelDeleteCandidate(asset, at: currentPhotoIndex)
            return
        }

        markDeleteCandidate(asset)
        moveToNextPhoto()
    }

    private func handleSkipAction() {
        guard canPerformPhotoAction, let asset = currentRealPhoto else { return }
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
        recordDeleteButtonTipOpportunity()
        recordReviewModeHintOpportunity()
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
        recordReviewModeHintOpportunity()
    }

    private func markSkip(_ asset: PHAsset, message: String? = nil) {
        let originalIndex = currentPhotoIndex
        let wasReviewed = dataManager.isReviewed(asset)
        recordSessionReviewedChange(wasReviewed: wasReviewed)
        scheduleSwipeMutation(asset, action: .keep)
        actionHistory.append(.skip(asset, originalIndex: originalIndex, wasReviewed: wasReviewed))
        HapticManager.impact(.light)
        showFeedback(message ?? L10n.string("已跳过"), icon: "arrow.right", style: .neutral)
        recordReviewModeHintOpportunity()
    }

    private func handleAddToAlbum(_ albumInfo: AlbumInfo) {
        dismissAlbumShortcutHint(markSeen: true)

        guard !showCompletionMessage,
              let asset = currentRealPhoto,
              let assetCollection = albumInfo.assetCollection else {
            showFeedback(L10n.string("无法归类到这个相册"), icon: "exclamationmark.triangle", style: .warning)
            return
        }

        let assetID = asset.localIdentifier
        guard !albumFilingAssetIDs.contains(assetID) else { return }

        albumFilingAssetIDs.insert(assetID)
        recentlyFiledAlbumAssetIDs.remove(assetID)

        let wasReviewed = dataManager.markReviewed(asset)
        recordSessionReviewedChange(wasReviewed: wasReviewed)
        HapticManager.impact(.light)
        showFeedback(L10n.string("正在归类到 \(albumInfo.title)"), icon: "tray.and.arrow.down", style: .neutral, duration: 1.0)
        dataManager.addPhotoToAlbum(asset, album: assetCollection) { success in
            DispatchQueue.main.async {
                self.albumFilingAssetIDs.remove(assetID)
                if success {
                    self.recentlyFiledAlbumAssetIDs.insert(assetID)
                    HapticManager.notify(.success)
                    self.showFeedback(L10n.string("已归类到 \(albumInfo.title)"), icon: "checkmark.circle.fill", style: .positive)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        self.recentlyFiledAlbumAssetIDs.remove(assetID)
                        if self.currentRealPhoto?.localIdentifier == assetID {
                            self.moveToNextPhoto()
                        }
                    }
                } else {
                    self.recentlyFiledAlbumAssetIDs.remove(assetID)
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

private struct SwipePhotoCardFrame: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let isInDeleteCandidates: Bool
    let isInFavoriteCandidates: Bool
    let isBeingFiledToAlbum: Bool
    let isFiledToAlbum: Bool
    let isVideoPlaying: Bool
    let displaySize: CGSize
    let targetSize: CGSize
    let onStopVideoPlayback: () -> Void

    var body: some View {
        RealPhotoCard(
            asset: asset,
            photoLibraryManager: photoLibraryManager,
            isInDeleteCandidates: isInDeleteCandidates,
            isInFavoriteCandidates: isInFavoriteCandidates,
            isBeingFiledToAlbum: isBeingFiledToAlbum,
            isFiledToAlbum: isFiledToAlbum,
            isVideoPlaying: isVideoPlaying,
            displaySize: displaySize,
            targetSize: targetSize,
            onStopVideoPlayback: onStopVideoPlayback
        )
    }
}

private struct InlineVideoCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.string("关闭"), systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.58)))
                .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .photoDeleteMinimumTapTarget()
        .accessibilityLabel(L10n.string("关闭"))
    }
}

private extension View {
    @ViewBuilder
    func photoDeleteTapGesture(enabled: Bool, action: @escaping () -> Void) -> some View {
        if enabled {
            self.onTapGesture(perform: action)
        } else {
            self
        }
    }

    @ViewBuilder
    func photoDeleteSimultaneousTapGesture(enabled: Bool, action: @escaping () -> Void) -> some View {
        if enabled {
            self.simultaneousGesture(TapGesture().onEnded { action() })
        } else {
            self
        }
    }

    @ViewBuilder
    func inlineVideoCloseAccessibility(isActive: Bool, action: @escaping () -> Void) -> some View {
        if isActive {
            self.accessibilityAction(named: Text(L10n.string("关闭"))) {
                action()
            }
        } else {
            self
        }
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
            return String(
                format: L10n.string("%lld 年第 %lld 周"),
                Int64(components.yearForWeekOfYear ?? 0),
                Int64(components.weekOfYear ?? 0)
            )
        case .month:
            return monthTitle.string(from: date)
        case .year:
            return yearTitle.string(from: date)
        }
    }

    static var dayTitle: DateFormatter {
        AppDateFormatter.configuredFormatter(template: "MMMEd")
    }

    private static var monthTitle: DateFormatter {
        AppDateFormatter.configuredFormatter(template: "yMMM")
    }

    private static var yearTitle: DateFormatter {
        AppDateFormatter.configuredFormatter(template: "y")
    }
}

// MARK: - 真实照片卡片
struct RealPhotoCard: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let isInDeleteCandidates: Bool
    let isInFavoriteCandidates: Bool
    let isBeingFiledToAlbum: Bool
    let isFiledToAlbum: Bool
    let isVideoPlaying: Bool
    let displaySize: CGSize
    let targetSize: CGSize
    let onStopVideoPlayback: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var thumbnailRequestID: PHImageRequestID?
    @State private var previewRequestID: PHImageRequestID?
    @State private var fallbackRequestID: PHImageRequestID?
    @State private var loadingAssetIdentifier: String?
    @State private var isShowingDegradedPreview = false
    @State private var isDownloadingFromCloud = false
    @State private var cloudDownloadProgress: Double?

    var body: some View {
        ZStack {
            if isVideoPlaying {
                PhotoAssetVideoPlayerView(
                    asset: asset,
                    photoLibraryManager: photoLibraryManager
                )
                .frame(width: displaySize.width, height: displaySize.height)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    InlineVideoCloseButton(action: onStopVideoPlayback)
                        .padding(12),
                    alignment: .topLeading
                )
                .overlay(
                    candidateOverlay,
                    alignment: .center
                )
            } else if let image = image {
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
                    .overlay(
                        previewStatusOverlay,
                        alignment: .bottom
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
                        VStack(spacing: 10) {
                            if isLoading || isDownloadingFromCloud {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                                    .scaleEffect(1.2)
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                            }

                            if isDownloadingFromCloud {
                                Text(L10n.string("正在从 iCloud 下载照片"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(PhotoDeleteStyle.secondaryText)
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
        .inlineVideoCloseAccessibility(isActive: isVideoPlaying, action: onStopVideoPlayback)
        .onAppear {
            loadImage()
        }
        .onDisappear {
            photoLibraryManager.cancelImageRequest(thumbnailRequestID)
            photoLibraryManager.cancelImageRequest(previewRequestID)
            photoLibraryManager.cancelImageRequest(fallbackRequestID)
            loadingAssetIdentifier = nil
            resetPreviewLoadingState()
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
        if isInDeleteCandidates || isInFavoriteCandidates || isBeingFiledToAlbum || isFiledToAlbum {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PhotoDeleteStyle.background.opacity(0.72))

                VStack(spacing: 12) {
                    Image(systemName: candidateOverlayIcon)
                        .font(.system(size: 38, weight: .medium))
                        .foregroundColor(candidateOverlayTint)

                    Text(candidateOverlayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            .cornerRadius(20)
        }
    }

    private var candidateOverlayIcon: String {
        if isInDeleteCandidates { return "trash.fill" }
        if isInFavoriteCandidates { return "heart.fill" }
        if isBeingFiledToAlbum { return "tray.and.arrow.down.fill" }
        return "checkmark.circle.fill"
    }

    private var candidateOverlayTint: Color {
        if isInDeleteCandidates { return PhotoDeleteStyle.destructive }
        if isInFavoriteCandidates { return PhotoDeleteStyle.iconTint(for: "favorite") }
        return PhotoDeleteStyle.positive
    }

    private var candidateOverlayTitle: String {
        if isInDeleteCandidates { return L10n.string("待删除") }
        if isInFavoriteCandidates { return L10n.string("待收藏") }
        if isBeingFiledToAlbum { return L10n.string("归类中") }
        return L10n.string("已归类")
    }

    @ViewBuilder
    private var previewStatusOverlay: some View {
        if !isInDeleteCandidates,
           !isInFavoriteCandidates,
           !isBeingFiledToAlbum,
           !isFiledToAlbum,
           isShowingDegradedPreview || isDownloadingFromCloud {
            HStack(spacing: 8) {
                if let cloudDownloadProgress {
                    ProgressView(value: cloudDownloadProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                        .frame(width: 48)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                        .scaleEffect(0.72)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(isDownloadingFromCloud ? L10n.string("正在从 iCloud 下载照片") : L10n.string("正在加载高清预览"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(L10n.string("当前可能较模糊"))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(PhotoDeleteStyle.primaryText.opacity(0.08), lineWidth: 1)
            )
            .padding(.bottom, 14)
            .accessibilityElement(children: .combine)
        }
    }

    private func loadImage() {
        photoLibraryManager.cancelImageRequest(thumbnailRequestID)
        photoLibraryManager.cancelImageRequest(previewRequestID)
        photoLibraryManager.cancelImageRequest(fallbackRequestID)
        isLoading = true
        image = nil
        fallbackRequestID = nil
        resetPreviewLoadingState()
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
                self.isShowingDegradedPreview = self.previewRequestID != nil
            }
            self.thumbnailRequestID = nil
        }

        previewRequestID = photoLibraryManager.loadSwipePreviewResult(for: asset, size: targetSize) { result in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            if result.isInCloud || result.progress != nil {
                self.isDownloadingFromCloud = true
                self.cloudDownloadProgress = result.progress
            }

            if result.isDegraded {
                self.isShowingDegradedPreview = true
            }

            if let loadedImage = result.image {
                self.image = loadedImage
                self.isLoading = false
            }

            if result.isFinal {
                self.isDownloadingFromCloud = false
                self.cloudDownloadProgress = nil
                self.isShowingDegradedPreview = false
                if result.image == nil, self.image == nil {
                    self.loadFallbackImage(for: requestedAssetID)
                }
                self.previewRequestID = nil
            } else if result.image != nil {
                self.isShowingDegradedPreview = true
            } else if result.isInCloud, self.image == nil {
                self.isLoading = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            guard loadingAssetIdentifier == requestedAssetID, image == nil else { return }
            loadFallbackImage(for: requestedAssetID)
        }
    }

    private func resetPreviewLoadingState() {
        isShowingDegradedPreview = false
        isDownloadingFromCloud = false
        cloudDownloadProgress = nil
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if asset.mediaType == .video {
            values.append(L10n.string("视频"))
            if isVideoPlaying {
                values.append(L10n.string("视频预览"))
            }
        } else {
            values.append(L10n.string("照片"))
        }

        if photoLibraryManager.isScreenshot(asset) {
            values.append(L10n.string("截图"))
        }

        if asset.isFavorite || isInFavoriteCandidates {
            values.append(L10n.string("收藏"))
        }

        if isDownloadingFromCloud {
            values.append(L10n.string("正在从 iCloud 下载照片"))
        } else if isShowingDegradedPreview {
            values.append(L10n.string("正在加载高清预览"))
        }

        if isInDeleteCandidates {
            values.append(L10n.string("待删除"))
        } else if isInFavoriteCandidates {
            values.append(L10n.string("待收藏"))
        } else if isBeingFiledToAlbum {
            values.append(L10n.string("归类中"))
        } else if isFiledToAlbum {
            values.append(L10n.string("已归类"))
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
            self.resetPreviewLoadingState()
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
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(message)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .photoDeleteCard()
    }
}

private struct ReviewTipBanner: View {
    let icon: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .frame(width: 22, height: 22)

            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.88)

            Spacer(minLength: 6)

            Button(action: onDismiss) {
                Text(L10n.string("知道了"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PhotoDeleteStyle.surface.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(PhotoDeleteStyle.hairline.opacity(0.64), lineWidth: 1)
                )
        )
        .shadow(color: PhotoDeleteStyle.floatingShadow.opacity(0.72), radius: 7, x: 0, y: 3)
    }
}

private struct AlbumShortcutHintBubble: View {
    let onDismiss: () -> Void

    var body: some View {
        ReviewTipBanner(
            icon: "tray.and.arrow.down",
            message: L10n.string("点击归类到相册"),
            onDismiss: onDismiss
        )
    }
}

private struct AlbumShortcutManageButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .frame(width: 34, height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(PhotoDeleteStyle.accent.opacity(0.12))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(PhotoDeleteStyle.accent.opacity(0.24), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PhotoDeletePressScaleButtonStyle())
        .accessibilityLabel(L10n.string("管理相册"))
        .accessibilityHint(L10n.string("打开相册页管理相册"))
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
        .contentShape(Capsule(style: .continuous))
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

private struct ReviewModeHintBubble: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(L10n.string("试试双行布局"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            } icon: {
                Image(systemName: "rectangle.grid.2x2")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(PhotoDeleteStyle.primaryText)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(PhotoDeleteStyle.accent.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: PhotoDeleteStyle.floatingShadow.opacity(0.7), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.string("切换到双行浏览"))
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

#Preview {
    SwipePhotoView(selectedCategory: PhotoCategory.all, selectedTimeGroup: nil, selectedAlbumInfo: nil)
        .environmentObject(DataManager())
}
