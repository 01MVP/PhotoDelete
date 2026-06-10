//
//  SwipePhotoView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI
import Photos
import Foundation

struct SwipePhotoView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    let selectedCategory: PhotoCategory?
    let selectedTimeGroup: String?
    let selectedAlbumInfo: AlbumInfo?

    @State private var dragOffset = CGSize.zero
    @State private var rotationAngle: Double = 0
    @State private var showDeleteConfirm = false
    @State private var swipeDirection: SwipeDirection?
    @State private var showPhotoAccessAlert = false
    @State private var showBatchConfirm = false
    @State private var currentPhotoIndex = 0
    @State private var showCompletionMessage = false
    @State private var favoriteRefreshTrigger = false
    @State private var actionHistory: [SwipeAction] = []
    @State private var sessionPhotos: [PHAsset] = []
    @State private var shouldDismissAfterBatch = false

    enum SwipeDirection {
        case left, right, up, down
    }

    private enum SwipeAction {
        case delete(PHAsset)
        case favorite(PHAsset)
        case skip
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
        } else if let category = selectedCategory {
            return dataManager.getRealPhotos(for: category)
        } else if let timeGroupString = selectedTimeGroup,
                  let timeGroup = TimeGroup.allCases.first(where: { $0.rawValue == timeGroupString }) {
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

    // 是否在相册模式（不显示进度，因为相册内的照片已经整理过）
    private var isAlbumMode: Bool {
        return selectedAlbumInfo != nil
    }

    private var isCurrentPhotoFavorited: Bool {
        guard let asset = currentRealPhoto else { return false }
        _ = favoriteRefreshTrigger
        return asset.isFavorite || dataManager.isInFavoriteCandidates(asset)
    }

    var body: some View {
        ZStack {
            PhotoDelScreenBackground()

            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height && geometry.size.width > 620

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
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showBatchConfirm) {
            BatchConfirmView {
                if shouldDismissAfterBatch {
                    dismiss()
                }
            }
                .environmentObject(dataManager)
        }
        .onDisappear {
            // 页面消失时的清理工作（不自动弹出确认对话框，因为用户可能只是切换到其他页面）
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            // 处理内存警告
            dataManager.photoLibraryManager.handleMemoryWarning()
        }
        .onAppear {
            refreshSessionPhotos()
        }
        .onChange(of: dataManager.photoLibraryManager.allPhotos.count) { _ in
            refreshSessionPhotos()
        }
    }

    // MARK: - 导航栏
    private var navigationHeader: some View {
        HStack {
            // 返回按钮
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

            // 标题信息
            VStack(spacing: 2) {
                Text(isAlbumMode ? "相册整理" : "照片整理")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                if isAlbumMode {
                    Text("\(getDisplayTitle()) · \(totalPhotosCount) 张照片")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                } else {
                    Text("\(getDisplayTitle()) · \(currentProgress)/\(totalPhotosCount)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                }
            }

            Spacer()

            // 候选库统计
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
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
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
                    // 需要照片权限
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(PhotoDelStyle.accent)

                        Text("需要访问照片库")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.primaryText)

                        Text("请允许访问您的照片库来开始整理照片")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                            .multilineTextAlignment(.center)

                        Button(action: {
                            dataManager.requestPhotoLibraryAccess()
                        }) {
                            Text("继续")
                                .frame(maxWidth: 180)
                        }
                        .photoDelPrimaryButton()
                    }
                    .padding(24)
                    .photoDelCard()
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
                        .offset(dragOffset)
                        .rotationEffect(.degrees(rotationAngle))
                        .scaleEffect(1.0 - abs(dragOffset.width) / 1000)
                        .gesture(createDragGesture())

                        if abs(dragOffset.width) > 50 {
                            SwipeIndicator(direction: dragOffset.width < 0 ? .left : .right)
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
                                            Button("继续整理") {
                                                showCompletionMessage = false
                                            }
                                            .photoDelSecondaryButton()

                                            Button("完成整理") {
                                                shouldDismissAfterBatch = true
                                                showBatchConfirm = true
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
                    HStack(spacing: 24) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(PhotoDelStyle.destructive)
                            Text("左滑删除候选")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                        }

                        Text("·")
                            .foregroundColor(PhotoDelStyle.tertiaryText)

                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(PhotoDelStyle.positive)
                            Text("右滑跳过")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                        }
                    }
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
                    title: isCurrentPhotoFavorited ? "已收藏" : "收藏",
                    color: PhotoDelStyle.iconTint(for: "favorite")
                ) {
                    handleFavoriteAction()
                    resetCardPosition()
                }

                SidebarActionButton(
                    icon: "trash",
                    title: "删除候选",
                    color: PhotoDelStyle.destructive
                ) {
                    handleDeleteAction()
                    resetCardPosition()
                }

                SidebarActionButton(
                    icon: "arrow.right",
                    title: "跳过",
                    color: PhotoDelStyle.accent
                ) {
                    handleSkipAction()
                    resetCardPosition()
                }

                HStack(spacing: 10) {
                    SidebarActionButton(
                        icon: "arrow.uturn.backward",
                        title: "撤销",
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

            Text(isAlbumMode ? "\(totalPhotosCount) 张照片" : "\(currentProgress)/\(totalPhotosCount) 已浏览")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(PhotoDelStyle.secondaryText)

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

            GestureGuideRow(icon: "arrow.left", title: "左滑", detail: "删除候选", color: PhotoDelStyle.destructive)
            GestureGuideRow(icon: "arrow.right", title: "右滑", detail: "保留跳过", color: PhotoDelStyle.positive)
            GestureGuideRow(icon: "arrow.up", title: "上滑", detail: "加入收藏", color: PhotoDelStyle.iconTint(for: "favorite"))
        }
        .padding(16)
        .photoDelCard(radius: 16)
    }

    @ViewBuilder
    private func albumShortcutStrip(horizontalPadding: CGFloat) -> some View {
        if !isAlbumMode && !dataManager.userAlbums.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dataManager.userAlbums) { albumInfo in
                        Button(action: {
                            handleAddToAlbum(albumInfo)
                        }) {
                            Text(albumInfo.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(PhotoDelStyle.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(PhotoDelStyle.surface)
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                                        )
                                )
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
            .frame(height: 36)
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
    }

    // MARK: - 手势处理
    private func refreshSessionPhotos() {
        let photos = filteredRealPhotos
        sessionPhotos = photos
        currentPhotoIndex = min(currentPhotoIndex, max(photos.count - 1, 0))
        preloadUpcomingImages(from: currentPhotoIndex)
    }

    private func preloadUpcomingImages(from index: Int) {
        guard index < sessionPhotos.count else { return }
        let upcomingPhotos = Array(sessionPhotos.dropFirst(index).prefix(6))
        dataManager.photoLibraryManager.preloadImagesForAssets(
            upcomingPhotos,
            size: swipeImageTargetSize,
            maxCount: 6
        )
    }

    private var swipeImageTargetSize: CGSize {
        let scale = min(UIScreen.main.scale, 2)
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
        let scale = min(UIScreen.main.scale, 2)
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

        if abs(translation.width) > threshold {
            if translation.width < 0 {
                // 左滑：添加到删除候选库
                markDeleteCandidate(asset)
                moveToNextPhoto()
            } else {
                // 右滑：跳过
                actionHistory.append(.skip)
                moveToNextPhoto()
            }
        } else if abs(translation.height) > threshold {
            if translation.height < 0 {
                // 上滑：添加到收藏候选库
                markFavoriteCandidate(asset)
                moveToNextPhoto()
            } else {
                // 下滑：跳过
                actionHistory.append(.skip)
                moveToNextPhoto()
            }
        }

        resetCardPosition()
    }

    private func moveToNextPhoto() {
        guard !sessionPhotos.isEmpty else { return }

        let newIndex = currentPhotoIndex + 1
        if newIndex < sessionPhotos.count {
            currentPhotoIndex = newIndex
            preloadUpcomingImages(from: newIndex)
        } else {
            // 到达最后一张照片时显示完成提示
            showCompletionMessage = true
        }
    }

    private func moveToPreviousPhoto() {
        guard currentPhotoIndex > 0 else { return }
        currentPhotoIndex -= 1
    }

    private func isValidPhotoIndex(_ index: Int) -> Bool {
        return index >= 0 && index < sessionPhotos.count
    }

    private func handleFavoriteAction() {
        guard let asset = currentRealPhoto else { return }
        markFavoriteCandidate(asset)

        // 强制刷新UI以更新收藏状态显示
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            favoriteRefreshTrigger.toggle()
        }
        moveToNextPhoto()
    }

    private func handleDeleteAction() {
        guard let asset = currentRealPhoto else { return }
        markDeleteCandidate(asset)
        moveToNextPhoto()
    }

    private func handleSkipAction() {
        actionHistory.append(.skip)
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
        if let lastAction = actionHistory.popLast() {
            switch lastAction {
            case .delete(let asset):
                dataManager.removeFromDeleteCandidates(asset)
            case .favorite(let asset):
                dataManager.removeFromFavoriteCandidates(asset)
            case .skip:
                break
            }
        }
        moveToPreviousPhoto()
    }

    private func markDeleteCandidate(_ asset: PHAsset) {
        dataManager.addToDeleteCandidates(asset)
        actionHistory.append(.delete(asset))
    }

    private func markFavoriteCandidate(_ asset: PHAsset) {
        guard !asset.isFavorite else {
            actionHistory.append(.skip)
            return
        }

        dataManager.addToFavoriteCandidates(asset)
        actionHistory.append(.favorite(asset))
    }

    private func handleAddToAlbum(_ albumInfo: AlbumInfo) {
        guard let asset = currentRealPhoto,
              let assetCollection = albumInfo.assetCollection else { return }

        // 将照片添加到指定相册
        dataManager.addPhotoToAlbum(asset, album: assetCollection) { success in
            DispatchQueue.main.async {
                if success {
                    // 添加成功后移动到下一张照片
                    self.moveToNextPhoto()
                } else {
                    // 添加失败，可以显示错误提示
                    print("添加照片到相册失败")
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

    private func getDisplayTitle() -> String {
        if let albumInfo = selectedAlbumInfo {
            return albumInfo.title
        } else if let category = selectedCategory {
            return category.rawValue
        } else if let timeGroup = selectedTimeGroup {
            return timeGroup
        } else {
            return "全部照片"
        }
    }
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
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
        .onAppear {
            loadImage()
        }
        .onChange(of: asset.localIdentifier) { _ in
            loadImage()
        }
        .onDisappear {
            photoLibraryManager.cancelImageRequest(requestID)
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

            if isScreenshot {
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

                    Text(isInDeleteCandidates ? "删除候选" : "收藏候选")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            .cornerRadius(20)
        }
    }

    private var isScreenshot: Bool {
        if #available(iOS 9.0, *) {
            return asset.mediaSubtypes.contains(.photoScreenshot)
        }

        // 备用方法：通过尺寸判断
        let screenScale = UIScreen.main.scale
        let screenSize = UIScreen.main.bounds.size
        let screenPixelSize = CGSize(
            width: screenSize.width * screenScale,
            height: screenSize.height * screenScale
        )

        let assetSize = CGSize(width: CGFloat(asset.pixelWidth), height: CGFloat(asset.pixelHeight))

        return abs(assetSize.width - screenPixelSize.width) < 10 &&
               abs(assetSize.height - screenPixelSize.height) < 10
    }

    private func loadImage() {
        photoLibraryManager.cancelImageRequest(requestID)
        isLoading = true
        image = nil
        let requestedAssetID = asset.localIdentifier

        requestID = photoLibraryManager.loadImage(for: asset, size: targetSize) { loadedImage in
            guard asset.localIdentifier == requestedAssetID else { return }
            self.image = loadedImage
            self.isLoading = false
            self.requestID = nil
        }
    }
}

// MARK: - 滑动指示器
struct SwipeIndicator: View {
    let direction: SwipePhotoView.SwipeDirection

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: direction == .left ? "trash" : "arrow.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(direction == .left ? PhotoDelStyle.destructive : PhotoDelStyle.positive)

            Text(direction == .left ? "删除候选" : "跳过")
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
                        .stroke(direction == .left ? PhotoDelStyle.destructive.opacity(0.38) : PhotoDelStyle.positive.opacity(0.38), lineWidth: 1)
                )
        )
        .offset(x: direction == .left ? -100 : 100)
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

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 60)
        }
        .buttonStyle(PlainButtonStyle())
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

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)

            Spacer()

            Text(detail)
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

                Text(title)
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
    let onComplete: (() -> Void)?

    init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
    }

    private var hasPendingOperations: Bool {
        !dataManager.deleteCandidates.isEmpty || !dataManager.favoriteCandidates.isEmpty
    }

    var body: some View {
        ZStack {
            PhotoDelScreenBackground()

            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundColor(PhotoDelStyle.positive)

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
            .padding(.vertical, 36)
            .photoDelCard()
            .padding(.horizontal, 24)
        }
    }

    private func executeBatchOperations() {
        guard hasPendingOperations else {
            dismiss()
            return
        }

        isProcessing = true
        errorMessage = nil
        dataManager.executeBatchOperations { success, error in
            isProcessing = false
            if success {
                // 重新加载数据以更新主页
                DispatchQueue.main.async {
                    dataManager.loadTimeGroups()
                    dataManager.loadAlbums()
                    dismiss()
                    onComplete?()
                }
            } else {
                errorMessage = error?.localizedDescription ?? "操作失败，请稍后重试。"
            }
        }
    }

    private func cancelOperations() {
        dataManager.cancelAllOperations()
        dismiss()
    }
}

#Preview {
    SwipePhotoView(selectedCategory: PhotoCategory.all, selectedTimeGroup: nil, selectedAlbumInfo: nil)
        .environmentObject(DataManager())
}
