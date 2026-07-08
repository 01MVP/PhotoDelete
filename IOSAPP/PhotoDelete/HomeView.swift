//
//  HomeView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import SwiftUI

enum SwipeViewDestination: Hashable {
    case category(PhotoCategory)
    case timeGroup(String)
    case album(AlbumInfo)
    case random(PhotoRandomReviewScope)
    case timeBrowser
    case locationBrowser
    case historicalToday
    case location(String)
    case period(AdvancedTimeScope, Date)

    static func == (lhs: SwipeViewDestination, rhs: SwipeViewDestination) -> Bool {
        switch (lhs, rhs) {
        case (.category(let lhsCategory), .category(let rhsCategory)):
            return lhsCategory == rhsCategory
        case (.timeGroup(let lhsTimeGroup), .timeGroup(let rhsTimeGroup)):
            return lhsTimeGroup == rhsTimeGroup
        case (.album(let lhsAlbum), .album(let rhsAlbum)):
            return lhsAlbum.id == rhsAlbum.id
        case (.random(let lhsScope), .random(let rhsScope)):
            return lhsScope == rhsScope
        case (.timeBrowser, .timeBrowser):
            return true
        case (.locationBrowser, .locationBrowser):
            return true
        case (.historicalToday, .historicalToday):
            return true
        case (.location(let lhsGroupID), .location(let rhsGroupID)):
            return lhsGroupID == rhsGroupID
        case (.period(let lhsScope, let lhsDate), .period(let rhsScope, let rhsDate)):
            return lhsScope == rhsScope && lhsDate == rhsDate
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .category(let category):
            hasher.combine("category")
            hasher.combine(category)
        case .timeGroup(let timeGroup):
            hasher.combine("timeGroup")
            hasher.combine(timeGroup)
        case .album(let album):
            hasher.combine("album")
            hasher.combine(album.id)
        case .random(let scope):
            hasher.combine("random")
            hasher.combine(scope)
        case .timeBrowser:
            hasher.combine("timeBrowser")
        case .locationBrowser:
            hasher.combine("locationBrowser")
        case .historicalToday:
            hasher.combine("historicalToday")
        case .location(let groupID):
            hasher.combine("location")
            hasher.combine(groupID)
        case .period(let scope, let date):
            hasher.combine("period")
            hasher.combine(scope)
            hasher.combine(date)
        }
    }
}

enum HomeLibraryContentState: Equatable {
    case needsAuthorization
    case preparing
    case available
    case empty

    static func resolve(
        hasPhotoLibraryAccess: Bool,
        isPreparingLibrary: Bool,
        isLoadingPhotoLibrary: Bool,
        hasLoadedPhotoLibrary: Bool,
        totalPhotosCount: Int
    ) -> HomeLibraryContentState {
        guard hasPhotoLibraryAccess else { return .needsAuthorization }
        if totalPhotosCount > 0 { return .available }
        if isPreparingLibrary || isLoadingPhotoLibrary || !hasLoadedPhotoLibrary { return .available }
        return .empty
    }
}

enum HomeCategoryCountDetailResolver {
    static func shouldShowLibraryLoading(
        category _: PhotoCategory,
        count: Int,
        isPreparingLibrary: Bool,
        isLoadingPhotoLibrary: Bool
    ) -> Bool {
        if isPreparingLibrary && isLoadingPhotoLibrary {
            return true
        }

        return count == 0 && isLoadingPhotoLibrary
    }
}

