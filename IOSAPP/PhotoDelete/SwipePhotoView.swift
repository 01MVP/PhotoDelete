//
//  SwipePhotoView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import SwiftUI
import AVKit
import Photos
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct SwipePhotoView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppConstants.leftSwipeActionKey) private var leftSwipeActionValue = SwipeGesturePreset.standard.leftAction.rawValue
    @AppStorage(AppConstants.rightSwipeActionKey) private var rightSwipeActionValue = SwipeGesturePreset.standard.rightAction.rawValue
    @AppStorage(AppConstants.upSwipeActionKey) private var upSwipeActionValue = SwipeGesturePreset.standard.upAction.rawValue
    @AppStorage(AppConstants.reviewMediaAutoPlayKey) private var reviewMediaAutoPlay = true
    @AppStorage(AppConstants.reviewVideoMutedKey) private var defaultReviewVideoMuted = true
    @AppStorage(AppConstants.reviewModeKey) private var reviewModeValue = PhotoReviewMode.card.rawValue
    @AppStorage(AppConstants.hasSeenReviewModeHintKey) private var hasSeenReviewModeHint = false
    @AppStorage(AppConstants.hasSeenAlbumShortcutHintKey) private var hasSeenAlbumShortcutHint = false
    @AppStorage(AppConstants.hasSeenDeleteButtonTipKey) private var hasSeenDeleteButtonTip = false
    @AppStorage(AppConstants.gestureUpdateNoticePendingKey) private var gestureUpdateNoticePending = false

    let selectedCategory: PhotoCategory?
    let selectedTimeGroup: String?
    let selectedAlbumInfo: AlbumInfo?
    let selectedDate: Date?
    let selectedAdvancedTimeScope: AdvancedTimeScope?
    let selectedAdvancedCleanup: AdvancedCleanupKind?
    let selectedLocationGroupID: String?
    let randomReviewScope: PhotoRandomReviewScope?
    let selectedHistoricalToday: Bool

    @State private var dragOffset = CGSize.zero
    @State private var showBatchConfirm = false
    @State private var showReviewSettings = false
    @State private var currentPhotoIndex = 0
    @State private var showCompletionMessage = false
    @State private var actionHistory: [SwipeAction] = []
    @State private var sessionPhotos: [PHAsset] = []
    @State private var allSessionPhotos: [PHAsset] = []
    @State private var loadedSessionPhotoCount = 0
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
    @State private var manuallyStoppedVideoAssetID: String?
    @State private var cardModeReviewActionCount = 0
    @State private var showReviewModeHint = false
    @State private var showAlbumShortcutHint = false
    @State private var showDeleteButtonTip = false
    @State private var sessionDeleteActionCount = 0
    @State private var albumFilingAssetIDs: Set<String> = []
    @State private var recentlyFiledAlbumAssetIDs: Set<String> = []
    @State private var currentAlbumInfo: AlbumInfo?
    @State private var sessionVideoMuted = true
    @State private var didApplySessionPlaybackPreference = false
    @State private var cardTransitionDirection = CardBrowseTransitionDirection.none
    @State private var hasPreparedSwipeCommit = false

    private let reviewModeHintThreshold = 5
    private let deleteButtonTipThreshold = 3
    private let albumShortcutTwoRowThreshold = 4
    private enum SwipeMotion {
        static let minimumDragDistance: CGFloat = 4
        static let previewStartDistance: CGFloat = 14
        static let directionLockDistance: CGFloat = 12
        static let commitDistance: CGFloat = 92
        static let predictedCommitDistance: CGFloat = 148
        static let minimumPredictedCommitDrag: CGFloat = 38
        static let browseClamp: CGFloat = 120
        static let closeClamp: CGFloat = 112
        static let actionDragLimit: CGFloat = 210
        static let actionDragResistance: CGFloat = 0.34
        static let maxCardTiltDegrees: CGFloat = 4
    }
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
        selectedAdvancedCleanup: AdvancedCleanupKind? = nil,
        selectedLocationGroupID: String? = nil,
        randomReviewScope: PhotoRandomReviewScope? = nil,
        selectedHistoricalToday: Bool = false
    ) {
        self.selectedCategory = selectedCategory
        self.selectedTimeGroup = selectedTimeGroup
        self.selectedAlbumInfo = selectedAlbumInfo
        self.selectedDate = selectedDate
        self.selectedAdvancedTimeScope = selectedAdvancedTimeScope
        self.selectedAdvancedCleanup = selectedAdvancedCleanup
        self.selectedLocationGroupID = selectedLocationGroupID
        self.randomReviewScope = randomReviewScope
        self.selectedHistoricalToday = selectedHistoricalToday
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

    private enum CardBrowseTransitionDirection: Equatable {
        case none
        case previous
        case next
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

        if let randomReviewScope {
            return dataManager.makeRandomReviewPhotos(
                for: randomReviewScope,
                scopeID: sessionProgressScopeID
            )
        } else if selectedHistoricalToday {
            return dataManager.getPhotosForHistoricalToday()
        } else if let albumInfo = activeAlbumInfo {
            return dataManager.getPhotosForAlbum(albumInfo)
        } else if let selectedDate, let selectedAdvancedTimeScope {
            return dataManager.getPhotosForPeriod(selectedAdvancedTimeScope, containing: selectedDate)
        } else if let selectedDate {
            return dataManager.getPhotosForDay(selectedDate)
        } else if let selectedAdvancedCleanup {
            return dataManager.getPhotosForAdvancedCleanup(selectedAdvancedCleanup)
        } else if let selectedLocationGroupID {
            return dataManager.getPhotosForLocationGroup(selectedLocationGroupID)
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
        return allSessionPhotos.isEmpty ? sessionPhotos.count : allSessionPhotos.count
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

    private var shouldPageSessionPhotos: Bool {
        selectedAdvancedCleanup == nil
    }

    private var activeAlbumInfo: AlbumInfo? {
        currentAlbumInfo ?? selectedAlbumInfo
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

    private var reviewVideoMuted: Bool {
        didApplySessionPlaybackPreference ? sessionVideoMuted : defaultReviewVideoMuted
    }

    private var shouldShowSessionMuteButton: Bool {
        guard let asset = currentRealPhoto else { return false }
        return asset.mediaType == .video || dataManager.photoLibraryManager.isLivePhoto(asset)
    }

    private var navigationHeaderSideWidth: CGFloat {
        116
    }

    private func shouldPlayVideo(for asset: PHAsset) -> Bool {
        guard asset.mediaType == .video else { return false }
        if inlinePlayingVideoAssetID == asset.localIdentifier {
            return true
        }
        if manuallyStoppedVideoAssetID == asset.localIdentifier {
            return false
        }
        return reviewMediaAutoPlay &&
            !isAssetQueuedForDelete(asset) &&
            !isAssetQueuedForFavorite(asset) &&
            !isAssetBeingFiledToAlbum(asset) &&
            !isAssetFiledToAlbum(asset)
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
                photoLibraryManager: dataManager.photoLibraryManager,
                locationTitle: dataManager.locationDisplayTextIfAvailable(for: previewAsset.asset)
            )
        }
        .sheet(isPresented: $showReviewSettings) {
            GestureSettingsView()
        }
        .fullScreenCover(isPresented: $showBatchConfirm, onDismiss: {
            didInitializeSession = false
            syncPendingOperationCounts()
            initializeSessionIfNeeded()
        }) {
            BatchConfirmView(albumInfo: activeAlbumInfo) { _ in
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
            applySessionPlaybackPreferenceIfNeeded()
            syncPendingOperationCounts()
            if selectedLocationGroupID != nil {
                dataManager.loadLocationGroups()
            }
            if refreshSelectedAlbumState() {
                initializeSessionIfNeeded()
            }
        }
        .onChange(of: albumStateRefreshToken) { _ in
            refreshSelectedAlbumState()
        }
        .onChange(of: dataManager.photoLibraryManager.isLoading) { _ in
            initializeSessionIfNeeded()
        }
        .onChange(of: dataManager.isPreparingLibrary) { _ in
            initializeSessionIfNeeded()
        }
        .onChange(of: dataManager.photoLibraryManager.allPhotos.count) { _ in
            refreshSessionForSourceChangeIfNeeded()
        }
        .onChange(of: dataManager.advancedCleanupQueuesRevision) { _ in
            guard selectedAdvancedCleanup != nil else { return }
            refreshSessionForSourceChangeIfNeeded(force: true)
        }
        .onChange(of: dataManager.locationGroupsRevision) { _ in
            guard selectedLocationGroupID != nil else { return }
            refreshSessionForSourceChangeIfNeeded(force: true)
        }
        .onChange(of: currentPhotoIndex) { _ in
            stopInlineVideoPlaybackIfNeeded(forNextIndex: currentPhotoIndex)
            manuallyStoppedVideoAssetID = nil
            expandLoadedSessionPhotosIfNeeded(for: currentPhotoIndex)
            scheduleSessionProgressSave()
        }
        .onChange(of: defaultReviewVideoMuted) { muted in
            sessionVideoMuted = muted
            didApplySessionPlaybackPreference = true
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
                .frame(width: navigationHeaderSideWidth, alignment: .leading)

                Spacer()

                VStack(spacing: 2) {
                    Text(navigationHeaderTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

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
                .frame(width: navigationHeaderSideWidth, alignment: .trailing)
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
            let placeholderBottomReserve: CGFloat = geometry.size.width > geometry.size.height ? 0 : 88

            Group {
                if !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                    centeredPhotoAreaPlaceholder(in: geometry, bottomReserve: placeholderBottomReserve) {
                        PhotoAuthorizationCard(
                            subtitle: L10n.string("请允许访问您的照片库来开始整理照片"),
                            onRequestAccess: { dataManager.requestPhotoLibraryAccess() }
                        )
                        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    }
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

                        if shouldShowGestureUpdateNotice && !showCompletionMessage {
                            VStack {
                                GestureUpdateNoticeBanner(
                                    onAdjust: openGestureSettingsFromNotice,
                                    onDismiss: acknowledgeGestureUpdateNotice
                                )
                                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                                .padding(.top, 14)
                                .transition(.move(edge: .top).combined(with: .opacity))

                                Spacer(minLength: 0)
                            }
                            .zIndex(2)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if shouldShowInitialPreparingState {
                    centeredPhotoAreaPlaceholder(in: geometry, bottomReserve: placeholderBottomReserve) {
                        PhotoSelectionLoadingCard(
                            title: L10n.string("正在读取照片"),
                            message: L10n.string("读取完成后会直接进入当前整理。"),
                            progress: activeLibraryLoadingProgress
                        )
                        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    }
                } else if shouldShowBackgroundLoadingState {
                    centeredPhotoAreaPlaceholder(in: geometry, bottomReserve: placeholderBottomReserve) {
                        PhotoSelectionLoadingCard(
                            title: L10n.string("正在读取当前相册"),
                            message: L10n.string("照片很多时可能需要几秒，完成后会自动开始。"),
                            progress: activeLibraryLoadingProgress
                        )
                        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    }
                } else {
                    centeredPhotoAreaPlaceholder(in: geometry, bottomReserve: placeholderBottomReserve) {
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
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func centeredPhotoAreaPlaceholder<Content: View>(
        in geometry: GeometryProxy,
        bottomReserve: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let resolvedBottomReserve = min(bottomReserve, geometry.size.height * 0.2)

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(0, geometry.size.height - resolvedBottomReserve), alignment: .center)
        .padding(.bottom, resolvedBottomReserve)
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
                isVideoPlaying: shouldPlayVideo(for: asset),
                allowsLivePhotoPlayback: reviewMediaAutoPlay,
                videoMuted: reviewVideoMuted,
                memoryCaption: memoryCaption(for: asset),
                metadataSummary: metadataSummary(for: asset),
                displaySize: cardSize,
                targetSize: imageTargetSize(for: cardSize),
                onStopVideoPlayback: {
                    stopInlineVideoPlayback(rememberManualStopFor: asset)
                }
            )
            .id(asset.localIdentifier)
            .transition(cardBrowseTransition)
            .overlay {
                if let feedback = dragFeedback(for: dragOffset) {
                    PhotoSwipeDragFeedbackView(feedback: feedback)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if shouldShowSessionMuteButton {
                    SessionMuteToggleButton(isMuted: reviewVideoMuted, action: toggleSessionVideoMuted)
                        .padding(12)
                        .transition(.opacity)
                }
            }
            .rotationEffect(cardRotationAngle(for: dragOffset, in: cardSize), anchor: .bottom)
            .offset(dragOffset)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .highPriorityGesture(createDragGesture())
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
        }
    }

    private var cardBrowseTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        switch cardTransitionDirection {
        case .previous:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .next:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .none:
            return .identity
        }
    }

    private func memoryCaption(for asset: PHAsset) -> PhotoMemoryCaption {
        PhotoMemoryCaption(
            title: PhotoMemoryCaptionFormatter.relativeTitle(for: asset.creationDate),
            subtitle: PhotoMemoryCaptionFormatter.dateSubtitle(for: asset.creationDate)
        )
    }

    private func metadataSummary(for asset: PHAsset) -> PhotoAssetMetadataSummary {
        PhotoAssetMetadataSummary(
            captureDateText: PhotoAssetMetadataFormatter.shortCaptureDate(for: asset.creationDate),
            locationText: dataManager.locationDisplayTextIfAvailable(for: asset)
        )
    }

    private func dragFeedback(for translation: CGSize) -> PhotoSwipeDragFeedbackState? {
        let previewStart = SwipeMotion.previewStartDistance
        let commitDistance = SwipeMotion.commitDistance
        guard let direction = dominantSwipeDirection(for: translation, threshold: previewStart) else {
            return nil
        }

        let distance: CGFloat
        switch direction {
        case .left, .right:
            distance = abs(translation.width)
        case .up, .down:
            distance = abs(translation.height)
        }

        let progress = min(max((distance - previewStart) / (commitDistance - previewStart), 0), 1)
        guard progress > 0 else { return nil }

        let action = configuredAction(for: direction)
        return PhotoSwipeDragFeedbackState(
            direction: direction,
            action: action,
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
                onStopVideoPlayback: {
                    stopInlineVideoPlayback()
                }
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
            manuallyStoppedVideoAssetID = assetID
        } else {
            manuallyStoppedVideoAssetID = nil
            inlinePlayingVideoAssetID = assetID
        }
    }

    private func stopInlineVideoPlayback(rememberManualStopFor asset: PHAsset? = nil) {
        if let asset, asset.mediaType == .video {
            manuallyStoppedVideoAssetID = asset.localIdentifier
        }
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

                Text(completionTitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(completionSubtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .multilineTextAlignment(.center)

                if randomReviewScope != nil {
                    HStack(spacing: 10) {
                        CompletionStatPill(
                            icon: "trash",
                            value: sessionActionCount(for: .delete),
                            title: L10n.string("删除"),
                            tint: PhotoDeleteStyle.destructive
                        )
                        CompletionStatPill(
                            icon: "heart",
                            value: sessionActionCount(for: .favorite),
                            title: L10n.string("收藏"),
                            tint: PhotoDeleteStyle.iconTint(for: "favorite")
                        )
                        CompletionStatPill(
                            icon: "checkmark",
                            value: sessionActionCount(for: .keep),
                            title: L10n.string("保留"),
                            tint: PhotoDeleteStyle.positive
                        )
                    }
                }

                HStack(spacing: 12) {
                    if hasUnreviewedPhotos {
                        Button(L10n.string("继续整理")) {
                            continueToNextUnreviewedPhoto()
                            showCompletionMessage = false
                        }
                        .photoDeleteSecondaryButton()
                    }

                    Button(completionPrimaryActionTitle) {
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

    private var completionTitle: String {
        L10n.string("整理完成！")
    }

    private var completionSubtitle: String {
        if randomReviewScope == nil {
            return L10n.string("您已经浏览完所有照片")
        }

        return String(
            format: L10n.string("已整理 %lld/%lld 张，确认后再统一删除。"),
            Int64(organizedProgress),
            Int64(totalPhotosCount)
        )
    }

    private var completionPrimaryActionTitle: String {
        if pendingDeleteCount > 0 || !dataManager.deleteCandidates.isEmpty {
            return L10n.string("确认删除")
        }
        if pendingFavoriteCount > 0 || !dataManager.favoriteCandidates.isEmpty {
            return L10n.string("确认收藏")
        }
        return L10n.string("完成整理")
    }

    private func sessionActionCount(for action: SwipeGestureAction) -> Int {
        actionHistory.reduce(0) { count, historyAction in
            switch (action, historyAction) {
            case (.delete, .delete):
                return count + 1
            case (.favorite, .favorite):
                return count + 1
            case (.keep, .skip):
                return count + 1
            default:
                return count
            }
        }
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
                    icon: "gearshape",
                    title: L10n.string("设置"),
                    color: PhotoDeleteStyle.accent
                ) {
                    openReviewSettings()
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
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(progressSubtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

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
                GestureGuideRow(
                    icon: "arrow.down",
                    title: L10n.string("下滑"),
                    detail: L10n.string("返回列表"),
                    color: PhotoDeleteStyle.accent
                )
            }
        }
        .padding(16)
        .photoDeleteCard()
    }

    @ViewBuilder
    private func albumShortcutStrip(horizontalPadding: CGFloat) -> some View {
        if !isAlbumMode && canPerformPhotoAction && !albumShortcutAlbums.isEmpty {
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
            !albumShortcutAlbums.isEmpty
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
        albumShortcutAlbums.count > albumShortcutTwoRowThreshold
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
            ActionButton(icon: "gearshape", title: "设置", color: PhotoDeleteStyle.accent) {
                openReviewSettings()
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

    private var shouldShowGestureUpdateNotice: Bool {
        gestureUpdateNoticePending &&
            currentRealPhoto != nil &&
            !showCompletionMessage
    }

    private var activeLibraryLoadingProgress: Double {
        min(max(dataManager.photoLibraryManager.loadingProgress, 0), 1)
    }

    private var progressSubtitle: String {
        guard totalPhotosCount > 0 else {
            return L10n.string("总体进度 0/0")
        }

        return String(
            format: L10n.string("总体进度 %@/%@ · 当前位置 %@/%@"),
            formattedCount(organizedProgress),
            formattedCount(totalPhotosCount),
            formattedCount(currentProgress),
            formattedCount(totalPhotosCount)
        )
    }

    private var navigationHeaderTitle: String {
        if randomReviewScope != nil,
           let asset = currentRealPhoto {
            let caption = memoryCaption(for: asset)
            return [caption.title, caption.subtitle]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        return getDisplayTitle()
    }

    private var headerProgressSubtitle: String {
        guard totalPhotosCount > 0 else {
            return L10n.string("总体进度 0/0")
        }

        return String(
            format: L10n.string("总体进度 %@/%@"),
            formattedCount(organizedProgress),
            formattedCount(totalPhotosCount)
        )
    }

    private func formattedCount(_ count: Int) -> String {
        Self.countFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private var portraitToastBottomPadding: CGFloat {
        var padding: CGFloat = 100
        if !isAlbumMode && canPerformPhotoAction && !albumShortcutAlbums.isEmpty {
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
        let albums = albumShortcutAlbums
        guard albumShortcutUsesTwoRows else {
            return (albums, [])
        }

        var top: [AlbumInfo] = []
        var bottom: [AlbumInfo] = []
        for (index, album) in albums.enumerated() {
            if index.isMultiple(of: 2) {
                top.append(album)
            } else {
                bottom.append(album)
            }
        }
        return (top, bottom)
    }

    private var albumShortcutAlbums: [AlbumInfo] {
        dataManager.getUserAlbumsSortedByCustomOrder()
    }

    private var hasUnreviewedPhotos: Bool {
        sessionReviewedCount < totalPhotosCount
    }

    private var albumStateRefreshToken: [String] {
        guard isAlbumMode else { return [] }
        return dataManager.userAlbums.map { album in
            "\(album.id)|\(album.title)|\(album.photosCount)|\(album.thumbnailAsset?.localIdentifier ?? "")"
        }
    }

    @discardableResult
    private func refreshSelectedAlbumState(showMissingToast: Bool = true) -> Bool {
        guard let selectedAlbumInfo else { return true }

        guard let latestAlbumInfo = dataManager.currentUserAlbumInfo(for: selectedAlbumInfo) else {
            currentAlbumInfo = nil
            if showMissingToast {
                showFeedback(L10n.string("这个相册已不存在，列表已更新"), icon: "arrow.clockwise", style: .warning)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            }
            return false
        }

        let previousAlbumInfo = activeAlbumInfo
        currentAlbumInfo = latestAlbumInfo

        guard didInitializeSession,
              previousAlbumInfo?.id == latestAlbumInfo.id,
              previousAlbumInfo?.title != latestAlbumInfo.title ||
              previousAlbumInfo?.photosCount != latestAlbumInfo.photosCount ||
              previousAlbumInfo?.thumbnailAsset?.localIdentifier != latestAlbumInfo.thumbnailAsset?.localIdentifier else {
            return true
        }

        refreshSessionPhotos(dataManager.getPhotosForAlbum(latestAlbumInfo))
        return true
    }

    private func initializeSessionIfNeeded() {
        guard !didInitializeSession else { return }

        let photos = filteredRealPhotos
        if photos.isEmpty && isWaitingForSourceData {
            return
        }

        refreshSessionPhotos(photos)
        didInitializeSession = true
    }

    private var isWaitingForSourceData: Bool {
        dataManager.photoLibraryManager.isLoading ||
            dataManager.isPreparingLibrary ||
            (selectedLocationGroupID != nil && (dataManager.isLoadingLocationGroups || dataManager.isResolvingLocationTitles)) ||
            dataManager.isLoadingAdvancedCleanupQueues
    }

    private func refreshSessionForSourceChangeIfNeeded(force: Bool = false) {
        guard didInitializeSession else {
            if refreshSelectedAlbumState() {
                initializeSessionIfNeeded()
            }
            return
        }

        let photos = filteredRealPhotos
        if photos.isEmpty, isWaitingForSourceData, !allSessionPhotos.isEmpty {
            return
        }

        let currentIDs = allSessionPhotos.map(\.localIdentifier)
        let nextIDs = photos.map(\.localIdentifier)
        guard force || currentIDs != nextIDs || (allSessionPhotos.isEmpty && !photos.isEmpty) else {
            return
        }

        let currentID = currentRealPhoto?.localIdentifier
        refreshSessionPhotos(photos)
        if let currentID,
           let updatedIndex = sessionPhotos.firstIndex(where: { $0.localIdentifier == currentID }) {
            currentPhotoIndex = updatedIndex
        }
    }

    private func refreshSessionPhotos(_ photos: [PHAsset]? = nil) {
        let fullPhotos = photos ?? filteredRealPhotos
        allSessionPhotos = fullPhotos
        if let inlinePlayingVideoAssetID,
           !fullPhotos.contains(where: { $0.localIdentifier == inlinePlayingVideoAssetID }) {
            self.inlinePlayingVideoAssetID = nil
        }

        sessionReviewedCount = dataManager.reviewedCount(in: fullPhotos)
        let firstUnreviewedIndex = fullPhotos.firstIndex(where: { !dataManager.isReviewed($0) })
        let targetIndex: Int
        if didInitializeSession {
            targetIndex = min(currentPhotoIndex, max(fullPhotos.count - 1, 0))
        } else {
            targetIndex = PhotoReviewSessionPaginator.initialTargetIndex(
                assetIdentifiers: fullPhotos.map(\.localIdentifier),
                reviewedAssetIdentifiers: dataManager.reviewedAssetIDs,
                savedAssetIdentifier: restoredSessionProgressAssetID,
                prefersFirstUnreviewedBeforeSavedProgress: shouldPreferFirstUnreviewedBeforeSavedProgress
            )
        }
        showCompletionMessage = !fullPhotos.isEmpty && firstUnreviewedIndex == nil

        let loadedCount = loadedSessionCount(totalCount: fullPhotos.count, targetIndex: targetIndex)
        loadedSessionPhotoCount = loadedCount
        sessionPhotos = Array(fullPhotos.prefix(loadedCount))
        currentPhotoIndex = min(targetIndex, max(sessionPhotos.count - 1, 0))
        preloadUpcomingImages(from: currentPhotoIndex)
        persistSessionProgressIfPossible()
    }

    private func loadedSessionCount(totalCount: Int, targetIndex: Int) -> Int {
        guard shouldPageSessionPhotos else { return totalCount }

        let initialCount = PhotoReviewSessionPaginator.initialLoadedCount(totalCount: totalCount)
        guard targetIndex >= initialCount else { return initialCount }
        return min(totalCount, targetIndex + 1)
    }

    @discardableResult
    private func expandLoadedSessionPhotosIfNeeded(for index: Int, force: Bool = false) -> Bool {
        guard shouldPageSessionPhotos,
              loadedSessionPhotoCount < allSessionPhotos.count else {
            return false
        }

        let newLoadedCount: Int
        if force {
            newLoadedCount = min(
                allSessionPhotos.count,
                loadedSessionPhotoCount + PhotoReviewSessionPaginator.defaultPageSize
            )
        } else {
            newLoadedCount = PhotoReviewSessionPaginator.expandedLoadedCount(
                totalCount: allSessionPhotos.count,
                currentLoadedCount: loadedSessionPhotoCount,
                currentIndex: index
            )
        }

        guard newLoadedCount > loadedSessionPhotoCount else { return false }
        loadedSessionPhotoCount = newLoadedCount
        sessionPhotos = Array(allSessionPhotos.prefix(newLoadedCount))
        return true
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
              !albumShortcutAlbums.isEmpty else {
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

    private func openReviewSettings() {
        HapticManager.impact(.light)
        dismissAlbumShortcutHint(markSeen: true)
        dismissReviewModeHint(markSeen: true)
        showReviewSettings = true
    }

    private func applySessionPlaybackPreferenceIfNeeded() {
        guard !didApplySessionPlaybackPreference else { return }
        sessionVideoMuted = defaultReviewVideoMuted
        didApplySessionPlaybackPreference = true
    }

    private func toggleSessionVideoMuted() {
        sessionVideoMuted.toggle()
        didApplySessionPlaybackPreference = true
        HapticManager.impact(.light)
        showFeedback(
            sessionVideoMuted ? L10n.string("已静音") : L10n.string("已打开声音"),
            icon: sessionVideoMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            style: .neutral,
            duration: 1.1
        )
    }

    private func createDragGesture() -> some Gesture {
        DragGesture(minimumDistance: SwipeMotion.minimumDragDistance)
            .onChanged { value in
                dragOffset = visualDragOffset(for: value.translation)
                updateSwipeCommitFeedback(for: value.translation)
            }
            .onEnded { value in
                handleSwipeGesture(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                )
            }
    }

    private func visualDragOffset(for translation: CGSize) -> CGSize {
        guard let direction = dominantSwipeDirection(for: translation, threshold: SwipeMotion.directionLockDistance) else {
            return translation
        }

        let action = configuredAction(for: direction)
        switch action {
        case .previous, .next:
            return CGSize(
                width: min(max(translation.width, -SwipeMotion.browseClamp), SwipeMotion.browseClamp),
                height: 0
            )
        case .close:
            return CGSize(width: 0, height: min(max(translation.height, -SwipeMotion.closeClamp), SwipeMotion.closeClamp))
        case .delete, .keep, .favorite:
            switch direction {
            case .left, .right:
                return CGSize(
                    width: rubberBanded(
                        translation.width,
                        limit: SwipeMotion.actionDragLimit,
                        resistance: SwipeMotion.actionDragResistance
                    ),
                    height: translation.height * 0.35
                )
            case .up, .down:
                return CGSize(
                    width: translation.width * 0.22,
                    height: rubberBanded(
                        translation.height,
                        limit: SwipeMotion.actionDragLimit,
                        resistance: SwipeMotion.actionDragResistance
                    )
                )
            }
        }
    }

    private func cardRotationAngle(for offset: CGSize, in cardSize: CGSize) -> Angle {
        guard !reduceMotion else { return .degrees(0) }
        let width = max(cardSize.width, 1)
        let normalized = max(min(offset.width / width, 1), -1)
        return .degrees(Double(normalized * SwipeMotion.maxCardTiltDegrees))
    }

    private func rubberBanded(_ value: CGFloat, limit: CGFloat, resistance: CGFloat) -> CGFloat {
        let distance = abs(value)
        guard distance > limit else { return value }
        let sign: CGFloat = value < 0 ? -1 : 1
        return sign * (limit + (distance - limit) * resistance)
    }

    private func updateSwipeCommitFeedback(for translation: CGSize) {
        let isPastCommitDistance = dominantSwipeDirection(for: translation, threshold: SwipeMotion.commitDistance) != nil
        if isPastCommitDistance && !hasPreparedSwipeCommit {
            hasPreparedSwipeCommit = true
            HapticManager.impact(.light)
        } else if !isPastCommitDistance {
            hasPreparedSwipeCommit = false
        }
    }

    private func handleSwipeGesture(translation: CGSize, predictedEndTranslation: CGSize) {
        // 如果显示完成消息，允许滑动操作
        if showCompletionMessage {
            if abs(translation.width) > SwipeMotion.commitDistance {
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

        if let direction = committedSwipeDirection(
            translation: translation,
            predictedEndTranslation: predictedEndTranslation
        ) {
            let action = configuredAction(for: direction)
            completeCommittedSwipe(action: action, asset: asset)
            return
        }

        resetCardPosition()
    }

    private func committedSwipeDirection(translation: CGSize, predictedEndTranslation: CGSize) -> SwipeDirection? {
        if let direction = dominantSwipeDirection(for: translation, threshold: SwipeMotion.commitDistance) {
            return direction
        }

        guard let predictedDirection = dominantSwipeDirection(
            for: predictedEndTranslation,
            threshold: SwipeMotion.predictedCommitDistance
        ) else {
            return nil
        }

        guard primaryDistance(for: predictedDirection, in: translation) >= SwipeMotion.minimumPredictedCommitDrag else {
            return nil
        }

        return predictedDirection
    }

    private func primaryDistance(for direction: SwipeDirection, in translation: CGSize) -> CGFloat {
        switch direction {
        case .left, .right:
            return abs(translation.width)
        case .up, .down:
            return abs(translation.height)
        }
    }

    private func completeCommittedSwipe(action: SwipeGestureAction, asset: PHAsset) {
        hasPreparedSwipeCommit = false
        clearDragOffsetWithoutAnimation()
        performConfiguredSwipeAction(action, asset: asset)
    }

    private func clearDragOffsetWithoutAnimation() {
        hasPreparedSwipeCommit = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragOffset = .zero
        }
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
            return .close
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

    private func performConfiguredSwipeAction(_ action: SwipeGestureAction, asset: PHAsset) {
        switch action {
        case .previous:
            browseToPreviousPhoto(reviewing: asset)
        case .next:
            browseToNextPhoto(reviewing: asset)
        case .close:
            handleFinishAction()
        case .delete:
            markDeleteCandidate(asset)
            moveToNextPhoto()
        case .keep:
            markSkip(asset)
            moveToNextPhoto()
        case .favorite:
            markFavoriteCandidate(asset)
            moveToNextPhoto()
        }
    }

    private func browseToPreviousPhoto(reviewing asset: PHAsset) {
        if randomReviewScope != nil {
            browseToPreviousRandomReviewPhoto(reviewing: asset)
            return
        }

        guard currentPhotoIndex > 0 else {
            showFeedback(L10n.string("已经是第一张"), icon: "chevron.left", style: .neutral, duration: 1.2)
            return
        }

        markBrowsedAsKept(asset)
        stopInlineVideoPlayback()
        let previousIndex = currentPhotoIndex - 1
        setCurrentPhotoIndex(previousIndex, transition: .previous)
        preloadUpcomingImages(from: previousIndex)
        persistSessionProgressIfPossible()
        HapticManager.impact(.light)
    }

    private func browseToNextPhoto(reviewing asset: PHAsset) {
        guard !sessionPhotos.isEmpty else { return }

        if randomReviewScope != nil {
            browseToNextRandomReviewPhoto(reviewing: asset)
            return
        }

        let nextIndex = currentPhotoIndex + 1
        while nextIndex >= sessionPhotos.count,
              expandLoadedSessionPhotosIfNeeded(for: sessionPhotos.count, force: true) { }

        guard isValidPhotoIndex(nextIndex) else {
            markBrowsedAsKept(asset)
            showCompletionMessage = true
            persistSessionProgressIfPossible()
            HapticManager.impact(.light)
            return
        }

        markBrowsedAsKept(asset)
        stopInlineVideoPlayback()
        setCurrentPhotoIndex(nextIndex, transition: .next)
        preloadUpcomingImages(from: nextIndex)
        persistSessionProgressIfPossible()
        HapticManager.impact(.light)
    }

    private func browseToPreviousRandomReviewPhoto(reviewing asset: PHAsset) {
        guard !sessionPhotos.isEmpty else { return }

        markBrowsedAsKept(asset)
        stopInlineVideoPlayback()
        let targetIndex = currentPhotoIndex > 0 ? currentPhotoIndex - 1 : sessionPhotos.count - 1
        setCurrentPhotoIndex(targetIndex, transition: .previous)
        preloadUpcomingImages(from: targetIndex)
        persistSessionProgressIfPossible()
        HapticManager.impact(.light)
    }

    private func browseToNextRandomReviewPhoto(reviewing asset: PHAsset) {
        guard !sessionPhotos.isEmpty else { return }

        markBrowsedAsKept(asset)
        stopInlineVideoPlayback()
        let nextIndex = currentPhotoIndex + 1
        let targetIndex = nextIndex < sessionPhotos.count ? nextIndex : 0
        setCurrentPhotoIndex(targetIndex, transition: .next)
        preloadUpcomingImages(from: targetIndex)
        persistSessionProgressIfPossible()
        HapticManager.impact(.light)
    }

    private func setCurrentPhotoIndex(_ index: Int, transition: CardBrowseTransitionDirection) {
        guard isValidPhotoIndex(index), index != currentPhotoIndex else { return }
        cardTransitionDirection = transition
        withAnimation(.easeOut(duration: 0.18)) {
            currentPhotoIndex = index
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard cardTransitionDirection == transition else { return }
            cardTransitionDirection = .none
        }
    }

    private func moveToNextPhoto() {
        guard !sessionPhotos.isEmpty else { return }

        stopInlineVideoPlayback()
        let nextSearchStart = currentPhotoIndex + 1
        var newIndex = firstLocallyUnreviewedPhotoIndex(startingAt: nextSearchStart) ?? nextSearchStart
        while newIndex >= sessionPhotos.count,
              expandLoadedSessionPhotosIfNeeded(for: sessionPhotos.count, force: true) {
            newIndex = firstLocallyUnreviewedPhotoIndex(startingAt: nextSearchStart) ?? nextSearchStart
        }

        if newIndex < sessionPhotos.count {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentPhotoIndex = newIndex
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
        var nextIndex = firstLocallyUnreviewedPhotoIndex(startingAt: 0)
        while nextIndex == nil,
              expandLoadedSessionPhotosIfNeeded(for: sessionPhotos.count, force: true) {
            nextIndex = firstLocallyUnreviewedPhotoIndex(startingAt: 0)
        }

        guard let nextIndex else {
            return
        }
        currentPhotoIndex = nextIndex
        preloadUpcomingImages(from: nextIndex)
    }

    private func firstLocallyUnreviewedPhotoIndex(startingAt startIndex: Int) -> Int? {
        guard startIndex < sessionPhotos.count else { return nil }
        return sessionPhotos[startIndex...].firstIndex { !isAssetLocallyReviewed($0) }
    }

    private var restoredSessionProgressAssetID: String? {
        persistedProgressMap()[sessionProgressScopeID]
    }

    private var shouldPreferFirstUnreviewedBeforeSavedProgress: Bool {
        selectedCategory == .all && randomReviewScope == nil
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
        if let randomReviewScope {
            return "random:\(randomReviewScope.rawValue)"
        }

        if let albumInfo = selectedAlbumInfo {
            return "album:\(albumInfo.id)"
        }

        if let selectedDate, let selectedAdvancedTimeScope {
            let intervalStart = Calendar.current.dateInterval(for: selectedAdvancedTimeScope, containing: selectedDate).start
            return "period:\(selectedAdvancedTimeScope.rawValue):\(Int(intervalStart.timeIntervalSince1970))"
        }

        if selectedHistoricalToday {
            let today = Calendar.current.startOfDay(for: Date())
            return "historicalToday:\(Int(today.timeIntervalSince1970))"
        }

        if let selectedDate {
            let dayStart = Calendar.current.startOfDay(for: selectedDate)
            return "day:\(Int(dayStart.timeIntervalSince1970))"
        }

        if let selectedAdvancedCleanup {
            return "advanced:\(selectedAdvancedCleanup.rawValue)"
        }

        if let selectedLocationGroupID {
            return "location:\(selectedLocationGroupID)"
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
            case .favorite, .keep, .previous, .next, .close:
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
            case .delete, .keep, .previous, .next, .close:
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
        recordSessionReviewedChange(wasReviewed: isAssetLocallyReviewed(asset))
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
        recordSessionReviewedChange(wasReviewed: isAssetLocallyReviewed(asset))
        updateLocalPendingCountsForFavorite(asset)
        scheduleSwipeMutation(asset, action: .favorite)
        actionHistory.append(.favorite(asset, originalIndex: originalIndex, wasReviewed: wasReviewed))
        HapticManager.impact(.light)
        showFeedback(L10n.string("已加入待收藏"), icon: "heart.fill", style: .favorite, showsUndo: true)
        recordReviewModeHintOpportunity()
    }

    private func markBrowsedAsKept(_ asset: PHAsset) {
        guard !isAssetLocallyReviewed(asset) else {
            recordReviewModeHintOpportunity()
            return
        }

        let originalIndex = currentPhotoIndex
        let wasReviewed = dataManager.isReviewed(asset)
        recordSessionReviewedChange(wasReviewed: false)
        scheduleSwipeMutation(asset, action: .keep)
        actionHistory.append(.skip(asset, originalIndex: originalIndex, wasReviewed: wasReviewed))
        recordReviewModeHintOpportunity()
    }

    private func markSkip(_ asset: PHAsset, message: String? = nil) {
        let originalIndex = currentPhotoIndex
        let wasReviewed = dataManager.isReviewed(asset)
        recordSessionReviewedChange(wasReviewed: isAssetLocallyReviewed(asset))
        scheduleSwipeMutation(asset, action: .keep)
        actionHistory.append(.skip(asset, originalIndex: originalIndex, wasReviewed: wasReviewed))
        HapticManager.impact(.light)
        showFeedback(message ?? L10n.string("已保留"), icon: "checkmark", style: .neutral)
        recordReviewModeHintOpportunity()
    }

    private func handleAddToAlbum(_ albumInfo: AlbumInfo) {
        dismissAlbumShortcutHint(markSeen: true)

        guard !showCompletionMessage,
              let asset = currentRealPhoto else {
            showFeedback(L10n.string("无法归类到这个相册"), icon: "exclamationmark.triangle", style: .warning)
            return
        }
        guard let currentAlbumInfo = dataManager.currentUserAlbumInfo(for: albumInfo) else {
            showFeedback(L10n.string("这个相册已不存在，列表已更新"), icon: "arrow.clockwise", style: .warning)
            return
        }
        guard let assetCollection = currentAlbumInfo.assetCollection else {
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
        showFeedback(L10n.string("正在归类到 \(currentAlbumInfo.title)"), icon: "tray.and.arrow.down", style: .neutral, duration: 1.0)
        dataManager.addPhotoToAlbum(asset, album: assetCollection) { success in
            DispatchQueue.main.async {
                self.albumFilingAssetIDs.remove(assetID)
                if success {
                    self.recentlyFiledAlbumAssetIDs.insert(assetID)
                    HapticManager.notify(.success)
                    self.showFeedback(L10n.string("已归类到 \(currentAlbumInfo.title)"), icon: "checkmark.circle.fill", style: .positive)
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
                    if self.dataManager.currentUserAlbumInfo(for: currentAlbumInfo) == nil {
                        self.showFeedback(L10n.string("这个相册已不存在，列表已更新"), icon: "arrow.clockwise", style: .warning)
                    } else {
                        self.showFeedback(L10n.string("归类失败，请再试一次"), icon: "exclamationmark.triangle", style: .warning)
                    }
                }
            }
        }

        resetCardPosition()
    }

    private func resetCardPosition() {
        hasPreparedSwipeCommit = false
        let resetAnimation: Animation = reduceMotion
            ? .easeOut(duration: 0.12)
            : .interactiveSpring(response: 0.32, dampingFraction: 0.82)
        withAnimation(resetAnimation) {
            dragOffset = .zero
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
        case .keep, .previous, .next, .close:
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

    private func getDisplayTitle() -> String {
        if let randomReviewScope {
            return randomReviewScope.title
        } else if selectedHistoricalToday {
            return L10n.string("历史上的今天")
        } else if let albumInfo = activeAlbumInfo {
            return albumInfo.title
        } else if let selectedDate, let selectedAdvancedTimeScope {
            return AdvancedSwipeDateFormatter.title(for: selectedAdvancedTimeScope, containing: selectedDate)
        } else if let selectedDate {
            return AdvancedSwipeDateFormatter.dayTitle.string(from: selectedDate)
        } else if let selectedAdvancedCleanup {
            return selectedAdvancedCleanup.title
        } else if let selectedLocationGroupID {
            return dataManager.locationGroupTitle(for: selectedLocationGroupID) ?? L10n.string("地点")
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

    private func acknowledgeGestureUpdateNotice() {
        gestureUpdateNoticePending = false
    }

    private func openGestureSettingsFromNotice() {
        gestureUpdateNoticePending = false
        openReviewSettings()
    }
}

private struct CompletionStatPill: View {
    let icon: String
    let value: Int
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text("\(value)")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundColor(tint)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
        )
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
    let allowsLivePhotoPlayback: Bool
    let videoMuted: Bool
    let memoryCaption: PhotoMemoryCaption
    let metadataSummary: PhotoAssetMetadataSummary
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
            allowsLivePhotoPlayback: allowsLivePhotoPlayback,
            videoMuted: videoMuted,
            memoryCaption: memoryCaption,
            metadataSummary: metadataSummary,
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
            Label(L10n.string("停止播放"), systemImage: "stop.fill")
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.76)))
                .overlay(Circle().stroke(Color.white.opacity(0.34), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .photoDeleteMinimumTapTarget()
        .accessibilityLabel(L10n.string("停止播放"))
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
            self.accessibilityAction(named: Text(L10n.string("停止播放"))) {
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
            hint
        }
        .opacity(0.7 + feedback.progress * 0.3)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var feedbackGlow: some View {
        switch feedback.direction {
        case .left:
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                LinearGradient(
                    colors: glowColors.reversed(),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: glowWidth)
            }
        case .right:
            HStack(spacing: 0) {
                LinearGradient(
                    colors: glowColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: glowWidth)

                Spacer(minLength: 0)
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
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                LinearGradient(
                    colors: glowColors.reversed(),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 72 + feedback.progress * 34)
            }
        }
    }

    @ViewBuilder
    private var hint: some View {
        switch feedback.direction {
        case .left:
            centeredHint(
                icon: SwipeGestureDirection.left.icon,
                title: "\(SwipeGestureDirection.left.title)\(feedback.action.title)",
                color: feedback.action.tint
            )
        case .right:
            centeredHint(
                icon: SwipeGestureDirection.right.icon,
                title: "\(SwipeGestureDirection.right.title)\(feedback.action.title)",
                color: feedback.action.tint
            )
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
            VStack {
                Spacer()
                SwipeEdgeHint(
                    icon: "arrow.down",
                    title: L10n.string("下滑返回列表"),
                    color: feedback.action.tint
                )
                .padding(.bottom, 16)
                .offset(y: 10 - feedback.progress * 10)
            }
        }
    }

    private func centeredHint(icon: String, title: String, color: Color) -> some View {
        SwipeEdgeHint(
            icon: icon,
            title: title,
            color: color
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .scaleEffect(0.94 + feedback.progress * 0.06)
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
                Spacer()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(feedback.action.tint)
                    .frame(width: 5 + feedback.progress * 5)
                    .padding(.vertical, 18)
                    .padding(.trailing, 7)
            }
        case .right:
            HStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(feedback.action.tint)
                    .frame(width: 5 + feedback.progress * 5)
                    .padding(.vertical, 18)
                    .padding(.leading, 7)
                Spacer()
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
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(feedback.action.tint)
                    .frame(height: 5 + feedback.progress * 5)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 7)
            }
        }
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
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if iconPlacement == .trailing {
                iconView
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.96))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1.2)
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 5)
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
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

private struct PhotoAssetQuickInfoOverlay: View {
    let summary: PhotoAssetMetadataSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            quickInfoRow(icon: "calendar", text: summary.captureDateText)
            if let locationText = summary.locationText {
                quickInfoRow(icon: "location", text: locationText)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }

    private func quickInfoRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 13)

            Text(text)
        }
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
    let allowsLivePhotoPlayback: Bool
    let videoMuted: Bool
    let memoryCaption: PhotoMemoryCaption
    let metadataSummary: PhotoAssetMetadataSummary
    let displaySize: CGSize
    let targetSize: CGSize
    let onStopVideoPlayback: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var thumbnailRequestID: PHImageRequestID?
    @State private var previewRequestID: PHImageRequestID?
    @State private var fallbackRequestID: PHImageRequestID?
    @State private var livePhotoRequestID: PHImageRequestID?
    @State private var livePhoto: PHLivePhoto?
    @State private var failedToLoadLivePhoto = false
    @State private var loadingAssetIdentifier: String?
    @State private var isShowingDegradedPreview = false
    @State private var isDownloadingFromCloud = false
    @State private var cloudDownloadProgress: Double?

    var body: some View {
        ZStack {
            if isVideoPlaying {
                PhotoAssetVideoPlayerView(
                    asset: asset,
                    photoLibraryManager: photoLibraryManager,
                    isMuted: videoMuted,
                    allowsPlayerInteraction: false
                )
                .allowsHitTesting(false)
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
            } else if shouldShowLivePhotoPlayback, let livePhoto {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.22))

                    LivePhotoPreviewRepresentable(
                        livePhoto: livePhoto,
                        autoPlay: allowsLivePhotoPlayback,
                        isMuted: videoMuted,
                        contentMode: .scaleAspectFit
                    )
                    .allowsHitTesting(false)
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
                    previewStatusOverlay,
                    alignment: .bottom
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
        .overlay(alignment: .bottomLeading) {
            if shouldShowMetadataOverlay {
                PhotoAssetQuickInfoOverlay(summary: metadataSummary)
                    .frame(maxWidth: displaySize.width - 24, alignment: .leading)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
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
            photoLibraryManager.cancelImageRequest(livePhotoRequestID)
            loadingAssetIdentifier = nil
            livePhoto = nil
            livePhotoRequestID = nil
            resetPreviewLoadingState()
        }
    }

    private var shouldShowLivePhotoPlayback: Bool {
        allowsLivePhotoPlayback &&
            photoLibraryManager.isLivePhoto(asset) &&
            !isInDeleteCandidates &&
            !isInFavoriteCandidates &&
            !isBeingFiledToAlbum &&
            !isFiledToAlbum
    }

    private var shouldShowMetadataOverlay: Bool {
        !isInDeleteCandidates &&
            !isInFavoriteCandidates &&
            !isBeingFiledToAlbum &&
            !isFiledToAlbum
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

            if photoLibraryManager.isLivePhoto(asset) {
                ZStack {
                    Circle()
                        .fill(PhotoDeleteStyle.background.opacity(0.62))
                        .frame(width: 30, height: 30)

                    Image(systemName: "livephoto")
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
        photoLibraryManager.cancelImageRequest(livePhotoRequestID)
        isLoading = true
        image = nil
        fallbackRequestID = nil
        livePhoto = nil
        livePhotoRequestID = nil
        failedToLoadLivePhoto = false
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

        if photoLibraryManager.isLivePhoto(asset) {
            loadLivePhoto(for: requestedAssetID)
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

        values.append(memoryCaption.title)
        if let subtitle = memoryCaption.subtitle {
            values.append(subtitle)
        }
        values.append(metadataSummary.captureDateText)
        if let locationText = metadataSummary.locationText {
            values.append(locationText)
        }

        if photoLibraryManager.isScreenshot(asset) {
            values.append(L10n.string("截图"))
        }

        if photoLibraryManager.isLivePhoto(asset) {
            values.append(L10n.string("实况照片"))
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

    private func loadLivePhoto(for requestedAssetID: String) {
        guard livePhotoRequestID == nil, !failedToLoadLivePhoto else { return }
        let livePhotoSize = CGSize(
            width: min(max(targetSize.width, displaySize.width * 2), 1_600),
            height: min(max(targetSize.height, displaySize.height * 2), 1_600)
        )

        livePhotoRequestID = photoLibraryManager.loadLivePhotoResult(
            for: asset,
            size: livePhotoSize
        ) { result in
            guard loadingAssetIdentifier == requestedAssetID else { return }

            if let loadedLivePhoto = result.livePhoto {
                livePhoto = loadedLivePhoto
                isLoading = false
            } else if result.isFinal, livePhoto == nil {
                failedToLoadLivePhoto = true
            }

            if result.isFinal {
                livePhotoRequestID = nil
            }
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
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil
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

            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
            }

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

private struct GestureUpdateNoticeBanner: View {
    let onAdjust: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ReviewTipBanner(
            icon: "hand.draw",
            message: L10n.string("手势已更新：左滑删除，右滑保留，上滑收藏。"),
            actionTitle: L10n.string("调整"),
            onAction: onAdjust,
            onDismiss: onDismiss
        )
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

private struct SessionMuteToggleButton: View {
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                isMuted ? L10n.string("打开声音") : L10n.string("静音"),
                systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
            )
            .labelStyle(.iconOnly)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(isMuted ? PhotoDeleteStyle.secondaryText : PhotoDeleteStyle.accent)
            .frame(width: 38, height: 38)
            .background(
                Circle()
                    .fill(PhotoDeleteStyle.surface)
                    .overlay(
                        Circle()
                            .stroke(
                                isMuted ? PhotoDeleteStyle.cardStroke : PhotoDeleteStyle.accent.opacity(0.28),
                                lineWidth: 1
                            )
                    )
            )
            .photoDeleteMinimumTapTarget()
        }
        .buttonStyle(PhotoDeletePressScaleButtonStyle())
        .accessibilityLabel(isMuted ? L10n.string("打开声音") : L10n.string("静音"))
        .accessibilityHint(L10n.string("只影响当前整理页面"))
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
