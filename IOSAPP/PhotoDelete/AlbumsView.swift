//
//  AlbumsView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import Combine
import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

enum EmptyAlbumCleanupPlanner {
    static func cleanupCandidates(
        from albums: [AlbumInfo],
        canDelete: (AlbumInfo) -> Bool
    ) -> [AlbumInfo] {
        albums.filter { album in
            album.type == .userCreated &&
                album.photosCount == 0 &&
                canDelete(album)
        }
    }
}

/// Lightweight, equatable row model so List rows only rebuild when display data changes.
private struct AlbumListRowModel: Identifiable, Equatable {
    let id: String
    let title: String
    let photosCount: Int
    let type: AlbumType
    let thumbnailAssetID: String?
    let canEdit: Bool

    static func == (lhs: AlbumListRowModel, rhs: AlbumListRowModel) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.photosCount == rhs.photosCount
            && lhs.type == rhs.type
            && lhs.thumbnailAssetID == rhs.thumbnailAssetID
            && lhs.canEdit == rhs.canEdit
    }
}

struct AlbumsView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppConstants.hasDismissedAlbumSwipeHintKey) private var hasDismissedAlbumSwipeHint = false
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var activeSheet: AlbumSheet?
    @State private var sortMode: AlbumSortMode = .custom
    @State private var editMode: EditMode = .inactive
    @State private var albumToast: PhotoDeleteToast?
    @State private var displayedRows: [AlbumListRowModel] = []
    @State private var albumsByID: [String: AlbumInfo] = [:]
    @State private var displayedAlbumCount = 0

    var body: some View {
        NavigationStack(path: $navigationPath) {
            rootContent
                .frame(maxWidth: PhotoDeleteAdaptiveLayout.listContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                .frame(maxWidth: .infinity)
                .background {
                    PhotoDeleteScreenBackground()
                }
                .overlay {
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
                                albumActionsMenu
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
            case .deleteEmpty(let albums):
                DeleteEmptyAlbumsView(albums: albums)
                    .environmentObject(dataManager)
            }
        }
        .onChange(of: sortMode) { mode in
            guard mode != .custom else { return }
            editMode = .inactive
            rebuildDisplayedRows()
        }
        .onChange(of: searchText) { _ in
            rebuildDisplayedRows()
        }
        .onReceive(dataManager.$userAlbums) { _ in
            rebuildDisplayedRows()
        }
        .onAppear {
            dataManager.loadAlbumsIfNeeded()
            rebuildDisplayedRows()
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

    private var albumActionsMenu: some View {
        Menu {
            Button(action: presentEmptyAlbumCleanup) {
                Label(L10n.string("删除空相册"), systemImage: "folder.badge.minus")
            }
        } label: {
            Label(L10n.string("相册操作"), systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PhotoDeleteStyle.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("相册操作"))
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

    private func presentEmptyAlbumCleanup() {
        let refreshedAlbums = dataManager.getUserAlbums().compactMap { album in
            dataManager.currentUserAlbumInfo(for: album)
        }
        let emptyAlbums = EmptyAlbumCleanupPlanner.cleanupCandidates(from: refreshedAlbums) { album in
            guard let collection = album.assetCollection else { return false }
            return collection.assetCollectionType == .album && collection.canPerform(.delete)
        }

        guard !emptyAlbums.isEmpty else {
            HapticManager.impact(.light)
            showAlbumToast(L10n.string("没有空相册"), icon: "checkmark.circle", style: .positive)
            return
        }

        HapticManager.impact(.light)
        activeSheet = .deleteEmpty(emptyAlbums)
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
        List {
            if isLoadingAlbums {
                Section {
                    loadingRow
                } header: {
                    albumCountHeader
                }
            } else if displayedRows.isEmpty {
                Section {
                    emptyRow
                } header: {
                    albumCountHeader
                }
            } else {
                // Keep count in the section header (not its own Section) so insetGrouped
                // does not leave a large empty gap under "N 个相册".
                Section {
                    if shouldShowAlbumSwipeHint {
                        AlbumSwipeHintRow {
                            hasDismissedAlbumSwipeHint = true
                        }
                    }

                    if editMode == .active {
                        ForEach(displayedRows) { row in
                            albumRow(row)
                        }
                        .onMove(perform: moveUserAlbums)
                    } else {
                        // Avoid always-on reorder handlers while scrolling.
                        ForEach(displayedRows) { row in
                            albumRow(row)
                        }
                    }
                } header: {
                    albumCountHeader
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            dataManager.loadAlbums(showLoading: false)
        }
    }

    private var albumCountHeader: some View {
        Text(albumHeaderSubtitle)
            .font(.subheadline)
            .foregroundStyle(PhotoDeleteStyle.secondaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textCase(nil)
            .padding(.bottom, 2)
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
        .padding(.vertical, 28)
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

    private func albumRow(_ row: AlbumListRowModel) -> some View {
        Button {
            openAlbum(id: row.id)
        } label: {
            AlbumInfoRow(
                id: row.id,
                title: row.title,
                photosCount: row.photosCount,
                type: row.type,
                thumbnailAssetID: row.thumbnailAssetID,
                photoLibraryManager: dataManager.photoLibraryManager,
                showsChevron: editMode != .active
            )
            .equatable()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.string("点按整理这个相册"))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if row.canEdit {
                Button(role: .destructive) {
                    deleteAlbum(id: row.id)
                } label: {
                    Label(L10n.string("删除"), systemImage: "trash")
                }
                .tint(PhotoDeleteStyle.destructive)

                Button {
                    editAlbum(id: row.id)
                } label: {
                    Label(L10n.string("编辑"), systemImage: "pencil")
                }
                .tint(PhotoDeleteStyle.accent)
            }
        }
        .listRowBackground(PhotoDeleteStyle.surface)
        .listRowSeparatorTint(PhotoDeleteStyle.hairline)
    }

    private var albumHeaderSubtitle: String {
        if isLoadingPhotoLibraryForAlbums {
            return L10n.string("正在初始化照片库")
        }
        if dataManager.isLoadingAlbums && displayedAlbumCount == 0 {
            return L10n.string("正在更新相册列表")
        }
        return L10n.string("\(displayedAlbumCount) 个相册")
    }

    // MARK: - 计算属性
    private var isLoadingAlbums: Bool {
        displayedRows.isEmpty &&
            (dataManager.isLoadingAlbums || isLoadingPhotoLibraryForAlbums) &&
            searchText.isEmpty
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
            ? L10n.string("正在读取相册数量和封面，完成后会显示你的相册。")
            : L10n.string("正在统计相册数量和封面。")
    }

    private var shouldShowAlbumSwipeHint: Bool {
        !hasDismissedAlbumSwipeHint &&
            searchText.isEmpty &&
            editMode != .active
    }

    // MARK: - 方法
    private func rebuildDisplayedRows() {
        let sourceAlbums = dataManager.getUserAlbums()
        displayedAlbumCount = sourceAlbums.count

        let sorted = sortedAlbums(sourceAlbums)
        let filtered: [AlbumInfo]
        if searchText.isEmpty {
            filtered = sorted
        } else {
            filtered = sorted.filter { $0.title.localizedStandardContains(searchText) }
        }

        var nextAlbumsByID: [String: AlbumInfo] = [:]
        nextAlbumsByID.reserveCapacity(filtered.count)

        let rows: [AlbumListRowModel] = filtered.map { album in
            nextAlbumsByID[album.id] = album
            let canEdit: Bool = {
                guard let collection = album.assetCollection,
                      collection.assetCollectionType == .album else {
                    return false
                }
                // Defer expensive canPerform checks: album type is enough for swipe affordance;
                // Photos will refuse the write if unsupported.
                return true
            }()

            return AlbumListRowModel(
                id: album.id,
                title: album.title,
                photosCount: album.photosCount,
                type: album.type,
                thumbnailAssetID: album.thumbnailAsset?.localIdentifier,
                canEdit: canEdit && album.type == .userCreated
            )
        }

        // Avoid redundant state writes that force List to re-diff every unrelated DataManager publish.
        if rows != displayedRows {
            displayedRows = rows
        }
        albumsByID = nextAlbumsByID
    }

    private func sortedAlbums(_ albums: [AlbumInfo]) -> [AlbumInfo] {
        switch sortMode {
        case .custom:
            return DataManager.albumsSortedByCustomOrder(albums, customOrder: dataManager.customAlbumOrderForDisplay)
        case .name:
            return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .count:
            return albums.sorted { $0.photosCount > $1.photosCount }
        }
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

    private func moveUserAlbums(from source: IndexSet, to destination: Int) {
        guard sortMode == .custom, searchText.isEmpty else {
            showAlbumToast(L10n.string("请先清除搜索再调整顺序"), icon: "magnifyingglass", style: .warning)
            return
        }

        var rows = displayedRows
        rows.move(fromOffsets: source, toOffset: destination)
        displayedRows = rows
        dataManager.saveCustomAlbumOrder(rows.map(\.id))
        HapticManager.impact(.light)
    }

    private func openAlbum(id: String) {
        guard let albumInfo = albumsByID[id] ?? dataManager.userAlbums.first(where: { $0.id == id }) else {
            HapticManager.impact(.light)
            showAlbumToast(L10n.string("这个相册已不存在，列表已更新"), icon: "arrow.clockwise", style: .warning)
            rebuildDisplayedRows()
            return
        }

        guard let currentAlbumInfo = dataManager.currentUserAlbumInfo(for: albumInfo) else {
            HapticManager.impact(.light)
            showAlbumToast(L10n.string("这个相册已不存在，列表已更新"), icon: "arrow.clockwise", style: .warning)
            rebuildDisplayedRows()
            return
        }

        guard currentAlbumInfo.photosCount > 0 else {
            HapticManager.impact(.light)
            showAlbumToast(L10n.string("这个相册还没有照片"), icon: "photo", style: .warning)
            return
        }

        HapticManager.impact(.light)
        navigationPath.append(AlbumNavigationDestination.swipeAlbum(currentAlbumInfo))
    }

    private func editAlbum(id: String) {
        guard let albumInfo = albumsByID[id] ?? dataManager.userAlbums.first(where: { $0.id == id }),
              let currentAlbumInfo = dataManager.currentUserAlbumInfo(for: albumInfo),
              let album = currentAlbumInfo.assetCollection else {
            HapticManager.impact(.light)
            showAlbumToast(L10n.string("这个相册已不存在，列表已更新"), icon: "arrow.clockwise", style: .warning)
            rebuildDisplayedRows()
            return
        }

        activeSheet = .edit(album)
    }

    private func deleteAlbum(id: String) {
        guard let albumInfo = albumsByID[id] ?? dataManager.userAlbums.first(where: { $0.id == id }),
              let currentAlbumInfo = dataManager.currentUserAlbumInfo(for: albumInfo),
              let album = currentAlbumInfo.assetCollection else {
            HapticManager.impact(.light)
            showAlbumToast(L10n.string("这个相册已不存在，列表已更新"), icon: "arrow.clockwise", style: .warning)
            rebuildDisplayedRows()
            return
        }

        dataManager.deleteUserAlbum(album) { success in
            if success {
                HapticManager.notify(.success)
                self.showAlbumToast(L10n.string("相册已删除"), icon: "trash", style: .positive)
            } else {
                HapticManager.notify(.error)
                self.showAlbumToast(L10n.string("相册列表已更新，请再试一次"), icon: "arrow.clockwise", style: .warning)
            }
            self.rebuildDisplayedRows()
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
        .allowsHitTesting(false)
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
    case deleteEmpty([AlbumInfo])

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let album):
            return "edit-\(album.localIdentifier)"
        case .deleteEmpty(let albums):
            return "deleteEmpty-\(albums.map(\.id).joined(separator: "|"))"
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

private struct AlbumSwipeHintRow: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.draw")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("可在右上角排序里调整顺序"))
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
        .listRowBackground(PhotoDeleteStyle.surface)
        .listRowSeparator(.hidden)
    }
}

private final class ThumbnailRequestBox: @unchecked Sendable {
    var id: PHImageRequestID?
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

struct AlbumInfoRow: View, Equatable {
    let id: String
    let title: String
    let photosCount: Int
    let type: AlbumType
    let thumbnailAssetID: String?
    let photoLibraryManager: PhotoLibraryManager
    var progress: AlbumProgressSnapshot? = nil
    var showsChevron = true

    @State private var thumbnailImage: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var loadedThumbnailAssetID: String?

    private static let thumbnailPointSize: CGFloat = 36

    static func == (lhs: AlbumInfoRow, rhs: AlbumInfoRow) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.photosCount == rhs.photosCount
            && lhs.type == rhs.type
            && lhs.thumbnailAssetID == rhs.thumbnailAssetID
            && lhs.progress == rhs.progress
            && lhs.showsChevron == rhs.showsChevron
    }

    var body: some View {
        rowContent
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(title), \(L10n.photoCount(photosCount))")
            .task(id: thumbnailAssetID) {
                await loadAlbumThumbnail()
            }
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            albumThumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)

                Text(L10n.photoCount(photosCount))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            Spacer(minLength: 8)

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

    @ViewBuilder
    private var albumThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
                .frame(width: Self.thumbnailPointSize, height: Self.thumbnailPointSize)

            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.low)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.thumbnailPointSize, height: Self.thumbnailPointSize)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .transaction { $0.animation = nil }
            } else {
                Image(systemName: type.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(albumIconTint)
            }
        }
        .frame(width: Self.thumbnailPointSize, height: Self.thumbnailPointSize)
    }

    @MainActor
    private func loadAlbumThumbnail() async {
        guard let thumbnailAssetID else {
            thumbnailImage = nil
            loadedThumbnailAssetID = nil
            return
        }

        if loadedThumbnailAssetID == thumbnailAssetID, thumbnailImage != nil {
            return
        }

        cancelThumbnailRequest()

        let scale = UIScreen.main.scale
        let pixel = Self.thumbnailPointSize * scale
        let targetSize = CGSize(width: pixel, height: pixel)

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [thumbnailAssetID], options: nil)
        guard let asset = assets.firstObject else {
            thumbnailImage = nil
            loadedThumbnailAssetID = nil
            return
        }

        let requestBox = ThumbnailRequestBox()
        let manager = photoLibraryManager
        let image: UIImage? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                var hasResumed = false
                let resumeOnce: (UIImage?) -> Void = { image in
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: image)
                }

                let id = manager.loadAlbumListThumbnail(for: asset, size: targetSize) { image in
                    resumeOnce(image)
                }
                requestBox.id = id
                requestID = id
            }
        } onCancel: {
            if let id = requestBox.id {
                manager.cancelImageRequest(id)
            }
        }

        guard !Task.isCancelled else { return }
        if let image {
            thumbnailImage = image
            loadedThumbnailAssetID = thumbnailAssetID
        }
        requestID = nil
    }

    private func cancelThumbnailRequest() {
        if let requestID {
            photoLibraryManager.cancelImageRequest(requestID)
        }
        requestID = nil
    }

    private var albumIconTint: Color {
        switch type {
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
        guard dataManager.currentUserAlbumInfo(for: album) != nil else {
            errorMessage = L10n.string("这个相册已不存在，列表已更新")
            dismissAfterShowingMissingAlbumMessage()
            return
        }

        isUpdating = true
        dataManager.renameUserAlbum(album, title: trimmedName) { success in
            self.isUpdating = false
            if success {
                self.dismiss()
            } else if self.dataManager.currentUserAlbumInfo(for: album) == nil {
                self.errorMessage = L10n.string("这个相册已不存在，列表已更新")
                self.dismissAfterShowingMissingAlbumMessage()
            } else {
                self.errorMessage = L10n.string("更新相册失败，请再试一次")
            }
        }
    }

    private func dismissAfterShowingMissingAlbumMessage() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}

// MARK: - 删除空相册
struct DeleteEmptyAlbumsView: View {
    let albums: [AlbumInfo]

    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedAlbumIDs: Set<String>
    @State private var isDeleting = false
    @State private var processedAlbumCount = 0
    @State private var failedAlbumTitles: [String] = []

    init(albums: [AlbumInfo]) {
        self.albums = albums
        self._selectedAlbumIDs = State(initialValue: Set(albums.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        headerSection
                        albumSelectionSection
                        errorSection
                        actionButtons
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                    .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(L10n.string("删除空相册"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("取消")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .disabled(isDeleting)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            PhotoDeleteIconTile(
                icon: "folder.badge.minus",
                tint: PhotoDeleteStyle.destructive,
                size: 58,
                cornerRadius: 16
            )

            VStack(spacing: 6) {
                Text(String(format: L10n.string("发现 %lld 个空相册"), Int64(albums.count)))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .multilineTextAlignment(.center)

                Text(L10n.string("只会删除空相册，不会删除任何照片。"))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var albumSelectionSection: some View {
        VStack(spacing: 0) {
            ForEach(albums) { album in
                Button {
                    toggleSelection(for: album)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedAlbumIDs.contains(album.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(selectedAlbumIDs.contains(album.id) ? PhotoDeleteStyle.destructive : PhotoDeleteStyle.tertiaryText)
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(album.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)
                                .lineLimit(1)

                            Text(L10n.photoCount(album.photosCount))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                        }

                        Spacer()
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)

                if album.id != albums.last?.id {
                    Divider()
                        .background(PhotoDeleteStyle.hairline)
                        .padding(.leading, 52)
                }
            }
        }
        .photoDeleteCard()
    }

    @ViewBuilder
    private var errorSection: some View {
        if !failedAlbumTitles.isEmpty {
            Text(String(format: L10n.string("%lld 个相册删除失败，请稍后再试"), Int64(failedAlbumTitles.count)))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: deleteSelectedAlbums) {
                HStack(spacing: 8) {
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.primaryButtonText))
                            .scaleEffect(0.82)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                    }

                    Text(deleteButtonTitle)
                }
            }
            .photoDeleteDestructiveButton()
            .disabled(selectedAlbums.isEmpty || isDeleting)

            Button(action: { dismiss() }) {
                Text(L10n.string("取消"))
            }
            .photoDeleteSecondaryButton()
            .disabled(isDeleting)
        }
    }

    private var selectedAlbums: [AlbumInfo] {
        albums.filter { selectedAlbumIDs.contains($0.id) }
    }

    private var deleteButtonTitle: String {
        if isDeleting {
            return String(
                format: L10n.string("正在删除 %lld/%lld"),
                Int64(processedAlbumCount),
                Int64(selectedAlbums.count)
            )
        }
        return String(format: L10n.string("删除 %lld 个空相册"), Int64(selectedAlbums.count))
    }

    private func toggleSelection(for album: AlbumInfo) {
        guard !isDeleting else { return }
        if selectedAlbumIDs.contains(album.id) {
            selectedAlbumIDs.remove(album.id)
        } else {
            selectedAlbumIDs.insert(album.id)
        }
        HapticManager.impact(.light)
    }

    private func deleteSelectedAlbums() {
        let targets = selectedAlbums
        guard !targets.isEmpty, !isDeleting else { return }

        failedAlbumTitles = []
        processedAlbumCount = 0
        isDeleting = true

        deleteNextAlbum(targets, index: 0, failures: [])
    }

    private func deleteNextAlbum(_ targets: [AlbumInfo], index: Int, failures: [String]) {
        guard index < targets.count else {
            isDeleting = false
            if failures.isEmpty {
                HapticManager.notify(.success)
                dismiss()
            } else {
                HapticManager.notify(.error)
                failedAlbumTitles = failures
            }
            return
        }

        let album = targets[index]
        guard let currentAlbum = dataManager.currentUserAlbumInfo(for: album),
              currentAlbum.photosCount == 0,
              let collection = currentAlbum.assetCollection,
              collection.assetCollectionType == .album,
              collection.canPerform(.delete) else {
            processedAlbumCount += 1
            deleteNextAlbum(targets, index: index + 1, failures: failures + [album.title])
            return
        }

        dataManager.deleteUserAlbum(collection) { success in
            processedAlbumCount += 1
            deleteNextAlbum(
                targets,
                index: index + 1,
                failures: success ? failures : failures + [album.title]
            )
        }
    }
}

#Preview {
    AlbumsView()
        .environmentObject(DataManager())
}
