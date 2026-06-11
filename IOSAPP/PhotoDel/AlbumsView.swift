//
//  AlbumsView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI
import Photos
import OSLog
#if canImport(UIKit)
import UIKit
#endif

private let albumsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "PhotoDel",
    category: "Albums"
)

struct AlbumsView: View {
    @EnvironmentObject var dataManager: DataManager
    @AppStorage(AppConstants.customAlbumOrderKey) private var customAlbumOrderData = "[]"
    @State private var searchText = ""
    @State private var activeSheet: AlbumSheet?
    @State private var selectedSwipeAlbum: AlbumInfo?
    @State private var isShowingSwipeAlbum = false
    @State private var showSearchBar = false
    @State private var sortMode: AlbumSortMode = .custom
    @State private var editMode: EditMode = .inactive
    @State private var pendingAlbumToDelete: PHAssetCollection?
    @State private var showingDeleteAlbumConfirmation = false
    @State private var albumToast: PhotoDelToast?

    var body: some View {
        NavigationStack {
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
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $isShowingSwipeAlbum) {
            if let selectedSwipeAlbum {
                SwipePhotoView(selectedCategory: nil, selectedTimeGroup: nil, selectedAlbumInfo: selectedSwipeAlbum)
                    .environmentObject(dataManager)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                CreateAlbumView()
                    .environmentObject(dataManager)
            case .edit(let album):
                EditAlbumView(album: album)
                    .environmentObject(dataManager)
            }
        }
        .confirmationDialog(
            L10n.string("删除这个相册？"),
            isPresented: $showingDeleteAlbumConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.string("删除相册"), role: .destructive) {
                guard let pendingAlbumToDelete else { return }
                deleteAlbum(pendingAlbumToDelete)
                self.pendingAlbumToDelete = nil
            }
            Button(L10n.string("取消"), role: .cancel) {
                pendingAlbumToDelete = nil
            }
        } message: {
            Text(L10n.string("只会删除相册，不会删除相册里的照片。"))
        }
        .onChange(of: sortMode) { mode in
            guard mode != .custom else { return }
            editMode = .inactive
        }
        .onAppear {
            dataManager.loadAlbumsIfNeeded()
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
                    Picker(L10n.string("排序"), selection: $sortMode) {
                        ForEach(AlbumSortMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }

                    if sortMode == .custom {
                        Button {
                            toggleReordering()
                        } label: {
                            Label(editMode == .active ? L10n.string("完成排序") : L10n.string("调整顺序"), systemImage: "line.3.horizontal")
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
                .accessibilityLabel(L10n.string("排序"))

                Button(action: {
                    HapticManager.impact(.light)
                    activeSheet = .create
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryButtonText)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(PhotoDelStyle.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("创建相册"))
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
            PhotoAuthorizationCard(
                subtitle: L10n.string("需要访问您的照片库来管理相册。\(AppConstants.privacyShortText)"),
                onRequestAccess: { dataManager.requestPhotoLibraryAccess() }
            )
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - 相册列表
    @ViewBuilder
    private var albumsList: some View {
        let userAlbums = filteredUserAlbums
        List {
            if showSearchBar {
                searchRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isLoadingAlbums {
                loadingRow
            } else {
                if !userAlbums.isEmpty {
                    sectionHeaderRow(L10n.string("我的相册"), count: userAlbums.count)

                    ForEach(userAlbums) { albumInfo in
                        albumRow(albumInfo, allowsActions: true)
                    }
                    .onMove(perform: moveUserAlbums)
                }

                if userAlbums.isEmpty {
                    emptyRow
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.editMode, $editMode)
        .refreshable {
            if showSearchBar {
                dataManager.loadAlbums(showLoading: false)
            } else {
                showSearch()
            }
        }
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
            .accessibilityLabel(L10n.string("关闭搜索"))
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
        let progress = activeAlbumLoadingProgress

        return VStack(spacing: 14) {
            VStack(spacing: 8) {
                ProgressView(value: max(progress, 0.03))
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDelStyle.accent))
                    .frame(maxWidth: 220)
                    .clipShape(Capsule(style: .continuous))

                Text(progress > 0.01 ? L10n.percent(Int(progress * 100)) : L10n.string("准备中"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
            }

            VStack(spacing: 5) {
                Text(albumLoadingTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(albumLoadingMessage)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }
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

    private func sectionHeaderRow(_ title: String, count: Int) -> some View {
        Text("\(title) (\(count))")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(PhotoDelStyle.tertiaryText)
            .textCase(nil)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func albumRow(_ albumInfo: AlbumInfo, allowsActions: Bool) -> some View {
        Button(action: {
            openAlbum(albumInfo)
        }) {
            AlbumInfoRow(
                albumInfo: albumInfo,
                photoLibraryManager: dataManager.photoLibraryManager,
                showsChevron: editMode != .active
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if allowsActions, let collection = albumInfo.assetCollection {
                Button(role: .destructive) {
                    confirmDeleteAlbum(collection)
                } label: {
                    Label("删除", systemImage: "trash")
                }

                Button {
                    activeSheet = .edit(collection)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .tint(.gray)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var albumHeaderSubtitle: String {
        if !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
            return L10n.string("需要访问照片库权限")
        }

        let albumCount = dataManager.getUserAlbums().count
        if isLoadingPhotoLibraryForAlbums {
            return L10n.string("正在初始化照片库")
        }
        if dataManager.isLoadingAlbums && albumCount == 0 {
            return L10n.string("正在更新相册列表")
        }
        return L10n.string("\(albumCount) 个我的相册")
    }

    // MARK: - 计算属性
    private var isLoadingAlbums: Bool {
        dataManager.getUserAlbums().isEmpty &&
            (dataManager.isLoadingAlbums || isLoadingPhotoLibraryForAlbums)
    }

    private var isLoadingPhotoLibraryForAlbums: Bool {
        dataManager.photoLibraryManager.isLoading &&
            !dataManager.photoLibraryManager.hasLoadedPhotoLibrary
    }

    private var activeAlbumLoadingProgress: Double {
        let progress = isLoadingPhotoLibraryForAlbums
            ? dataManager.photoLibraryManager.loadingProgress
            : dataManager.albumLoadingProgress
        return min(max(progress, 0), 1)
    }

    private var albumLoadingTitle: String {
        isLoadingPhotoLibraryForAlbums ? L10n.string("正在初始化照片库") : L10n.string("正在更新相册列表")
    }

    private var albumLoadingMessage: String {
        isLoadingPhotoLibraryForAlbums
            ? L10n.string("首次初始化会读取照片数量和分类。完成后下次会优先使用本机缓存。")
            : L10n.string("正在统计相册数量和封面。")
    }

    private func filteredAlbums(_ albums: [AlbumInfo]) -> [AlbumInfo] {
        let sorted = sortedAlbums(albums)
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredUserAlbums: [AlbumInfo] {
        filteredAlbums(dataManager.getUserAlbums())
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
        }
        searchText = ""
    }

    private func sortedAlbums(_ albums: [AlbumInfo]) -> [AlbumInfo] {
        switch sortMode {
        case .custom:
            return albumsSortedByCustomOrder(albums)
        case .name:
            return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .count:
            return albums.sorted { $0.photosCount > $1.photosCount }
        }
    }

    private func albumsSortedByCustomOrder(_ albums: [AlbumInfo]) -> [AlbumInfo] {
        let order = customAlbumOrder
        guard !order.isEmpty else { return albums }

        let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return albums.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = ranks[lhs.element.id] ?? (order.count + lhs.offset)
                let rhsRank = ranks[rhs.element.id] ?? (order.count + rhs.offset)
                return lhsRank < rhsRank
            }
            .map(\.element)
    }

    private var customAlbumOrder: [String] {
        guard let data = customAlbumOrderData.data(using: .utf8),
              let order = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return order
    }

    private func saveCustomAlbumOrder(_ order: [String]) {
        guard let data = try? JSONEncoder().encode(order),
              let value = String(data: data, encoding: .utf8) else { return }
        customAlbumOrderData = value
    }

    private func toggleReordering() {
        guard sortMode == .custom else { return }
        HapticManager.impact(.light)
        withAnimation(.easeInOut(duration: 0.18)) {
            editMode = editMode == .active ? .inactive : .active
        }
    }

    private func moveUserAlbums(from source: IndexSet, to destination: Int) {
        guard sortMode == .custom, searchText.isEmpty else {
            showAlbumToast(L10n.string("请先清除搜索再调整顺序"), icon: "magnifyingglass", style: .warning)
            return
        }

        var albums = filteredUserAlbums
        albums.move(fromOffsets: source, toOffset: destination)
        saveCustomAlbumOrder(albums.map(\.id))
        HapticManager.impact(.light)
    }

    private func openAlbum(_ albumInfo: AlbumInfo) {
        guard albumInfo.photosCount > 0 else {
            HapticManager.impact(.light)
            showAlbumToast(L10n.string("这个相册还没有照片"), icon: "photo", style: .warning)
            return
        }

        HapticManager.impact(.light)
        selectedSwipeAlbum = albumInfo
        isShowingSwipeAlbum = true
    }

    private func confirmDeleteAlbum(_ album: PHAssetCollection) {
        guard album.assetCollectionType == .album else { return }
        pendingAlbumToDelete = album
        showingDeleteAlbumConfirmation = true
    }

    private func deleteAlbum(_ album: PHAssetCollection) {
        guard album.assetCollectionType == .album else { return }
        let albumID = album.localIdentifier

        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    HapticManager.notify(.success)
                    self.showAlbumToast(L10n.string("相册已删除"), icon: "trash", style: .positive)
                    self.dataManager.removeUserAlbum(id: albumID)
                } else if let error = error {
                    HapticManager.notify(.error)
                    self.showAlbumToast(L10n.string("删除失败，请再试一次"), icon: "exclamationmark.triangle", style: .warning)
                    albumsLogger.error("Failed to delete album: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func showAlbumToast(_ message: String, icon: String, style: PhotoDelToastStyle) {
        let toast = PhotoDelToast(message: message, icon: icon, style: style)
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

    private func albumToastView(_ toast: PhotoDelToast) -> some View {
        VStack {
            Spacer()
            PhotoDelToastView(toast: toast)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

}

private enum AlbumSheet: Identifiable {
    case create
    case edit(PHAssetCollection)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let album):
            return "edit-\(album.localIdentifier)"
        }
    }
}

private enum AlbumSortMode: String, CaseIterable, Identifiable {
    case custom
    case name
    case count

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom:
            return L10n.string("自定义")
        case .name:
            return L10n.string("名称")
        case .count:
            return L10n.string("数量")
        }
    }

    var icon: String {
        switch self {
        case .custom:
            return "line.3.horizontal"
        case .name:
            return "textformat"
        case .count:
            return "number"
        }
    }
}

// MARK: - 相册信息行
struct AlbumInfoRow: View {
    let albumInfo: AlbumInfo
    let photoLibraryManager: PhotoLibraryManager
    var showsChevron = true

    @State private var thumbnailImage: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        rowContent
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            loadAlbumThumbnail()
        }
        .onDisappear {
            if let requestID { photoLibraryManager.cancelImageRequest(requestID) }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Group {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(PhotoDelStyle.elevatedSurface)
                            .frame(width: 48, height: 48)

                        Image(systemName: albumInfo.type.icon)
                            .font(.system(size: 18, weight: .medium))
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

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .photoDelCard(radius: 14)
    }

    private func loadAlbumThumbnail() {
        if let thumbnailAsset = albumInfo.thumbnailAsset {
            requestID = photoLibraryManager.loadImage(for: thumbnailAsset, size: CGSize(width: 150, height: 150)) { image in
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
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
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

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(PhotoDelStyle.warning)
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
                        .disabled(albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(PhotoDelStyle.secondaryText)
                }
            }
        }
    }

    private func createAlbum() {
        let trimmedName = albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isCreating = true
        var createdAlbumIdentifier: String?

        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: trimmedName)
            createdAlbumIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
        }) { success, error in
            DispatchQueue.main.async {
                self.isCreating = false
                if success {
                    self.dataManager.insertCreatedUserAlbum(withIdentifier: createdAlbumIdentifier)
                    self.dismiss()
                } else if let error = error {
                    albumsLogger.error("Failed to create album: \(error.localizedDescription, privacy: .public)")
                    self.errorMessage = L10n.string("创建相册失败，请再试一次")
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
    @State private var errorMessage: String?

    init(album: PHAssetCollection) {
        self.album = album
        self._newName = State(initialValue: album.localizedTitle ?? "")
    }

    var body: some View {
        NavigationStack {
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

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(PhotoDelStyle.warning)
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
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUpdating)

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(PhotoDelStyle.secondaryText)
                }
            }
        }
    }

    private func updateAlbum() {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, album.assetCollectionType == .album else { return }

        isUpdating = true
        let albumID = album.localIdentifier

        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest(for: album)
            request?.title = trimmedName
        }) { success, error in
            DispatchQueue.main.async {
                self.isUpdating = false
                if success {
                    self.dataManager.renameUserAlbum(id: albumID, title: trimmedName)
                    self.dismiss()
                } else if let error = error {
                    albumsLogger.error("Failed to update album: \(error.localizedDescription, privacy: .public)")
                    self.errorMessage = L10n.string("更新相册失败，请再试一次")
                }
            }
        }
    }
}

#Preview {
    AlbumsView()
        .environmentObject(DataManager())
}
