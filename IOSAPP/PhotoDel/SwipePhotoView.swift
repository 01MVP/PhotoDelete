//
//  SwipePhotoView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI
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

    let selectedCategory: PhotoCategory?
    let selectedTimeGroup: String?
    let selectedAlbumInfo: AlbumInfo?
    let selectedDate: Date?
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
    @State private var feedbackToast: PhotoDelToast?
    @State private var didInitializeSession = false
    @State private var preloadedAssets: [PHAsset] = []

    init(
        selectedCategory: PhotoCategory?,
        selectedTimeGroup: String?,
        selectedAlbumInfo: AlbumInfo?,
        selectedDate: Date? = nil,
        selectedAdvancedCleanup: AdvancedCleanupKind? = nil
    ) {
        self.selectedCategory = selectedCategory
        self.selectedTimeGroup = selectedTimeGroup
        self.selectedAlbumInfo = selectedAlbumInfo
        self.selectedDate = selectedDate
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
        return asset.isFavorite || dataManager.isInFavoriteCandidates(asset)
    }

    private var canPerformPhotoAction: Bool {
        currentRealPhoto != nil && !showCompletionMessage
    }

    var body: some View {
        ZStack {
            PhotoDelScreenBackground()

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
                        PhotoDelToastView(toast: feedbackToast) {
                            handleUndoAction()
                            resetCardPosition()
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, isLandscape ? 24 : 126)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showBatchConfirm, onDismiss: {
            didInitializeSession = false
        }) {
            BatchConfirmView(albumInfo: selectedAlbumInfo) {
                if shouldDismissAfterBatch {
                    dismiss()
                }
            }
                .environmentObject(dataManager)
        }
        .onDisappear {
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
        .onAppear {
            initializeSessionIfNeeded()
        }
        .onChange(of: dataManager.photoLibraryManager.isLoading) { _ in
            initializeSessionIfNeeded()
        }
        .onChange(of: dataManager.isPreparingLibrary) { _ in
            initializeSessionIfNeeded()
        }
    }

    // MARK: - 导航栏
    private var navigationHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: handleBackAction) {
                    ZStack {
                        Circle()
                            .fill(PhotoDelStyle.elevatedSurface)
                            .frame(width: 40, height: 40)

                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(PhotoDelStyle.primaryText)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 2) {
                    Text(sessionModeTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text(progressSubtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer()

                HStack(spacing: 7) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.destructive)
                    Text("\(dataManager.deleteCandidates.count)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)
                }
                .frame(minWidth: 40)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(PhotoDelStyle.surface)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                        )
                )
            }

            if totalPhotosCount > 0 {
                ProgressView(value: progressFraction)
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDelStyle.accent))
                    .frame(height: 4)
                    .clipShape(Capsule(style: .continuous))
                    .animation(.easeOut(duration: 0.22), value: organizedProgress)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(PhotoDelStyle.background.opacity(0.86))
        .overlay(
            Rectangle()
                .fill(PhotoDelStyle.hairline)
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
                    .padding(.horizontal, 24)
                } else if let realPhoto = currentRealPhoto {
                    // 真实照片显示
                    let cardSize = photoCardSize(in: geometry.size)
                    ZStack {
                        RealPhotoCard(
                            asset: realPhoto,
                            photoLibraryManager: dataManager.photoLibraryManager,
                            isInDeleteCandidates: dataManager.isInDeleteCandidates(realPhoto),
                            isInFavoriteCandidates: dataManager.isInFavoriteCandidates(realPhoto),
                            displaySize: cardSize,
                            targetSize: imageTargetSize(for: cardSize)
                        )
                        .id(realPhoto.localIdentifier)
                        .offset(dragOffset)
                        .rotationEffect(.degrees(rotationAngle))
                        .scaleEffect(1.0 - abs(dragOffset.width) / 1000)
                        .gesture(createDragGesture())
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        // 完成提示覆盖层
                        Group {
                            if showCompletionMessage {
                                ZStack {
                                    PhotoDelStyle.background.opacity(0.78)
                                        .ignoresSafeArea()

                                    VStack(spacing: 18) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 54, weight: .medium))
                                            .foregroundColor(PhotoDelStyle.positive)

                                        Text("整理完成！")
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundColor(PhotoDelStyle.primaryText)

                                        Text("您已经浏览完所有照片")
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(PhotoDelStyle.secondaryText)

                                        HStack(spacing: 12) {
                                            if hasUnreviewedPhotos {
                                                Button("继续整理") {
                                                    continueToNextUnreviewedPhoto()
                                                    showCompletionMessage = false
                                                }
                                                .photoDelSecondaryButton()
                                            }

                                            Button("完成整理") {
                                                handleFinishAction()
                                                showCompletionMessage = false
                                            }
                                            .photoDelPrimaryButton()
                                        }
                                    }
                                    .padding(24)
                                    .photoDelCard()
                                    .padding(.horizontal, 32)
                                }
                                .transition(.opacity)
                            }
                        }
                    )
                } else if shouldShowInitialPreparingState {
                    PhotoSelectionLoadingCard(
                        title: "正在读取照片",
                        message: "读取完成后会直接进入当前整理。",
                        progress: activeLibraryLoadingProgress
                    )
                    .padding(.horizontal, 24)
                } else if shouldShowBackgroundLoadingState {
                    PhotoSelectionLoadingCard(
                        title: "正在读取当前相册",
                        message: "照片很多时可能需要几秒，完成后会自动开始。",
                        progress: activeLibraryLoadingProgress
                    )
                    .padding(.horizontal, 24)
                } else {
                    // 没有更多照片
                    VStack(spacing: 20) {
                        if totalPhotosCount == 0 {
                            // 没有照片的情况
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 60, weight: .medium))
                                .foregroundColor(PhotoDelStyle.accent)

                            Text("这里还没有可整理的照片")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.primaryText)

                            Text("您可以返回选择其他分类，或稍后在系统照片中添加更多照片后再回来。")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            Button(action: { dismiss() }) {
                                Text("返回主页")
                                    .frame(maxWidth: 180)
                            }
                            .photoDelSecondaryButton()
                        } else {
                            // 整理完成的情况
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60, weight: .medium))
                                .foregroundColor(PhotoDelStyle.positive)

                            Text("整理完成！")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.primaryText)

                            Text("您已经整理完所有照片")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDelStyle.secondaryText)

                            Button(action: { dismiss() }) {
                                Text("返回主页")
                                    .frame(maxWidth: 180)
                            }
                            .photoDelSecondaryButton()
                        }
                    }
                    .padding(24)
                    .photoDelCard()
                    .padding(.horizontal, 24)
                }

                // 操作提示
                if currentRealPhoto != nil {
                    gestureHintStrip
                        .padding(.bottom, 20)
                }

                Spacer()
            }
        }
    }

    // MARK: - 底部控制区域
    private var bottomControls: some View {
        VStack(spacing: 14) {
            albumShortcutStrip(horizontalPadding: 24)
            actionToolbar
        }
        .padding(.top, 12)
        .padding(.bottom, 30)
        .background(
            PhotoDelStyle.background.opacity(0.92)
                .overlay(PhotoDelStyle.hairline.frame(height: 1), alignment: .top)
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
                    color: PhotoDelStyle.iconTint(for: "favorite")
                ) {
                    handleFavoriteAction()
                    resetCardPosition()
                }

                SidebarActionButton(
                    icon: "trash",
                    title: L10n.string("待删除"),
                    color: PhotoDelStyle.destructive
                ) {
                    handleDeleteAction()
                    resetCardPosition()
                }

                SidebarActionButton(
                    icon: "arrow.right",
                    title: L10n.string("跳过"),
                    color: PhotoDelStyle.accent
                ) {
                    handleSkipAction()
                    resetCardPosition()
                }

                HStack(spacing: 10) {
                    SidebarActionButton(
                        icon: "arrow.uturn.backward",
                        title: L10n.string("撤销"),
                        color: PhotoDelStyle.secondaryText,
                        isCompact: true
                    ) {
                        handleUndoAction()
                        resetCardPosition()
                    }

                    SidebarActionButton(
                        icon: "checkmark",
                        title: "完成",
                        color: PhotoDelStyle.positive,
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
            PhotoDelStyle.background.opacity(0.92)
                .overlay(PhotoDelStyle.hairline.frame(width: 1), alignment: .leading)
        )
    }

    private var sessionSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(getDisplayTitle())
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)
                .lineLimit(1)

            Text(progressSubtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(PhotoDelStyle.secondaryText)

            if totalPhotosCount > 0 {
                ProgressView(value: progressFraction)
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDelStyle.accent))
                    .clipShape(Capsule(style: .continuous))
            }

            HStack(spacing: 12) {
                Label("\(dataManager.deleteCandidates.count)", systemImage: "trash")
                    .foregroundColor(PhotoDelStyle.destructive)
                Label("\(dataManager.favoriteCandidates.count)", systemImage: "heart")
                    .foregroundColor(PhotoDelStyle.iconTint(for: "favorite"))
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .padding(16)
        .photoDelCard(radius: 16)
    }

    private var gestureGuidePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("手势")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDelStyle.tertiaryText)

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
        .padding(16)
        .photoDelCard(radius: 16)
    }

    @ViewBuilder
    private func albumShortcutStrip(horizontalPadding: CGFloat) -> some View {
        if !isAlbumMode && canPerformPhotoAction && !dataManager.userAlbums.isEmpty {
            let rows = [
                GridItem(.fixed(32), spacing: 8),
                GridItem(.fixed(32), spacing: 8)
            ]

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 8) {
                    ForEach(dataManager.userAlbums) { albumInfo in
                        Button(action: {
                            handleAddToAlbum(albumInfo)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(PhotoDelStyle.accent)

                                Text(albumInfo.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(PhotoDelStyle.primaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                            }
                            .padding(.horizontal, 11)
                            .frame(width: 118, height: 32)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(PhotoDelStyle.surface)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
            .frame(height: 76)
        }
    }

    private var actionToolbar: some View {
        HStack(spacing: 0) {
            Spacer()
            ActionButton(icon: "arrow.uturn.backward", title: "撤销", color: PhotoDelStyle.secondaryText) {
                handleUndoAction()
                resetCardPosition()
            }
            Spacer()
            ActionButton(icon: isCurrentPhotoFavorited ? "heart.fill" : "heart", title: "收藏", color: PhotoDelStyle.iconTint(for: "favorite")) {
                handleFavoriteAction()
                resetCardPosition()
            }
            Spacer()
            ActionButton(icon: "trash", title: "删除", color: PhotoDelStyle.destructive) {
                handleDeleteAction()
                resetCardPosition()
            }
            Spacer()
            ActionButton(icon: "arrow.right", title: "跳过", color: PhotoDelStyle.accent) {
                handleSkipAction()
                resetCardPosition()
            }
            Spacer()
            ActionButton(icon: "checkmark", title: "完成", color: PhotoDelStyle.positive) {
                handleFinishAction()
                resetCardPosition()
            }
            Spacer()
        }
        .padding(.horizontal, 24)
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

    private var hasUnreviewedPhotos: Bool {
        sessionReviewedCount < totalPhotosCount
    }

    private var gestureHintStrip: some View {
        HStack(spacing: 8) {
            ForEach(SwipeGestureDirection.allCases) { direction in
                let action = configuredAction(for: direction)
                GestureHintPill(
                    icon: direction.icon,
                    title: "\(direction.title)\(action.title)",
                    color: action.tint
                )
            }
        }
        .padding(.horizontal, 24)
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
        sessionReviewedCount = dataManager.reviewedCount(in: photos)
        if didInitializeSession {
            currentPhotoIndex = min(currentPhotoIndex, max(photos.count - 1, 0))
        } else if let firstUnreviewedIndex = photos.firstIndex(where: { !dataManager.isReviewed($0) }) {
            currentPhotoIndex = firstUnreviewedIndex
        } else {
            currentPhotoIndex = 0
            showCompletionMessage = !photos.isEmpty
        }
        preloadUpcomingImages(from: currentPhotoIndex)
    }

    private func preloadUpcomingImages(from index: Int) {
        guard index < sessionPhotos.count else { return }
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
        let height = min(availableHeight, 540)
        return CGSize(width: width, height: height)
    }

    private func imageTargetSize(for displaySize: CGSize) -> CGSize {
        let scale = displayScale
        return CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
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
                    showBatchConfirm = true
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
        let newIndex = sessionPhotos[nextSearchStart...]
            .firstIndex(where: { !dataManager.isReviewed($0) }) ?? nextSearchStart
        if newIndex < sessionPhotos.count {
            withAnimation(.easeOut(duration: 0.15)) {
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
        guard let nextIndex = sessionPhotos.firstIndex(where: { !dataManager.isReviewed($0) }) else {
            return
        }
        currentPhotoIndex = nextIndex
        preloadUpcomingImages(from: nextIndex)
    }

    private func isValidPhotoIndex(_ index: Int) -> Bool {
        return index >= 0 && index < sessionPhotos.count
    }

    private func handleFavoriteAction() {
        guard !showCompletionMessage, let asset = currentRealPhoto else { return }
        markFavoriteCandidate(asset)
        moveToNextPhoto()
    }

    private func handleDeleteAction() {
        guard !showCompletionMessage, let asset = currentRealPhoto else { return }
        markDeleteCandidate(asset)
        moveToNextPhoto()
    }

    private func handleSkipAction() {
        guard !showCompletionMessage, let asset = currentRealPhoto else { return }
        markSkip(asset)
        moveToNextPhoto()
    }

    private func handleFinishAction() {
        if hasPendingOperations {
            shouldDismissAfterBatch = true
            showBatchConfirm = true
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
            dataManager.removeFromDeleteCandidates(asset)
            dataManager.restoreReviewedState(asset, wasReviewed: wasReviewed)
            restoreSessionReviewedCount(wasReviewed: wasReviewed)
            restorePhotoPosition(asset, preferredIndex: originalIndex)
        case .favorite(let asset, let originalIndex, let wasReviewed):
            dataManager.removeFromFavoriteCandidates(asset)
            dataManager.restoreReviewedState(asset, wasReviewed: wasReviewed)
            restoreSessionReviewedCount(wasReviewed: wasReviewed)
            restorePhotoPosition(asset, preferredIndex: originalIndex)
        case .skip(let asset, let originalIndex, let wasReviewed):
            dataManager.restoreReviewedState(asset, wasReviewed: wasReviewed)
            restoreSessionReviewedCount(wasReviewed: wasReviewed)
            restorePhotoPosition(asset, preferredIndex: originalIndex)
        }
        HapticManager.notify(.success)
        showFeedback(L10n.string("已撤销上一步"), icon: "arrow.uturn.backward", style: .positive)
    }

    private func markDeleteCandidate(_ asset: PHAsset) {
        let originalIndex = currentPhotoIndex
        let wasReviewed = dataManager.markReviewed(asset)
        recordSessionReviewedChange(wasReviewed: wasReviewed)
        dataManager.addToDeleteCandidates(asset)
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
        let wasReviewed = dataManager.markReviewed(asset)
        recordSessionReviewedChange(wasReviewed: wasReviewed)
        dataManager.addToFavoriteCandidates(asset)
        actionHistory.append(.favorite(asset, originalIndex: originalIndex, wasReviewed: wasReviewed))
        HapticManager.impact(.light)
        showFeedback(L10n.string("已加入待收藏"), icon: "heart.fill", style: .favorite, showsUndo: true)
    }

    private func markSkip(_ asset: PHAsset, message: String? = nil) {
        let originalIndex = currentPhotoIndex
        let wasReviewed = dataManager.markReviewed(asset)
        recordSessionReviewedChange(wasReviewed: wasReviewed)
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
        showFeedback(L10n.string("正在归类到 \(albumInfo.title)"), icon: "folder", style: .neutral, duration: 1.0)
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

    private func handleBackAction() {
        // 如果有待处理的删除操作，显示确认对话框
        if hasPendingOperations {
            shouldDismissAfterBatch = true
            showBatchConfirm = true
        } else {
            dismiss()
        }
    }

    private var hasPendingOperations: Bool {
        !dataManager.deleteCandidates.isEmpty || !dataManager.favoriteCandidates.isEmpty
    }

    private var sessionModeTitle: String {
        if selectedAlbumInfo != nil {
            return L10n.string("相册整理")
        }
        if selectedDate != nil {
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
        style: PhotoDelToastStyle,
        showsUndo: Bool = false,
        duration: TimeInterval = 3.0
    ) {
        let toast = PhotoDelToast(message: message, icon: icon, style: style, showsUndo: showsUndo)
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

private enum AdvancedSwipeDateFormatter {
    static let dayTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMEd")
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
                                PhotoDelStyle.surface,
                                PhotoDelStyle.elevatedSurface
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
                                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDelStyle.accent))
                                    .scaleEffect(1.2)
                            } else {
                                VStack(spacing: 10) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: PhotoDelStyle.accent))
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
                .stroke(PhotoDelStyle.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 26, x: 0, y: 18)
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
                        .fill(PhotoDelStyle.background.opacity(0.62))
                        .frame(width: 30, height: 30)

                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
            }

            if photoLibraryManager.isScreenshot(asset) {
                ZStack {
                    Circle()
                        .fill(PhotoDelStyle.background.opacity(0.62))
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
                    .fill(PhotoDelStyle.background.opacity(0.72))

                VStack(spacing: 12) {
                    Image(systemName: isInDeleteCandidates ? "trash.fill" : "heart.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundColor(isInDeleteCandidates ? PhotoDelStyle.destructive : PhotoDelStyle.iconTint(for: "favorite"))

                    Text(isInDeleteCandidates ? L10n.string("待删除") : L10n.string("待收藏"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)
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
                        .progressViewStyle(LinearProgressViewStyle(tint: PhotoDelStyle.accent))
                        .frame(maxWidth: 230)
                        .clipShape(Capsule(style: .continuous))

                    Text(L10n.percent(Int(progress * 100)))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.tertiaryText)
                }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDelStyle.accent))
                    .scaleEffect(1.05)
            }

            VStack(spacing: 7) {
                Text(title.appLocalized)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(message.appLocalized)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .photoDelCard()
    }
}

private struct GestureHintPill: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)

            Text(title.appLocalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PhotoDelStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill(PhotoDelStyle.surface)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(color.opacity(0.24), lineWidth: 1)
                )
        )
    }
}

// MARK: - 滑动指示器
struct SwipeIndicator: View {
    let direction: SwipePhotoView.SwipeDirection
    let action: SwipeGestureAction

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: action.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(action.tint)

            Text(action.detailTitle.appLocalized)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(PhotoDelStyle.background.opacity(0.82))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(action.tint.opacity(0.38), lineWidth: 1)
                )
        )
        .offset(indicatorOffset)
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
struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(PhotoDelStyle.elevatedSurface)
                        .overlay(
                            Circle()
                                .stroke(color.opacity(0.38), lineWidth: 1)
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(color)
                }

                Text(title.appLocalized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
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
                .foregroundColor(PhotoDelStyle.primaryText)

            Spacer()

            Text(detail.appLocalized)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(PhotoDelStyle.secondaryText)
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
                    .foregroundColor(PhotoDelStyle.primaryText)
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
                    .fill(PhotoDelStyle.surface)
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
        let deleteAssets = sortedAssets(Array(dataManager.deleteCandidates))
        let favoriteAssets = sortedAssets(Array(dataManager.favoriteCandidates))

        ZStack {
            PhotoDelScreenBackground()

            VStack(spacing: 22) {
                VStack(spacing: 16) {
                    Image(systemName: dataManager.deleteCandidates.isEmpty ? "checkmark.circle.fill" : "trash.circle.fill")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundColor(dataManager.deleteCandidates.isEmpty ? PhotoDelStyle.positive : PhotoDelStyle.destructive)

                    Text("执行批量操作")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    VStack(spacing: 8) {
                        if !dataManager.deleteCandidates.isEmpty {
                            Text("删除 \(dataManager.deleteCandidates.count) 张照片")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDelStyle.destructive)
                        }

                        if !dataManager.favoriteCandidates.isEmpty {
                            Text("收藏 \(dataManager.favoriteCandidates.count) 张照片")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDelStyle.iconTint(for: "favorite"))
                        }

                        if !hasPendingOperations {
                            Text("没有待执行的操作")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(PhotoDelStyle.warning)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                        }
                    }
                }

                if hasPendingOperations {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            if !deleteAssets.isEmpty {
                                CandidatePreviewSection(
                                    title: L10n.string("将删除"),
                                    assets: deleteAssets,
                                    color: PhotoDelStyle.destructive,
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
                                    color: PhotoDelStyle.iconTint(for: "favorite"),
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
                    .frame(maxHeight: 330)
                }

                VStack(spacing: 12) {
                    Button(action: executeBatchOperations) {
                        Text(isProcessing ? "正在执行..." : "确认执行")
                    }
                    .photoDelPrimaryButton()
                    .disabled(isProcessing || !hasPendingOperations)

                    Button(action: cancelOperations) {
                        Text("取消操作")
                    }
                    .photoDelSecondaryButton()
                    .disabled(isProcessing)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
            .photoDelCard()
            .padding(.horizontal, 24)
        }
        .sheet(item: $previewAsset) { previewAsset in
            CandidatePhotoPreviewView(
                asset: previewAsset.asset,
                photoLibraryManager: dataManager.photoLibraryManager
            )
        }
    }

    private func executeBatchOperations() {
        guard hasPendingOperations else {
            dismiss()
            return
        }

        isProcessing = true
        errorMessage = nil
        let deletedAssets = Array(dataManager.deleteCandidates)
        dataManager.executeBatchOperations { success, error in
            isProcessing = false
            if success {
                DispatchQueue.main.async {
                    dataManager.recordDeletedPhotosFromAlbum(
                        albumID: albumInfo?.id,
                        deletedAssets: deletedAssets
                    )
                    dismiss()
                    onComplete?()
                }
            } else {
                errorMessage = error?.localizedDescription ?? L10n.string("操作失败，请稍后重试。")
            }
        }
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
                    .foregroundColor(PhotoDelStyle.primaryText)

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
                .fill(PhotoDelStyle.surface)
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
                .overlay(Circle().stroke(PhotoDelStyle.background.opacity(0.8), lineWidth: 1.5))
                .offset(x: -53, y: -53)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(PhotoDelStyle.background.opacity(0.9)))
                    .overlay(Circle().stroke(PhotoDelStyle.primaryText.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removeAccessibilityLabel)
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
                .fill(PhotoDelStyle.elevatedSurface)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: PhotoDelStyle.accent))
                            .scaleEffect(0.72)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(PhotoDelStyle.secondaryText)
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
                    PhotoDelStyle.background.ignoresSafeArea()

                    if let image {
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
                                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDelStyle.accent))
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 36, weight: .medium))
                                    .foregroundColor(PhotoDelStyle.secondaryText)
                            }

                            Text(isLoading ? L10n.string("正在读取照片") : L10n.string("无法读取这张照片"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                        }
                    }
                }
                .onAppear {
                    loadImage(in: geometry.size)
                }
            }
            .navigationTitle(L10n.string("照片预览"))
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
