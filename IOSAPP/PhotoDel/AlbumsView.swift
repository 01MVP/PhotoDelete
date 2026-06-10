//
//  AlbumsView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI
import Photos

struct AlbumsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    @State private var showingCreateAlbum = false
    @State private var editingAlbum: PHAssetCollection?
    @State private var showingEditAlbum = false
    @State private var isLoading = false
    @State private var showSwipeView = false
    @State private var selectedAlbumInfo: AlbumInfo?
    @State private var showSearchBar = false

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
        .sheet(isPresented: $showSwipeView) {
            if let albumInfo = selectedAlbumInfo {
                SwipePhotoView(selectedCategory: nil, selectedTimeGroup: nil, selectedAlbumInfo: albumInfo)
                    .environmentObject(dataManager)
            }
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

                if isLoading {
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
                                        selectedAlbumInfo = albumInfo
                                        showSwipeView = true
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
                                    isCompact: true
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
                                        selectedAlbumInfo = albumInfo
                                        showSwipeView = true
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
                                    isCompact: true
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
        VStack(spacing: 10) {
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
    private var filteredSystemAlbums: [AlbumInfo] {
        let albums = dataManager.getSystemAlbums()
        if searchText.isEmpty {
            return albums
        } else {
            return albums.filter { albumInfo in
                albumInfo.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var filteredUserAlbums: [AlbumInfo] {
        let albums = dataManager.getUserAlbums()
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

    private func deleteAlbum(_ album: PHAssetCollection) {
        // 只有用户创建的相册可以删除（非系统相册）
        guard album.assetCollectionType == .album else { return }

        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.dataManager.loadAlbums()
                } else if let error = error {
                    print("删除相册失败: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - 相册信息行
struct AlbumInfoRow: View {
    let albumInfo: AlbumInfo
    let photoLibraryManager: PhotoLibraryManager
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let isCompact: Bool

    @State private var thumbnailImage: UIImage?

    init(albumInfo: AlbumInfo, photoLibraryManager: PhotoLibraryManager, onTap: @escaping () -> Void, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void, isCompact: Bool = false) {
        self.albumInfo = albumInfo
        self.photoLibraryManager = photoLibraryManager
        self.onTap = onTap
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.isCompact = isCompact
    }

    var body: some View {
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

            HStack(spacing: 16) {
                if albumInfo.type == .userCreated {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(PhotoDelStyle.destructive)
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
            }
        }
        .padding(isCompact ? 8 : 12)
        .photoDelCard(radius: 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            loadAlbumThumbnail()
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
