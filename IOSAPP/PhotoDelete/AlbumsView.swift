//
//  AlbumsView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

struct AlbumsView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppConstants.customAlbumOrderKey) private var customAlbumOrderData = "[]"
    @AppStorage(AppConstants.hasDismissedAlbumSwipeHintKey) private var hasDismissedAlbumSwipeHint = false
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var activeSheet: AlbumSheet?
    @State private var sortMode: AlbumSortMode = .custom
    @State private var editMode: EditMode = .inactive
    @State private var pendingAlbumToDelete: PHAssetCollection?
    @State private var albumToast: PhotoDeleteToast?
    @State private var albumProgressByID: [String: AlbumProgressSnapshot] = [:]
    @State private var albumProgressGeneration = 0

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                PhotoDeleteScreenBackground()

                rootContent
                .frame(maxWidth: PhotoDeleteAdaptiveLayout.listContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                .frame(maxWidth: .infinity)

                if let albumToast {
                    albumToastView(albumToast)
                }
            }
            .navigationTitle(L10n.string("相册"))
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Text(L10n.string("搜索相册"))
            )
            .toolbar {
                if dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if editMode == .active {
                            Button(L10n.string("完成"), action: toggleReordering)
                                .font(.body.weight(.semibold))
                        } else {
                            sortMenu
                            createAlbumButton
                        }
                    }
                }
            }
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

    @ViewBuilder
    private var rootContent: some View {
        if !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
            authorizationSection
        } else {
            albumsList
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker(L10n.string("排序"), selection: $sortMode) {
                ForEach(AlbumSortMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon).tag(mode)
                }
            }

            if sortMode == .custom {
                Button(action: toggleReordering) {
                    Label(L10n.string("调整顺序"), systemImage: "line.3.horizontal")
                }
            }
        } label: {
            Label(L10n.string("排序"), systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PhotoDeleteStyle.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("排序"))
    }

    private var albumTopSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            albumCountRow
        }
        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
        .padding(.top, PhotoDeleteStyle.rootContentTopSpacing)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
    }

    private var albumCountRow: some View {
        Text(albumHeaderSubtitle)
            .font(.subheadline)
            .foregroundStyle(PhotoDeleteStyle.secondaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var createAlbumButton: some View {
        Button(action: createAlbum) {
            Label(L10n.string("创建相册"), systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PhotoDeleteStyle.accent)
        }
        .accessibilityLabel(L10n.string("创建相册"))
    }

    private func createAlbum() {
        HapticManager.impact(.light)
        activeSheet = .create
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
            albumTopSection
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if isLoadingAlbums {
                loadingRow
            } else {
                if !userAlbums.isEmpty {
                    Section {
                        if shouldShowAlbumSwipeHint {
                            AlbumSwipeHintRow {
                                hasDismissedAlbumSwipeHint = true
                            }
                        }

                        ForEach(userAlbums) { albumInfo in
                            albumRow(albumInfo, allowsActions: true)
                        }
                        .onMove(perform: moveUserAlbums)
                    }

                } else {
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
        .photoDeleteAlbumListSectionSpacing()
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            dataManager.loadAlbums(showLoading: false)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 88)
        }
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
        Group {
            if #available(iOS 17.0, *) {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: searchText.isEmpty ? "photo.stack" : "magnifyingglass",
                    description: Text(emptyMessage)
                )
                .foregroundStyle(PhotoDeleteStyle.secondaryText)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: searchText.isEmpty ? "photo.stack" : "magnifyingglass")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)

                    VStack(spacing: 6) {
                        Text(emptyTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.primaryText)

                        Text(emptyMessage)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 58)
        .listRowInsets(EdgeInsets(top: 0, leading: PhotoDeleteStyle.screenHorizontalPadding, bottom: 0, trailing: PhotoDeleteStyle.screenHorizontalPadding))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var emptyTitle: String {
        searchText.isEmpty ? L10n.string("还没有相册") : L10n.string("没有找到相册")
    }

    private var emptyMessage: String {
        searchText.isEmpty ? L10n.string("可以点右上角加号创建一个新相册。") : L10n.string("换个关键词试试。")
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55)
                .onEnded { _ in
                    startReorderingFromAlbumRow()
                }
        )
        .accessibilityHint(L10n.string("点按整理这个相册，长按调整排序"))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let editableAlbum {
                Button(role: .destructive) {
                    pendingAlbumToDelete = editableAlbum
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
        .confirmationDialog(
            L10n.string("删除这个相册？"),
            isPresented: Binding(
                get: {
                    guard let editableAlbum else { return false }
                    return pendingAlbumToDelete?.localIdentifier == editableAlbum.localIdentifier
                },
                set: { isPresented in
                    if !isPresented {
                        pendingAlbumToDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.string("删除相册"), role: .destructive) {
                guard let editableAlbum else { return }
                deleteAlbum(editableAlbum)
                pendingAlbumToDelete = nil
            }
            Button(L10n.string("取消"), role: .cancel) {
                pendingAlbumToDelete = nil
            }
        } message: {
            Text(L10n.string("只会删除相册，不会删除相册里的照片。"))
        }
        .listRowSeparatorTint(PhotoDeleteStyle.hairline)
    }

    private var albumHeaderSubtitle: String {
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
        return sorted.filter { $0.title.localizedStandardContains(searchText) }
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
        if editMode != .active && !searchText.isEmpty {
            showAlbumToast(L10n.string("请先清除搜索再调整顺序"), icon: "magnifyingglass", style: .warning)
            return
        }

        HapticManager.impact(.light)
        withAnimation(.easeInOut(duration: 0.18)) {
            editMode = editMode == .active ? .inactive : .active
        }
    }

    private func startReorderingFromAlbumRow() {
        guard searchText.isEmpty else {
            showAlbumToast(L10n.string("请先清除搜索再调整顺序"), icon: "magnifyingglass", style: .warning)
            return
        }

        if sortMode != .custom {
            sortMode = .custom
        }

        guard editMode != .active else { return }
        HapticManager.impact(.light)
        withAnimation(.easeInOut(duration: 0.18)) {
            editMode = .active
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

    private func deleteAlbum(_ album: PHAssetCollection) {
        dataManager.deleteUserAlbum(album) { success in
            if success {
                HapticManager.notify(.success)
                self.showAlbumToast(L10n.string("相册已删除"), icon: "trash", style: .positive)
            } else {
                HapticManager.notify(.error)
                self.showAlbumToast(L10n.string("删除失败，请再试一次"), icon: "exclamationmark.triangle", style: .warning)
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
            contentMargins(.top, 0, for: .scrollContent)
        } else {
            self
        }
    }

    @ViewBuilder
    func photoDeleteAlbumListSectionSpacing() -> some View {
        if #available(iOS 17.0, *) {
            listSectionSpacing(10)
        } else {
            self
        }
    }
}

private struct AlbumSwipeHintRow: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.draw")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("长按相册可自定义排序"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(L10n.string("左滑相册可编辑或删除"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Text(L10n.string("知道了"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                                        .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.primaryButtonText))
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
                .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                .frame(maxWidth: .infinity)
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
        dataManager.createUserAlbum(named: trimmedName) { success in
            self.isCreating = false
            if success {
                self.dismiss()
            } else {
                self.errorMessage = L10n.string("创建相册失败，请再试一次")
            }
        }
    }
}

// MARK: - 编辑相册视图
struct EditAlbumView: View {
    let album: PHAssetCollection
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                                        .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.primaryButtonText))
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
                .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                .frame(maxWidth: .infinity)
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
        dataManager.renameUserAlbum(album, title: trimmedName) { success in
            self.isUpdating = false
            if success {
                self.dismiss()
            } else {
                self.errorMessage = L10n.string("更新相册失败，请再试一次")
            }
        }
    }
}

#Preview {
    AlbumsView()
        .environmentObject(DataManager())
}
