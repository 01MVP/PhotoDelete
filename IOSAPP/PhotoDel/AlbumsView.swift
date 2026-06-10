//
//  AlbumsView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

struct AlbumsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    @State private var showingCreateAlbum = false
    @State private var editingAlbum: PHAssetCollection?
    @State private var showingEditAlbum = false
    @State private var selectedAlbumInfo: AlbumInfo?
    @State private var showSearchBar = false
    @State private var sortMode: AlbumSortMode = .defaultOrder
    @State private var albumToast: AlbumToast?

    var body: some View {
        NavigationView {
            ZStack {
                PhotoDelScreenBackground()

                VStack(spacing: 0) {
                    // 顶部区域
                    headerSection

                    if !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                        // 权限授权区域
                        authorizationSection
                    } else {
                        // 相册列表
                        albumsList
                    }
                }

                if let albumToast {
                    albumToastView(albumToast)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingCreateAlbum) {
            CreateAlbumView()
                .environmentObject(dataManager)
                .onDisappear {
                    dataManager.loadAlbums()
                }
        }
        .sheet(isPresented: $showingEditAlbum) {
            if let album = editingAlbum {
                EditAlbumView(album: album)
                    .environmentObject(dataManager)
                    .onDisappear {
                        dataManager.loadAlbums()
                    }
            }
        }
        .sheet(item: $selectedAlbumInfo) { albumInfo in
            SwipePhotoView(selectedCategory: nil, selectedTimeGroup: nil, selectedAlbumInfo: albumInfo)
                .environmentObject(dataManager)
        }
        .onAppear {
            dataManager.loadAlbums()
        }
    }

    // MARK: - 顶部区域
    private var headerSection: some View {
        VStack(spacing: 20) {
            // 标题
            VStack(spacing: 8) {
                Text("相册管理")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                if dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                    Text("管理您的照片相册")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                } else {
                    Text("需要访问照片库权限")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(PhotoDelStyle.accent)
                }
            }
            .padding(.top, 20)

            // 搜索栏和创建按钮（仅在已授权时显示）
            if dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                HStack {
                    Spacer()

                    // 创建相册按钮
                    Button(action: {
                        showingCreateAlbum = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.86))
                            .frame(width: 44, height: 44)
                            .background(PhotoDelStyle.accent)
                            .clipShape(RoundedRectangle(cornerRadius: PhotoDelStyle.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - 权限授权区域
    private var authorizationSection: some View {
        VStack {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundColor(PhotoDelStyle.accent)

                Text("需要访问照片库")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text("需要访问您的照片库来管理相册。我们不会上传或分享您的照片。")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)

                Button(action: {
                    dataManager.requestPhotoLibraryAccess()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))

                        Text("继续")
                    }
                }
                .photoDelPrimaryButton()
            }
            .padding(24)
            .photoDelCard()
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - 相册列表
    private var albumsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                pullSearchArea

                if isLoadingAlbums {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: PhotoDelStyle.accent))
                            .scaleEffect(1.2)

                        Text("加载相册中...")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                    }
                    .padding(.top, 40)
                } else {
                    // 系统相册
                    if !filteredSystemAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("系统相册 (\(filteredSystemAlbums.count)个)")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.primaryText)
                                .padding(.horizontal, 24)
                                .padding(.top, 12)

                            ForEach(filteredSystemAlbums) { albumInfo in
                                AlbumInfoRow(
                                    albumInfo: albumInfo,
                                    photoLibraryManager: dataManager.photoLibraryManager,
                                    onTap: {
                                        openAlbum(albumInfo)
                                    },
                                    onEdit: {
                                        if let collection = albumInfo.assetCollection {
                                            editingAlbum = collection
                                            showingEditAlbum = true
                                        }
                                    },
                                    onDelete: {
                                        if let collection = albumInfo.assetCollection {
                                            deleteAlbum(collection)
                                        }
                                    },
                                    isCompact: true,
                                    allowsSwipeActions: false
                                )
                                .padding(.horizontal, 24)
                            }
                        }
                    }

                    // 用户创建的相册
                    if !filteredUserAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("我的相册 (\(filteredUserAlbums.count)个)")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.primaryText)
                                .padding(.horizontal, 24)
                                .padding(.top, 12)

                            ForEach(filteredUserAlbums, id: \.id) { albumInfo in
                                AlbumInfoRow(
                                    albumInfo: albumInfo,
                                    photoLibraryManager: dataManager.photoLibraryManager,
                                    onTap: {
                                        openAlbum(albumInfo)
                                    },
                                    onEdit: {
                                        if let collection = albumInfo.assetCollection {
                                            editingAlbum = collection
                                            showingEditAlbum = true
                                        }
                                    },
                                    onDelete: {
                                        if let collection = albumInfo.assetCollection {
                                            deleteAlbum(collection)
                                        }
                                    },
                                    isCompact: true,
                                    allowsSwipeActions: true
                                )
                                .padding(.horizontal, 24)
                            }
                        }
                    }

                    if filteredSystemAlbums.isEmpty && filteredUserAlbums.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 60, weight: .medium))
                                .foregroundColor(PhotoDelStyle.secondaryText)

                            Text("没有找到相册")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.primaryText)

                            Text("尝试创建一个新相册或检查搜索条件")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                        }
                        .padding(.top, 60)
                    }
                }

                // 底部安全区域
                Spacer()
                    .frame(height: 100)
            }
        }
    }

    private var pullSearchArea: some View {
        VStack(spacing: 12) {
            if showSearchBar {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(PhotoDelStyle.secondaryText)

                    TextField("搜索相册", text: $searchText)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Button(action: hideSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: PhotoDelStyle.controlRadius, style: .continuous)
                        .fill(PhotoDelStyle.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: PhotoDelStyle.controlRadius, style: .continuous)
                                .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                        )
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                Button(action: showSearch) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                        Text("搜索相册")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(PhotoDelStyle.tertiaryText)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            if !dataManager.getAllAlbums().isEmpty {
                Picker("排序", selection: $sortMode) {
                    ForEach(AlbumSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    if value.translation.height > 34 {
                        showSearch()
                    } else if value.translation.height < -34 {
                        hideSearch()
                    }
                }
        )
    }

    // MARK: - 计算属性
    private var isLoadingAlbums: Bool {
        dataManager.isLoadingAlbums || dataManager.isPreparingLibrary || dataManager.photoLibraryManager.isLoading
    }

    private var filteredSystemAlbums: [AlbumInfo] {
        let albums = sortedAlbums(dataManager.getSystemAlbums())
        if searchText.isEmpty {
            return albums
        } else {
            return albums.filter { albumInfo in
                albumInfo.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var filteredUserAlbums: [AlbumInfo] {
        let albums = sortedAlbums(dataManager.getUserAlbums())
        if searchText.isEmpty {
            return albums
        } else {
            return albums.filter { albumInfo in
                albumInfo.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - 方法
    private func showSearch() {
        withAnimation(.easeInOut(duration: 0.22)) {
            showSearchBar = true
        }
    }

    private func hideSearch() {
        withAnimation(.easeInOut(duration: 0.22)) {
            showSearchBar = false
            searchText = ""
        }
    }

    private func sortedAlbums(_ albums: [AlbumInfo]) -> [AlbumInfo] {
        switch sortMode {
        case .defaultOrder:
            return albums
        case .name:
            return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .count:
            return albums.sorted { $0.photosCount > $1.photosCount }
        }
    }

    private func openAlbum(_ albumInfo: AlbumInfo) {
        guard !isLoadingAlbums else {
            showAlbumToast("相册还在加载中", icon: "hourglass", style: .neutral)
            return
        }

        let photos = dataManager.getPhotosForAlbum(albumInfo)
        guard !photos.isEmpty else {
            impact(.light)
            showAlbumToast("这个相册还没有照片", icon: "photo", style: .warning)
            return
        }

        impact(.light)
        selectedAlbumInfo = albumInfo
    }

    private func deleteAlbum(_ album: PHAssetCollection) {
        // 只有用户创建的相册可以删除（非系统相册）
        guard album.assetCollectionType == .album else { return }

        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.notify(.success)
                    self.showAlbumToast("相册已删除", icon: "trash", style: .positive)
                    self.dataManager.loadAlbums()
                } else if let error = error {
                    self.notify(.error)
                    self.showAlbumToast("删除失败，请再试一次", icon: "exclamationmark.triangle", style: .warning)
                    print("删除相册失败: \(error.localizedDescription)")
                }
            }
        }
    }

    private func showAlbumToast(_ message: String, icon: String, style: AlbumToastStyle) {
        let toast = AlbumToast(message: message, icon: icon, style: style)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            albumToast = toast
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard albumToast?.id == toast.id else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                albumToast = nil
            }
        }
    }

    private func albumToastView(_ toast: AlbumToast) -> some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                Image(systemName: toast.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(toast.style.color)

                Text(toast.message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(PhotoDelStyle.background.opacity(0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(toast.style.color.opacity(0.35), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 8)
            .padding(.bottom, 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

private enum AlbumSortMode: String, CaseIterable, Identifiable {
    case defaultOrder
    case name
    case count

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultOrder:
            return "默认"
        case .name:
            return "名称"
        case .count:
            return "数量"
        }
    }
}

private enum AlbumToastStyle {
    case neutral
    case positive
    case warning

    var color: Color {
        switch self {
        case .neutral:
            return PhotoDelStyle.accent
        case .positive:
            return PhotoDelStyle.positive
        case .warning:
            return PhotoDelStyle.warning
        }
    }
}

private struct AlbumToast: Identifiable {
    let id = UUID()
    let message: String
    let icon: String
    let style: AlbumToastStyle
}

// MARK: - 相册信息行
struct AlbumInfoRow: View {
    let albumInfo: AlbumInfo
    let photoLibraryManager: PhotoLibraryManager
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let isCompact: Bool
    let allowsSwipeActions: Bool

    @State private var thumbnailImage: UIImage?
    @State private var revealOffset: CGFloat = 0
    @State private var actionsRevealed = false

    private let actionWidth: CGFloat = 112

    init(
        albumInfo: AlbumInfo,
        photoLibraryManager: PhotoLibraryManager,
        onTap: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        isCompact: Bool = false,
        allowsSwipeActions: Bool = false
    ) {
        self.albumInfo = albumInfo
        self.photoLibraryManager = photoLibraryManager
        self.onTap = onTap
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.isCompact = isCompact
        self.allowsSwipeActions = allowsSwipeActions
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if allowsSwipeActions {
                HStack(spacing: 0) {
                    Button(action: {
                        closeActions()
                        onEdit()
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.primaryText)
                            .frame(width: 56, height: isCompact ? 66 : 78)
                            .background(PhotoDelStyle.elevatedSurface)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        closeActions()
                        onDelete()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: isCompact ? 66 : 78)
                            .background(PhotoDelStyle.destructive)
                    }
                    .buttonStyle(.plain)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button(action: handleRowTap) {
                rowContent
            }
            .buttonStyle(.plain)
            .offset(x: revealOffset)
            .simultaneousGesture(revealGesture)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            loadAlbumThumbnail()
        }
    }

    private var rowContent: some View {
        HStack(spacing: isCompact ? 12 : 16) {
            Group {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: isCompact ? 50 : 60, height: isCompact ? 50 : 60)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(PhotoDelStyle.elevatedSurface)
                            .frame(width: isCompact ? 50 : 60, height: isCompact ? 50 : 60)

                        Image(systemName: albumInfo.type.icon)
                            .font(.system(size: isCompact ? 16 : 20, weight: .medium))
                            .foregroundColor(albumIconTint)
                    }
                }
            }

            VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
                Text(albumInfo.title)
                    .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                    .lineLimit(1)

                Text("\(albumInfo.photosCount) 张照片")
                    .font(.system(size: isCompact ? 12 : 14, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PhotoDelStyle.tertiaryText)
        }
        .padding(isCompact ? 8 : 12)
        .photoDelCard(radius: 14)
    }

    private var revealGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard allowsSwipeActions,
                      abs(value.translation.width) > abs(value.translation.height) else { return }

                let baseOffset: CGFloat = actionsRevealed ? -actionWidth : 0
                let proposedOffset = min(0, max(-actionWidth, baseOffset + value.translation.width))
                revealOffset = proposedOffset
            }
            .onEnded { value in
                guard allowsSwipeActions else { return }
                let shouldReveal = value.translation.width < -34 || revealOffset < -actionWidth / 2
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    actionsRevealed = shouldReveal
                    revealOffset = shouldReveal ? -actionWidth : 0
                }
            }
    }

    private func closeActions() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            actionsRevealed = false
            revealOffset = 0
        }
    }

    private func handleRowTap() {
        if revealOffset < 0 {
            closeActions()
        } else {
            onTap()
        }
    }

    private func loadAlbumThumbnail() {
        // 加载缩略图
        if let thumbnailAsset = albumInfo.thumbnailAsset {
            photoLibraryManager.loadThumbnail(for: thumbnailAsset) { image in
                self.thumbnailImage = image
            }
        }
    }

    private var albumIconTint: Color {
        switch albumInfo.type {
        case .favorites:
            return PhotoDelStyle.iconTint(for: "favorite")
        case .videos:
            return PhotoDelStyle.iconTint(for: "video")
        default:
            return PhotoDelStyle.accent
        }
    }
}