struct HomeView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppConstants.hasSeenIntroKey) private var hasSeenPhotoDeleteIntro = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                let usesExpandedLayout = PhotoDeleteAdaptiveLayout.prefersExpandedContent(
                    in: geometry.size,
                    horizontalSizeClass: horizontalSizeClass
                )

                ZStack {
                    PhotoDeleteScreenBackground()

                    ScrollView {
                        homeContent(isLandscape: usesExpandedLayout)
                            .padding(
                                .horizontal,
                                PhotoDeleteAdaptiveLayout.homeHorizontalPadding(
                                    in: geometry.size,
                                    horizontalSizeClass: horizontalSizeClass
                                )
                            )
                            .padding(
                                .top,
                                PhotoDeleteAdaptiveLayout.homeTopPadding(
                                    in: geometry.size,
                                    horizontalSizeClass: horizontalSizeClass
                                )
                            )
                            .padding(.bottom, 112)
                            .frame(
                                maxWidth: PhotoDeleteAdaptiveLayout.homeContentMaxWidth(
                                    in: geometry.size,
                                    horizontalSizeClass: horizontalSizeClass
                                )
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(L10n.string("整理"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SwipeViewDestination.self) { destination in
                switch destination {
                case .category(let category):
                    SwipePhotoView(selectedCategory: category, selectedTimeGroup: nil, selectedAlbumInfo: nil)
                        .environmentObject(dataManager)
                case .timeGroup(let timeGroup):
                    SwipePhotoView(selectedCategory: nil, selectedTimeGroup: timeGroup, selectedAlbumInfo: nil)
                        .environmentObject(dataManager)
                case .album(let albumInfo):
                    SwipePhotoView(selectedCategory: nil, selectedTimeGroup: nil, selectedAlbumInfo: albumInfo)
                        .environmentObject(dataManager)
                case .random(let scope):
                    SwipePhotoView(
                        selectedCategory: nil,
                        selectedTimeGroup: nil,
                        selectedAlbumInfo: nil,
                        randomReviewScope: scope
                    )
                    .environmentObject(dataManager)
                case .timeBrowser:
                    TimeOrganizeView()
                        .environmentObject(dataManager)
                case .locationBrowser:
                    LocationOrganizeView()
                        .environmentObject(dataManager)
                case .historicalToday:
                    SwipePhotoView(
                        selectedCategory: nil,
                        selectedTimeGroup: nil,
                        selectedAlbumInfo: nil,
                        selectedHistoricalToday: true
                    )
                    .environmentObject(dataManager)
                case .location(let groupID):
                    SwipePhotoView(
                        selectedCategory: nil,
                        selectedTimeGroup: nil,
                        selectedAlbumInfo: nil,
                        selectedLocationGroupID: groupID
                    )
                    .environmentObject(dataManager)
                case .period(let scope, let intervalStart):
                    SwipePhotoView(
                        selectedCategory: nil,
                        selectedTimeGroup: nil,
                        selectedAlbumInfo: nil,
                        selectedDate: intervalStart,
                        selectedAdvancedTimeScope: scope
                    )
                    .environmentObject(dataManager)
                }
            }
        }
        .onAppear {
            dataManager.loadAlbumsIfNeeded()
        }
    }

    @ViewBuilder
    private func homeContent(isLandscape: Bool) -> some View {
        if libraryContentState != .needsAuthorization {
            if isLandscape {
                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 18) {
                        introSection(isCompact: true)
                        primaryOrganizeSection(isCompact: true)
                        locationOrganizeSection
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 18) {
                        secondaryEntrySection
                        timelineSection
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: PhotoDeleteStyle.sectionSpacing) {
                    introSection(isCompact: false)
                    primaryOrganizeSection(isCompact: false)
                    locationOrganizeSection
                    secondaryEntrySection
                    timelineSection
                }
            }
        } else {
            VStack(spacing: PhotoDeleteStyle.sectionSpacing) {
                introSection(isCompact: false)
                authorizationSection
            }
        }
    }

    @ViewBuilder
    private func introSection(isCompact: Bool) -> some View {
        if !hasSeenPhotoDeleteIntro {
            VStack(alignment: .leading, spacing: isCompact ? 12 : 14) {
                HStack(alignment: .top, spacing: 12) {
                    PhotoDeleteIconTile(
                        icon: "hand.draw",
                        size: 28,
                        cornerRadius: 8
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("快速上手"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.primaryText)

                        Text(L10n.string("默认左滑删除、右滑保留、上滑收藏；想换手势，可以在整理页底部打开设置。"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    PhotoDeleteIconTile(
                        icon: "lock.shield",
                        tint: PhotoDeleteStyle.positive,
                        size: 28,
                        cornerRadius: 8
                    )

                    Text(L10n.string("隐私优先：\(AppConstants.privacyShortText)"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hasSeenPhotoDeleteIntro = true
                    }
                } label: {
                    Text(L10n.string("知道了"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .photoDeleteMinimumTapTarget()
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                        .fill(PhotoDeleteStyle.elevatedSurface)
                )
            }
            .padding(isCompact ? 16 : 18)
            .photoDeleteCard()
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var isLibraryPreparing: Bool {
        libraryContentState == .preparing
    }

    private var libraryContentState: HomeLibraryContentState {
        HomeLibraryContentState.resolve(
            hasPhotoLibraryAccess: dataManager.photoLibraryManager.hasPhotoLibraryAccess,
            isPreparingLibrary: dataManager.isPreparingLibrary,
            isLoadingPhotoLibrary: dataManager.photoLibraryManager.isLoading,
            hasLoadedPhotoLibrary: dataManager.photoLibraryManager.hasLoadedPhotoLibrary,
            totalPhotosCount: dataManager.photoLibraryManager.displayTotalPhotosCount
        )
    }

    @ViewBuilder
    private func primaryOrganizeSection(isCompact: Bool) -> some View {
        switch libraryContentState {
        case .preparing:
            libraryScanningSection
        case .empty:
            emptyLibrarySection
        case .available:
            startOrganizingSection(isCompact: isCompact)
        case .needsAuthorization:
            EmptyView()
        }
    }

    // MARK: - 权限授权区域
    private var authorizationSection: some View {
        PhotoAuthorizationCard(
            subtitle: String(format: L10n.string("删图需要照片库权限来整理相册。%@"), AppConstants.privacyShortText),
            onRequestAccess: { dataManager.requestPhotoLibraryAccess() }
        )
    }

    // MARK: - 照片库扫描区域
    private var libraryScanningSection: some View {
        VStack(spacing: 18) {
            ScanningSwipeGlyph()

            VStack(spacing: 8) {
                Text(L10n.string("正在读取照片"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                if dataManager.photoLibraryManager.loadingProgress > 0.01 {
                    Text(L10n.percent(Int(dataManager.photoLibraryManager.loadingProgress * 100)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }

                Text(L10n.string("准备完成后会自动显示分类和数量。整理过程只在本机完成。"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if dataManager.photoLibraryManager.loadingProgress > 0.01 {
                ProgressView(value: dataManager.photoLibraryManager.loadingProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    .frame(maxWidth: .infinity)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
            }
        }
        .padding(24)
        .photoDeleteCard()
    }

    private var categorySkeletonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("快速入口"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                Spacer()
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                let skeletons: [(String, String)] = [
                    (PhotoCategory.all.title, "photo.on.rectangle"),
                    (PhotoCategory.unclassified.title, "tray"),
                    (PhotoCategory.videos.title, "video"),
                    (PhotoCategory.screenshots.title, "iphone"),
                    (PhotoCategory.livePhotos.title, "livephoto")
                ]

                ForEach(Array(skeletons.enumerated()), id: \.offset) { index, item in
                    CategorySkeletonCard(title: item.0, icon: item.1)

                    if index != skeletons.count - 1 {
                        Divider()
                            .background(PhotoDeleteStyle.hairline)
                            .padding(.leading, 62)
                    }
                }
            }
            .photoDeleteCard()
        }
    }

    // MARK: - 空照片库区域
    private var emptyLibrarySection: some View {
        VStack(spacing: 16) {
            if #available(iOS 17.0, *) {
                ContentUnavailableView(
                    L10n.string("没有可整理的照片"),
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(L10n.string("当前授权范围内没有照片。您可以在系统设置里调整删图的照片访问范围。"))
                )
                .foregroundStyle(PhotoDeleteStyle.secondaryText)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)

                    Text(L10n.string("没有可整理的照片"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(L10n.string("当前授权范围内没有照片。您可以在系统设置里调整删图的照片访问范围。"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }

            Button {
                dataManager.managePhotoLibraryAccessSettings()
            } label: {
                Label(L10n.string("管理照片访问范围"), systemImage: dataManager.photoLibraryManager.hasLimitedPhotoLibraryAccess ? "photo.badge.plus" : "gearshape")
            }
            .photoDeleteSecondaryButton()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .photoDeleteCard()
    }

    // MARK: - 主整理入口
    private func startOrganizingSection(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 16 : 18) {
            HStack(alignment: .top, spacing: 14) {
                PhotoDeleteIconTile(
                    icon: "photo.on.rectangle",
                    size: isCompact ? 42 : 48,
                    cornerRadius: 13,
                    filled: false
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("整理全部照片"))
                        .font(.system(size: isCompact ? 21 : 24, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(L10n.string("从全部照片开始，按你的节奏逐张整理。"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                navigationPath.append(SwipeViewDestination.category(.all))
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 15, weight: .semibold))
                    Text(L10n.string("开始整理"))
                }
            }
            .photoDeletePrimaryButton()

            Button {
                navigationPath.append(SwipeViewDestination.random(.memories))
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                    Text(L10n.string("随机浏览"))
                }
            }
            .photoDeleteSecondaryButton()
        }
        .padding(isCompact ? 18 : 20)
        .photoDeleteCard()
    }

    // MARK: - 地点整理入口
    private var locationOrganizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("按地点整理"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                Spacer()
            }
            .padding(.horizontal, 2)

            HomeEntryRow(
                icon: "mappin.and.ellipse",
                title: L10n.string("地点整理"),
                detail: locationOrganizeDetail,
                tint: PhotoDeleteStyle.accent
            ) {
                navigationPath.append(SwipeViewDestination.locationBrowser)
            }
            .photoDeleteCard()
        }
    }

    private var locationOrganizeDetail: String {
        if dataManager.isLoadingLocationGroups || dataManager.isResolvingLocationTitles {
            return L10n.string("正在整理地点")
        }

        let count = dataManager.locatedAssetCount
        if count > 0 {
            return L10n.shortPhotoCount(count)
        }

        return L10n.string("按地点继续")
    }

    // MARK: - 快速入口区域
    @ViewBuilder
    private var secondaryEntrySection: some View {
        if isLibraryPreparing {
            categorySkeletonSection
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.string("快速入口"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                    Spacer()
                }
                .padding(.horizontal, 2)

                VStack(spacing: 0) {
                    ForEach(Array(PhotoCategory.allCases.enumerated()), id: \.element.rawValue) { index, category in
                        HomeEntryRow(
                            icon: category.icon,
                            title: category.title,
                            detail: getPhotoCountDetail(for: category),
                            tint: iconTint(for: category)
                        ) {
                            navigationPath.append(SwipeViewDestination.category(category))
                        }

                        if index != PhotoCategory.allCases.count - 1 {
                            Divider()
                                .background(PhotoDeleteStyle.hairline)
                                .padding(.leading, 62)
                        }
                    }
                }
                .photoDeleteCard()
            }
        }
    }

    // MARK: - 时间线浏览区域
    @ViewBuilder
    private var timelineSection: some View {
        if !isLibraryPreparing && !dataManager.timeGroups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.string("按时间整理"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                    Spacer()
                }
                .padding(.horizontal, 2)

                VStack(spacing: 0) {
                    if dataManager.historicalTodayPhotoCount > 0 {
                        HomeEntryRow(
                            icon: "calendar.badge.clock",
                            title: L10n.string("历史上的今天"),
                            detail: L10n.shortPhotoCount(dataManager.historicalTodayPhotoCount),
                            tint: PhotoDeleteStyle.warning
                        ) {
                            navigationPath.append(SwipeViewDestination.historicalToday)
                        }

                        Divider()
                            .background(PhotoDeleteStyle.hairline)
                            .padding(.leading, 62)
                    }

                    ForEach(Array(dataManager.timeGroups.enumerated()), id: \.element.id) { index, timeGroupInfo in
                        HomeEntryRow(
                            icon: timeGroupInfo.timeGroup.icon,
                            title: timeGroupInfo.timeGroup.title,
                            detail: L10n.shortPhotoCount(timeGroupInfo.photosCount),
                            tint: PhotoDeleteStyle.accent
                        ) {
                            navigationPath.append(SwipeViewDestination.timeGroup(timeGroupInfo.timeGroup.rawValue))
                        }

                        if index != dataManager.timeGroups.count - 1 {
                            Divider()
                                .background(PhotoDeleteStyle.hairline)
                                .padding(.leading, 62)
                        }
                    }
                }
                .photoDeleteCard()
            }
        }
    }

    // MARK: - 辅助方法
    private func getPhotoCount(for category: PhotoCategory) -> Int {
        switch category {
        case .all:
            return dataManager.photoLibraryManager.displayTotalPhotosCount
        case .unclassified:
            return dataManager.unclassifiedPhotosCount
        case .videos:
            return dataManager.photoLibraryManager.displayVideosCount
        case .screenshots:
            return dataManager.photoLibraryManager.displayScreenshotsCount
        case .livePhotos:
            return dataManager.photoLibraryManager.displayLivePhotosCount
        case .favorites:
            return dataManager.photoLibraryManager.displayFavoritesCount
        }
    }

    private func getPhotoCountDetail(for category: PhotoCategory) -> String {
        let count = getPhotoCount(for: category)

        if HomeCategoryCountDetailResolver.shouldShowLibraryLoading(
            category: category,
            count: count,
            isPreparingLibrary: dataManager.isPreparingLibrary,
            isLoadingPhotoLibrary: dataManager.photoLibraryManager.isLoading
        ) {
            return L10n.string("读取中 \(libraryLoadingProgressText)")
        }

        if category == .unclassified && !dataManager.hasLoadedAlbumMembership {
            return L10n.string("读取中")
        }

        return L10n.shortPhotoCount(count)
    }

    private func iconTint(for category: PhotoCategory) -> Color {
        switch category {
        case .videos:
            return PhotoDeleteStyle.iconTint(for: "video")
        case .screenshots:
            return PhotoDeleteStyle.iconTint(for: "screenshot")
        case .livePhotos:
            return PhotoDeleteStyle.iconTint(for: "livephoto")
        case .favorites:
            return PhotoDeleteStyle.iconTint(for: "favorite")
        case .unclassified:
            return PhotoDeleteStyle.warning
        case .all:
            return PhotoDeleteStyle.accent
        }
    }

    private var libraryLoadingProgressText: String {
        let progress = min(max(dataManager.photoLibraryManager.loadingProgress, 0), 1)
        guard progress > 0.01 else { return "..." }
        return L10n.percent(Int(progress * 100))
    }

}

// MARK: - 首页组件
struct HomeEntryRow: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                PhotoDeleteIconTile(icon: icon, tint: tint)

                Text(title.appLocalized)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)

                Spacer()

                Text(detail.appLocalized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: PhotoDeleteStyle.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 扫描态组件
struct ScanningSwipeGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
                .frame(width: 132, height: 92)
                .rotationEffect(.degrees(animate ? 5 : 1))
                .offset(x: animate ? 20 : 14, y: -3)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .frame(width: 132, height: 92)
                .overlay(
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.black.opacity(0.16))
                            .frame(width: 58, height: 8)

                        Spacer()

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.12))
                            .frame(width: 82, height: 10)
                    }
                    .padding(16)
                )
                .rotationEffect(.degrees(animate ? -5 : -1))
                .offset(x: animate ? -18 : -8)

            Image(systemName: "arrow.left")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .offset(x: -70, y: 4)

            Image(systemName: "trash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.destructive)
                .offset(x: 76, y: 28)
        }
        .frame(height: 108)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else {
                animate = true
                return
            }
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

struct CategorySkeletonCard: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(icon: icon, tint: PhotoDeleteStyle.secondaryText, filled: false)

            VStack(alignment: .leading, spacing: 6) {
                Text(title.appLocalized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PhotoDeleteStyle.elevatedSurface)
                    .frame(width: 54, height: 6)
            }

            Spacer()

            Text(L10n.string("准备中"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
        }
        .padding(14)
        .frame(minHeight: PhotoDeleteStyle.rowMinHeight)
    }
}

#Preview {
    HomeView()
        .environmentObject(DataManager())
}
