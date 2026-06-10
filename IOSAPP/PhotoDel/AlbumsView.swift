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
    @State private var userAlbumsOrder: [String] = []

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

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
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                if dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                    Text("管理您的照片相册")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.gray)
                } else {
                    Text("需要访问照片库权限")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.orange)
                }
            }
            .padding(.top, 20)

            // 搜索栏和创建按钮（仅在已授权时显示）
            if dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                HStack(spacing: 12) {
                    // 搜索栏（条件显示）
                    if showSearchBar {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.gray)

                            TextField("搜索相册", text: $searchText)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // 搜索按钮（当搜索栏隐藏时显示）
                    if !showSearchBar {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showSearchBar = true
                            }
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.gray.opacity(0.6))
                                .cornerRadius(8)
                        }
                    }

                    // 创建相册按钮
                    Button(action: {
                        showingCreateAlbum = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
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
                    .foregroundColor(.blue)

                Text("需要访问照片库")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("需要访问您的照片库来管理相册。我们不会上传或分享您的照片。")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)

                Button(action: {
                    dataManager.requestPhotoLibraryAccess()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 16, weight: .semibold))

                        Text("授权访问照片库")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - 相册列表
    private var albumsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 下拉区域（用于显示搜索框）
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 20)
                    .gesture(
                        DragGesture()
                            .onEnded { value in
                                if value.translation.height > 50 && !showSearchBar {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showSearchBar = true
                                    }
                                } else if value.translation.height < -50 && showSearchBar {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showSearchBar = false
                                        searchText = ""
                                    }
                                }
                            }
                    )
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)

                        Text("加载相册中...")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                } else {
                    // 系统相册
                    if !filteredSystemAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("系统相册 (\(filteredSystemAlbums.count)个)")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
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
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.top, 12)

                            ForEach(orderedUserAlbums, id: \.id) { albumInfo in
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
                            .onMove(perform: moveUserAlbums)
                        }
                    }

                    if filteredSystemAlbums.isEmpty && filteredUserAlbums.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 60, weight: .medium))
                                .foregroundColor(.gray)

                            Text("没有找到相册")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)

                            Text("尝试创建一个新相册或检查搜索条件")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.gray)
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

    private var orderedUserAlbums: [AlbumInfo] {
        let albums = filteredUserAlbums
        if userAlbumsOrder.isEmpty {
            return albums
        }

        // 根据保存的顺序重新排列相册
        var orderedAlbums: [AlbumInfo] = []
        var remainingAlbums = albums

        // 按照保存的顺序添加相册
        for albumId in userAlbumsOrder {
            if let index = remainingAlbums.firstIndex(where: { $0.id == albumId }) {
                orderedAlbums.append(remainingAlbums.remove(at: index))
            }
        }

        // 添加新的相册（不在保存顺序中的）
        orderedAlbums.append(contentsOf: remainingAlbums)

        return orderedAlbums
    }

    // MARK: - 方法
    private func moveUserAlbums(from source: IndexSet, to destination: Int) {
        var newOrder = orderedUserAlbums.map { $0.id }
        newOrder.move(fromOffsets: source, toOffset: destination)
        userAlbumsOrder = newOrder
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

    @State private var dragOffset: CGSize = .zero
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
        ZStack {
            // 背景操作按钮
            HStack {
                // 编辑按钮
                Button(action: onEdit) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue)
                            .frame(width: 60, height: 60)

                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                // 删除按钮（只有用户创建的相册可以删除）
                if albumInfo.type == .userCreated {
                    Button(action: onDelete) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red)
                                .frame(width: 60, height: 60)

                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .opacity(abs(dragOffset.width) > 20 ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: dragOffset)

            // 主要内容
            HStack(spacing: isCompact ? 12 : 16) {
                // 相册缩略图
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
                                .fill(albumInfo.type.color.opacity(0.3))
                                .frame(width: isCompact ? 50 : 60, height: isCompact ? 50 : 60)

                            Image(systemName: albumInfo.type.icon)
                                .font(.system(size: isCompact ? 16 : 20, weight: .medium))
                                .foregroundColor(albumInfo.type.color)
                        }
                    }
                }

                // 相册信息
                VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
                    Text(albumInfo.title)
                        .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text("\(albumInfo.photosCount) 张照片")
                        .font(.system(size: isCompact ? 12 : 14, weight: .regular))
                        .foregroundColor(.gray)
                }

                Spacer()

                // 操作按钮
                HStack(spacing: 16) {
                    if albumInfo.type == .userCreated {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                        }

                        Button(action: {
                            withAnimation {
                                onDelete()
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }

                    // 进入整理页面箭头
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
            .padding(isCompact ? 8 : 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            )
            .offset(dragOffset)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        if abs(value.translation.width) > 100 {
                            if value.translation.width > 0 {
                                onEdit()
                            } else if albumInfo.type == .userCreated {
                                onDelete()
                            }
                        }

                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    }
            )
        }
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
                Color.black.ignoresSafeArea()

                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        Image(systemName: "plus.rectangle.on.folder")
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(.blue)

                        Text("创建新相册")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("相册名称")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)

                            TextField("输入相册名称", text: $albumName)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }

                        Text("简洁的相册名称，如\"旅行\"、\"家庭\"等")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.gray)
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
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(albumName.isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(12)
                        }
                        .disabled(albumName.isEmpty || isCreating)

                        Button(action: { dismiss() }) {
                            Text("取消")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                        }
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
                    .foregroundColor(.gray)
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
                Color.black.ignoresSafeArea()

                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(.blue)

                        Text("编辑相册")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("相册名称")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)

                            TextField("输入相册名称", text: $newName)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(newName.isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(12)
                        }
                        .disabled(newName.isEmpty || isUpdating)

                        Button(action: { dismiss() }) {
                            Text("取消")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                        }
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
                    .foregroundColor(.gray)
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