// MARK: - 创建相册视图
struct CreateAlbumView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var albumName = ""
    @State private var isCreating = false

    var body: some View {
        NavigationView {
            ZStack {
                PhotoDelScreenBackground()

                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        Image(systemName: "plus.rectangle.on.folder")
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(PhotoDelStyle.accent)

                        Text("创建新相册")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.primaryText)
                    }

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("相册名称")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.primaryText)

                            TextField("输入相册名称", text: $albumName)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDelStyle.primaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: PhotoDelStyle.controlRadius, style: .continuous)
                                        .fill(PhotoDelStyle.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: PhotoDelStyle.controlRadius, style: .continuous)
                                                .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                                        )
                                )
                        }

                        Text("简洁的相册名称，如\"旅行\"、\"家庭\"等")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                            .multilineTextAlignment(.leading)
                    }

                    VStack(spacing: 12) {
                        Button(action: createAlbum) {
                            HStack(spacing: 8) {
                                if isCreating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                }

                                Text(isCreating ? "创建中..." : "创建相册")
                            }
                        }
                        .photoDelPrimaryButton()
                        .disabled(albumName.isEmpty || isCreating)

                        Button(action: { dismiss() }) {
                            Text("取消")
                        }
                        .photoDelSecondaryButton()
                    }

                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)
            }
            .navigationTitle("创建相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(PhotoDelStyle.secondaryText)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func createAlbum() {
        guard !albumName.isEmpty else { return }

        isCreating = true

        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
        }) { success, error in
            DispatchQueue.main.async {
                self.isCreating = false
                if success {
                    self.dismiss()
                } else if let error = error {
                    print("创建相册失败: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - 编辑相册视图
struct EditAlbumView: View {
    let album: PHAssetCollection
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var newName: String
    @State private var isUpdating = false

    init(album: PHAssetCollection) {
        self.album = album
        self._newName = State(initialValue: album.localizedTitle ?? "")
    }

    var body: some View {
        NavigationView {
            ZStack {
                PhotoDelScreenBackground()

                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(PhotoDelStyle.accent)

                        Text("编辑相册")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.primaryText)
                    }

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("相册名称")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.primaryText)

                            TextField("输入相册名称", text: $newName)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDelStyle.primaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: PhotoDelStyle.controlRadius, style: .continuous)
                                        .fill(PhotoDelStyle.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: PhotoDelStyle.controlRadius, style: .continuous)
                                                .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                                        )
                                )
                        }
                    }

                    VStack(spacing: 12) {
                        Button(action: updateAlbum) {
                            HStack(spacing: 8) {
                                if isUpdating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .semibold))
                                }

                                Text(isUpdating ? "更新中..." : "保存更改")
                            }
                        }
                        .photoDelPrimaryButton()
                        .disabled(newName.isEmpty || isUpdating)

                        Button(action: { dismiss() }) {
                            Text("取消")
                        }
                        .photoDelSecondaryButton()
                    }

                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)
            }
            .navigationTitle("编辑相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(PhotoDelStyle.secondaryText)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func updateAlbum() {
        guard !newName.isEmpty, album.assetCollectionType == .album else { return }

        isUpdating = true

        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest(for: album)
            request?.title = newName
        }) { success, error in
            DispatchQueue.main.async {
                self.isUpdating = false
                if success {
                    self.dismiss()
                } else if let error = error {
                    print("更新相册失败: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    AlbumsView()
        .environmentObject(DataManager())
}
