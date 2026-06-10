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
                    headerSection

                    if !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                        authorizationSection
                    } else {
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
                    dataManager.loadAlbums(showLoading: false)
                }
        }
        .sheet(isPresented: $showingEditAlbum) {
            if let album = editingAlbum {
                EditAlbumView(album: album)
                    .environmentObject(dataManager)
                    .onDisappear {
                        dataManager.loadAlbums(showLoading: false)
                    }
            }
        }
        .sheet(item: $selectedAlbumInfo) { albumInfo in
            SwipePhotoView(selectedCategory: nil, selectedTimeGroup: nil, selectedAlbumInfo: albumInfo)
                .environmentObject(dataManager)
        }
        .onAppear {
            dataManager.loadAlbums(showLoading: false)
        }
    }

    // MARK: - 顶部区域
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("相册")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(albumHeaderSubtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(dataManager.photoLibraryManager.hasPhotoLibraryAccess ? PhotoDelStyle.secondaryText : PhotoDelStyle.accent)
            }

            Spacer()

            if dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                Menu {
                    Picker("排序", selection: $sortMode) {
                        ForEach(AlbumSortMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(PhotoDelStyle.elevatedSurface))
                }
                .menuStyle(.button)

                Button(action: {
                    impact(.light)
                    showingCreateAlbum = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.86))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(PhotoDelStyle.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 12)
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
        List {
            if showSearchBar {
                searchRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isLoadingAlbums {
                loadingRow
            } else {
                if !filteredSystemAlbums.isEmpty {
                    Section {
                        ForEach(filteredSystemAlbums) { albumInfo in
                            albumRow(albumInfo, allowsActions: false)
                        }
                    } header: {
                        sectionHeader("系统相册", count: filteredSystemAlbums.count)
                    }
                }

                if !filteredUserAlbums.isEmpty {
                    Section {
                        ForEach(filteredUserAlbums) { albumInfo in
                            albumRow(albumInfo, allowsActions: true)
                        }
                    } header: {
                        sectionHeader("我的相册", count: filteredUserAlbums.count)
                    }
                }

                if filteredSystemAlbums.isEmpty && filteredUserAlbums.isEmpty {
                    emptyRow
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable {
            dataManager.loadAlbums(showLoading: false)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height > 46 {
                        showSearch()
                    } else if value.translation.height < -46 {
                        hideSearch()
                    }
                }
        )
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 88)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(PhotoDelStyle.secondaryText)

            TextField("搜索相册", text: $searchText)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(PhotoDelStyle.primaryText)
                .submitLabel(.search)

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
        .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 10, trailing: 24))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var loadingRow: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: PhotoDelStyle.accent))

            Text("加载相册中")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(PhotoDelStyle.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var emptyRow: some View {
        VStack(spacing: 18) {
            Image(systemName: searchText.isEmpty ? "photo.stack" : "magnifyingglass")
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(PhotoDelStyle.secondaryText)

            VStack(spacing: 6) {
                Text(searchText.isEmpty ? "还没有相册" : "没有找到相册")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(searchText.isEmpty ? "可以点右上角加号创建一个新相册。" : "换个关键词试试。")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 58)
        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title) (\(count))")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(PhotoDelStyle.tertiaryText)
            .textCase(nil)
            .padding(.top, 8)
    }

    private func albumRow(_ albumInfo: AlbumInfo, allowsActions: Bool) -> some View {
        Button(action: {
            openAlbum(albumInfo)
        }) {
            AlbumInfoRow(
                albumInfo: albumInfo,
                photoLibraryManager: dataManager.photoLibraryManager
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if allowsActions, let collection = albumInfo.assetCollection {
                Button(role: .destructive) {
                    deleteAlbum(collection)
                } label: {
                    Label("删除", systemImage: "trash")
                }

                Button {
                    editingAlbum = collection
                    showingEditAlbum = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .tint(.gray)
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var albumHeaderSubtitle: String {
        if !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
            return "需要访问照片库权限"
        }

        let albumCount = dataManager.getAllAlbums().count
        if dataManager.isLoadingAlbums && albumCount == 0 {
            return "正在读取相册"
        }
        return "\(albumCount) 个相册"
    }

    // MARK: - 计算属性
    private var isLoadingAlbums: Bool {
        dataManager.isLoadingAlbums && dataManager.getAllAlbums().isEmpty
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
        withAnimation(.easeInOut(duration: 0.2)) {
            showSearchBar = true
        }
    }

    private func hideSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
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
        guard album.assetCollectionType == .album else { return }

        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.notify(.success)
                    self.showAlbumToast("相册已删除", icon: "trash", style: .positive)
                    self.dataManager.loadAlbums(showLoading: false)
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

    var icon: String {
        switch self {
        case .defaultOrder:
            return "rectangle.stack"
        case .name:
            return "textformat"
        case .count:
            return "number"
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

    @State private var thumbnailImage: UIImage?

    var body: some View {
        rowContent
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            loadAlbumThumbnail()
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Group {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(PhotoDelStyle.elevatedSurface)
                            .frame(width: 56, height: 56)

                        Image(systemName: albumInfo.type.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(albumIconTint)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(albumInfo.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                    .lineLimit(1)

                Text("\(albumInfo.photosCount) 张照片")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PhotoDelStyle.tertiaryText)
        }
        .padding(10)
        .frame(minHeight: 76)
        .photoDelCard(radius: 14)
    }

    private func loadAlbumThumbnail() {
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
