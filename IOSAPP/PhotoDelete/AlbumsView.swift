//
//  AlbumsView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import SwiftUI
import Photos
import OSLog
#if canImport(UIKit)
import UIKit
#endif

private let albumsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "PhotoDelete",
    category: "Albums"
)

struct AlbumsView: View {
    @EnvironmentObject var dataManager: DataManager
    @AppStorage(AppConstants.customAlbumOrderKey) private var customAlbumOrderData = "[]"
    @AppStorage(AppConstants.hasDismissedAlbumSwipeHintKey) private var hasDismissedAlbumSwipeHint = false
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var activeSheet: AlbumSheet?
    @State private var showSearchBar = false
    @State private var sortMode: AlbumSortMode = .custom
    @State private var editMode: EditMode = .inactive
    @State private var pendingAlbumToDelete: PHAssetCollection?
    @State private var showingDeleteAlbumConfirmation = false
    @State private var albumToast: PhotoDeleteToast?
    @State private var albumProgressByID: [String: AlbumProgressSnapshot] = [:]
    @State private var albumProgressGeneration = 0

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                PhotoDeleteScreenBackground()

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
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AlbumNavigationDestination.self) { destination in
                switch destination {
                case .swipeAlbum(let selectedSwipeAlbum):
                    SwipePhotoView(selectedCategory: nil, selectedTimeGroup: nil, selectedAlbumInfo: selectedSwipeAlbum)
                        .environmentObject(dataManager)
                }
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
            refreshAlbumProgress()
        }
        .onChange(of: dataManager.userAlbums.count) { _ in
            refreshAlbumProgress()
        }
        .onChange(of: dataManager.reviewedAssetIDs) { _ in
            refreshAlbumProgress()
        }
    }

    // MARK: - 顶部区域
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string("相册"))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(albumHeaderSubtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(dataManager.photoLibraryManager.hasPhotoLibraryAccess ? PhotoDeleteStyle.secondaryText : PhotoDeleteStyle.accent)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
                    Label(L10n.string("排序"), systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(PhotoDeleteStyle.elevatedSurface))
                }
                .menuStyle(.button)
                .accessibilityLabel(L10n.string("排序"))

                Button {
                    HapticManager.impact(.light)
                    activeSheet = .create
                } label: {
                    Label(L10n.string("创建相册"), systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryButtonText)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(PhotoDeleteStyle.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("创建相册"))
            }
        }
        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 权限授权区域
    private var authorizationSection: some View {
        VStack {
            Spacer()
            PhotoAuthorizationCard(
                subtitle: L10n.string("需要访问您的照片库来管理相册。\(AppConstants.privacyShortText)"),
                onRequestAccess: { dataManager.requestPhotoLibraryAccess() }
            )
            .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
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
                    if shouldShowAlbumSwipeHint {
                        AlbumSwipeHintRow {
                            hasDismissedAlbumSwipeHint = true
                        }
                    }

                    Section {
                        ForEach(userAlbums) { albumInfo in
                            albumRow(albumInfo, allowsActions: true)
                        }
                        .onMove(perform: moveUserAlbums)
                    }
                }

                if userAlbums.isEmpty {
                    emptyRow
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.editMode, $editMode)
        .photoDeleteAlbumListTopMargin()
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
                .foregroundColor(PhotoDeleteStyle.secondaryText)

            TextField(L10n.string("搜索相册"), text: $searchText)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .submitLabel(.search)

            Button(action: hideSearch) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.tertiaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("关闭搜索"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                .fill(PhotoDeleteStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                )
        )
        .listRowInsets(EdgeInsets(top: 4, leading: PhotoDeleteStyle.screenHorizontalPadding, bottom: 10, trailing: PhotoDeleteStyle.screenHorizontalPadding))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var loadingRow: some View {
        let progress = activeAlbumLoadingProgress

        return VStack(spacing: 14) {
            VStack(spacing: 8) {
                ProgressView(value: max(progress, 0.03))
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    .frame(maxWidth: 220)
                    .clipShape(Capsule(style: .continuous))

                Text(progress > 0.01 ? L10n.percent(Int(progress * 100)) : L10n.string("准备中"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.tertiaryText)
            }

            VStack(spacing: 5) {
                Text(albumLoadingTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(albumLoadingMessage)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .listRowInsets(EdgeInsets(top: 0, leading: PhotoDeleteStyle.screenHorizontalPadding, bottom: 0, trailing: PhotoDeleteStyle.screenHorizontalPadding))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var emptyRow: some View {
        VStack(spacing: 18) {
            Image(systemName: searchText.isEmpty ? "photo.stack" : "magnifyingglass")
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.secondaryText)

            VStack(spacing: 6) {
                Text(searchText.isEmpty ? L10n.string("还没有相册") : L10n.string("没有找到相册"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(searchText.isEmpty ? L10n.string("可以点右上角加号创建一个新相册。") : L10n.string("换个关键词试试。"))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 58)
        .listRowInsets(EdgeInsets(top: 0, leading: PhotoDeleteStyle.screenHorizontalPadding, bottom: 0, trailing: PhotoDeleteStyle.screenHorizontalPadding))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func albumRow(_ albumInfo: AlbumInfo, allowsActions: Bool) -> some View {
        let editableAlbum = editableAssetCollection(for: albumInfo, allowsActions: allowsActions)

        return Button(action: {
            openAlbum(albumInfo)
        }) {
            AlbumInfoRow(
                albumInfo: albumInfo,
                photoLibraryManager: dataManager.photoLibraryManager,
                progress: albumProgressByID[albumInfo.id],
                showsChevron: editMode != .active
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let editableAlbum {
                Button(role: .destructive) {
                    confirmDeleteAlbum(editableAlbum)
                } label: {
                    Label(L10n.string("删除"), systemImage: "trash")
                }
                .tint(PhotoDeleteStyle.destructive)

                Button {
                    activeSheet = .edit(editableAlbum)
                } label: {
                    Label(L10n.string("编辑"), systemImage: "pencil")
                }
                .tint(PhotoDeleteStyle.accent)
            }
        }
        .listRowSeparatorTint(PhotoDeleteStyle.hairline)
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
        return L10n.string("\(albumCount) 个相册")
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

    private var shouldShowAlbumSwipeHint: Bool {
        !hasDismissedAlbumSwipeHint &&
            searchText.isEmpty &&
            editMode != .active
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

    private func refreshAlbumProgress() {
        let albums = dataManager.getUserAlbums()
        let reviewedAssetIDs = dataManager.reviewedAssetIDs
        albumProgressGeneration += 1
        let generation = albumProgressGeneration

        DispatchQueue.global(qos: .utility).async {
            var progressByID: [String: AlbumProgressSnapshot] = [:]
            for album in albums {
                progressByID[album.id] = Self.albumProgressSnapshot(
                    for: album,
                    reviewedAssetIDs: reviewedAssetIDs
                )
            }

            DispatchQueue.main.async {
                guard albumProgressGeneration == generation else { return }
                albumProgressByID = progressByID
            }
        }
    }

    private static func albumProgressSnapshot(
        for albumInfo: AlbumInfo,
        reviewedAssetIDs: Set<String>
    ) -> AlbumProgressSnapshot {
        guard albumInfo.photosCount > 0 else {
            return AlbumProgressSnapshot(totalCount: 0, reviewedCount: 0)
        }

        guard let assetCollection = albumInfo.assetCollection else {
            return AlbumProgressSnapshot(totalCount: albumInfo.photosCount, reviewedCount: 0)
        }

        let fetchOptions = PHFetchOptions()
        let assets = PHAsset.fetchAssets(in: assetCollection, options: fetchOptions)
        var reviewedCount = 0
        assets.enumerateObjects { asset, _, _ in
            if reviewedAssetIDs.contains(asset.localIdentifier) {
                reviewedCount += 1
            }
        }

        return AlbumProgressSnapshot(
            totalCount: assets.count,
            reviewedCount: reviewedCount
        )
    }

    private func openAlbum(_ albumInfo: AlbumInfo) {
        guard albumInfo.photosCount > 0 else {
            HapticManager.impact(.light)
            showAlbumToast(L10n.string("这个相册还没有照片"), icon: "photo", style: .warning)
            return
        }

        HapticManager.impact(.light)
        navigationPath.append(AlbumNavigationDestination.swipeAlbum(albumInfo))
    }

    private func editableAssetCollection(
        for albumInfo: AlbumInfo,
        allowsActions: Bool
    ) -> PHAssetCollection? {
        guard allowsActions,
              let collection = albumInfo.assetCollection,
              collection.assetCollectionType == .album else {
            return nil
        }
        return collection
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

    private func showAlbumToast(_ message: String, icon: String, style: PhotoDeleteToastStyle) {
        let toast = PhotoDeleteToast(message: message, icon: icon, style: style)
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

    private func albumToastView(_ toast: PhotoDeleteToast) -> some View {
        VStack {
            Spacer()
            PhotoDeleteToastView(toast: toast)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

}

private extension View {
    @ViewBuilder
    func photoDeleteAlbumListTopMargin() -> some View {
        if #available(iOS 17.0, *) {
            contentMargins(.top, 8, for: .scrollContent)
        } else {
            self
        }
    }
}

private struct AlbumSwipeHintRow: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.draw")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .frame(width: 24, height: 24)

            Text(L10n.string("左滑相册可编辑或删除"))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Text(L10n.string("知道了"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }
}

enum AlbumNavigationDestination: Hashable {
    case swipeAlbum(AlbumInfo)

    static func == (lhs: AlbumNavigationDestination, rhs: AlbumNavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.swipeAlbum(let lhsAlbum), .swipeAlbum(let rhsAlbum)):
            return lhsAlbum.id == rhsAlbum.id
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .swipeAlbum(let album):
            hasher.combine("swipeAlbum")
            hasher.combine(album.id)
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
struct AlbumProgressSnapshot: Equatable {
    let totalCount: Int
    let reviewedCount: Int

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return min(Double(reviewedCount) / Double(totalCount), 1)
    }

    var displayText: String? {
        guard totalCount > 0 else { return nil }
        return L10n.percent(Int((progress * 100).rounded()))
    }

    var tint: Color {
        if progress >= 1 {
            return PhotoDeleteStyle.positive
        }
        if progress > 0 {
            return PhotoDeleteStyle.accent
        }
        return PhotoDeleteStyle.tertiaryText
    }
}

struct AlbumInfoRow: View {
    let albumInfo: AlbumInfo
    let photoLibraryManager: PhotoLibraryManager
    let progress: AlbumProgressSnapshot?
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
        HStack(spacing: 9) {
            Group {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(PhotoDeleteStyle.elevatedSurface)
                            .frame(width: 36, height: 36)

                        Image(systemName: albumInfo.type.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(albumIconTint)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(albumInfo.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)

                Text(L10n.photoCount(albumInfo.photosCount))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            Spacer()

            if let progressText {
                Text(progressText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(progress?.tint ?? PhotoDeleteStyle.tertiaryText)
                    .monospacedDigit()
                    .accessibilityLabel(L10n.string("照片数据整理进度"))
                    .accessibilityValue(progressText)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.tertiaryText)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    private func loadAlbumThumbnail() {
        if let thumbnailAsset = albumInfo.thumbnailAsset {
            requestID = photoLibraryManager.loadImage(for: thumbnailAsset, size: CGSize(width: 120, height: 120)) { image in
                self.thumbnailImage = image
            }
        }
    }

    private var albumIconTint: Color {
        switch albumInfo.type {
        case .favorites:
            return PhotoDeleteStyle.iconTint(for: "favorite")
        case .videos:
            return PhotoDeleteStyle.iconTint(for: "video")
        case .livePhotos:
            return PhotoDeleteStyle.iconTint(for: "livephoto")
        default:
            return PhotoDeleteStyle.accent
        }
    }

    private var progressText: String? {
        progress?.displayText
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
                PhotoDeleteScreenBackground()

                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        Image(systemName: "plus.rectangle.on.folder")
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(PhotoDeleteStyle.accent)

                        Text(L10n.string("创建新相册"))
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.primaryText)
                    }

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("相册名称"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)

                            TextField(L10n.string("输入相册名称"), text: $albumName)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.primaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                                        .fill(PhotoDeleteStyle.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                                                .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                                        )
                                )
                        }

                        Text(L10n.string("简洁的相册名称，如\"旅行\"、\"家庭\"等"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                            .multilineTextAlignment(.leading)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(PhotoDeleteStyle.warning)
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

                                Text(isCreating ? L10n.string("创建中...") : L10n.string("创建相册"))
                            }
                        }
                        .photoDeletePrimaryButton()
                        .disabled(albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)

                        Button(action: { dismiss() }) {
                            Text(L10n.string("取消"))
                        }
                        .photoDeleteSecondaryButton()
                    }

                    Spacer()
                }
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, 40)
            }
            .navigationTitle(L10n.string("创建相册"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("取消")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
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
                PhotoDeleteScreenBackground()

                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(PhotoDeleteStyle.accent)

                        Text(L10n.string("编辑相册"))
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.primaryText)
                    }

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("相册名称"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)

                            TextField(L10n.string("输入相册名称"), text: $newName)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.primaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                                        .fill(PhotoDeleteStyle.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                                                .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                                        )
                                )
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(PhotoDeleteStyle.warning)
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

                                Text(isUpdating ? L10n.string("更新中...") : L10n.string("保存更改"))
                            }
                        }
                        .photoDeletePrimaryButton()
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUpdating)

                        Button(action: { dismiss() }) {
                            Text(L10n.string("取消"))
                        }
                        .photoDeleteSecondaryButton()
                    }

                    Spacer()
                }
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, 40)
            }
            .navigationTitle(L10n.string("编辑相册"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("取消")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
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
