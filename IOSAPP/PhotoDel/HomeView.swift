//
//  HomeView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI

enum SwipeViewDestination: Hashable {
    case category(PhotoCategory)
    case timeGroup(String)
    case album(AlbumInfo)

    static func == (lhs: SwipeViewDestination, rhs: SwipeViewDestination) -> Bool {
        switch (lhs, rhs) {
        case (.category(let lhsCategory), .category(let rhsCategory)):
            return lhsCategory == rhsCategory
        case (.timeGroup(let lhsTimeGroup), .timeGroup(let rhsTimeGroup)):
            return lhsTimeGroup == rhsTimeGroup
        case (.album(let lhsAlbum), .album(let rhsAlbum)):
            return lhsAlbum.id == rhsAlbum.id
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
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var dataManager: DataManager
    @AppStorage("hasSeenPhotoDelIntro") private var hasSeenPhotoDelIntro = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height && geometry.size.width > AppConstants.landscapeBreakpoint

                ZStack {
                    PhotoDelScreenBackground()

                    ScrollView {
                        homeContent(isLandscape: isLandscape)
                            .padding(.horizontal, isLandscape ? 32 : 24)
                            .padding(.top, isLandscape ? 18 : 24)
                            .padding(.bottom, 112)
                            .frame(maxWidth: isLandscape ? 900 : 520)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationBarHidden(true)
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
                }
            }
        }
    }

    @ViewBuilder
    private func homeContent(isLandscape: Bool) -> some View {
        if dataManager.photoLibraryManager.hasPhotoLibraryAccess {
            if isLandscape {
                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 18) {
                        titleSection
                        introSection(isCompact: true)
                        primaryOrganizeSection(isCompact: true)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 18) {
                        secondaryEntrySection
                        timelineSection
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 22) {
                    titleSection
                    introSection(isCompact: false)
                    primaryOrganizeSection(isCompact: false)
                    secondaryEntrySection
                    timelineSection
                }
            }
        } else {
            VStack(spacing: 22) {
                titleSection
                introSection(isCompact: false)
                authorizationSection
            }
        }
    }

    @ViewBuilder
    private func introSection(isCompact: Bool) -> some View {
        if !hasSeenPhotoDelIntro {
            VStack(alignment: .leading, spacing: isCompact ? 12 : 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.accent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(PhotoDelStyle.elevatedSurface))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("快速上手"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.primaryText)

                        Text(L10n.string("左滑删除，右滑跳过，上滑收藏。点完成后再统一确认。"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.positive)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(PhotoDelStyle.elevatedSurface))

                    Text(L10n.string("隐私优先：\(AppConstants.privacyShortText)"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hasSeenPhotoDelIntro = true
                    }
                } label: {
                    Text(L10n.string("知道了"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: PhotoDelStyle.controlRadius, style: .continuous)
                        .fill(PhotoDelStyle.elevatedSurface)
                )
            }
            .padding(isCompact ? 16 : 18)
            .photoDelCard(radius: 18)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var isLibraryPreparing: Bool {
        dataManager.isPreparingLibrary
    }

    private var titleSection: some View {
        VStack(spacing: 7) {
            Text("PhotoDel")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundColor(PhotoDelStyle.primaryText)

            Text(titleSubtitle)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(dataManager.photoLibraryManager.hasPhotoLibraryAccess ? PhotoDelStyle.secondaryText : PhotoDelStyle.accent)
        }
    }

    private var titleSubtitle: String {
        if !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
            return L10n.string("需要访问照片库权限")
        }
        if isLibraryPreparing {
            return L10n.string("正在读取照片信息")
        }
        return L10n.string("轻扫判断照片去留")
    }

    @ViewBuilder
    private func primaryOrganizeSection(isCompact: Bool) -> some View {
        if isLibraryPreparing {
            libraryScanningSection
        } else if dataManager.photoLibraryManager.totalPhotosCount == 0 && !dataManager.photoLibraryManager.isLoading {
            emptyLibrarySection
        } else {
            startOrganizingSection(isCompact: isCompact)
        }
    }

    // MARK: - 权限授权区域
    private var authorizationSection: some View {
        PhotoAuthorizationCard(
            subtitle: L10n.string("PhotoDel 需要照片库权限来整理相册。\(AppConstants.privacyShortText)"),
            onRequestAccess: { dataManager.requestPhotoLibraryAccess() }
        )
    }

    // MARK: - 照片库扫描区域
    private var libraryScanningSection: some View {
        VStack(spacing: 18) {
            ScanningSwipeGlyph()

            VStack(spacing: 8) {
                Text("正在读取照片")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                if dataManager.photoLibraryManager.loadingProgress > 0.01 {
                    Text(L10n.percent(Int(dataManager.photoLibraryManager.loadingProgress * 100)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                }

                Text("准备完成后会自动显示分类和数量。整理过程只在本机完成。")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if dataManager.photoLibraryManager.loadingProgress > 0.01 {
                ProgressView(value: dataManager.photoLibraryManager.loadingProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDelStyle.accent))
                    .frame(maxWidth: .infinity)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDelStyle.accent))
            }
        }
        .padding(24)
        .photoDelCard()
    }

    private var categorySkeletonSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("快速入口")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                Spacer()
            }

            VStack(spacing: 12) {
                CategorySkeletonCard(title: PhotoCategory.all.title, icon: "photo.on.rectangle")
                CategorySkeletonCard(title: PhotoCategory.videos.title, icon: "video")
                CategorySkeletonCard(title: PhotoCategory.screenshots.title, icon: "iphone")
            }
        }
    }

    // MARK: - 空照片库区域
    private var emptyLibrarySection: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .medium))
                .foregroundColor(PhotoDelStyle.secondaryText)

            Text("没有可整理的照片")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)

            Text("当前授权范围内没有照片。您可以在系统设置里调整 PhotoDel 的照片访问范围。")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(PhotoDelStyle.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .photoDelCard()
    }

    // MARK: - 主整理入口
    private func startOrganizingSection(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 16 : 22) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PhotoDelStyle.elevatedSurface)
                        .frame(width: isCompact ? 46 : 54, height: isCompact ? 46 : 54)

                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: isCompact ? 19 : 23, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("开始整理照片")
                        .font(.system(size: isCompact ? 22 : 26, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text("滑动整理照片，完成前不会真正删除。手势可在设置里调整。")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                navigationPath.append(SwipeViewDestination.category(.all))
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                    Text("整理全部照片")
                }
            }
            .photoDelPrimaryButton()

            if isCompact {
                Text(primarySummaryText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PhotoDelStyle.secondaryText)
            } else {
                HStack(spacing: 0) {
                    HomeStatPill(value: primaryPhotoCountValue, label: primaryPhotoCountLabel)
                    Divider()
                        .frame(height: 28)
                        .background(PhotoDelStyle.hairline)
                    HomeStatPill(value: "\(dataManager.deleteCandidates.count)", label: L10n.string("待删除"))
                    Divider()
                        .frame(height: 28)
                        .background(PhotoDelStyle.hairline)
                    HomeStatPill(value: dataManager.organizeStats.formattedSpaceSaved, label: L10n.string("可释放"))
                }
                .padding(.vertical, 3)
            }
        }
        .padding(isCompact ? 18 : 22)
        .photoDelCard(radius: 20)
    }

    // MARK: - 快速入口区域
    @ViewBuilder
    private var secondaryEntrySection: some View {
        if isLibraryPreparing {
            categorySkeletonSection
        } else {
            VStack(spacing: 14) {
                HStack {
                    Text("快速入口")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)
                    Spacer()
                }

                VStack(spacing: 10) {
                    ForEach(PhotoCategory.allCases, id: \.rawValue) { category in
                        HomeEntryRow(
                            icon: category.icon,
                            title: category.title,
                            detail: getPhotoCountDetail(for: category),
                            tint: PhotoDelStyle.iconTint(for: category == .videos ? "video" : category == .favorites ? "favorite" : "photo")
                        ) {
                            navigationPath.append(SwipeViewDestination.category(category))
                        }
                    }
                }
            }
        }
    }

    // MARK: - 时间线浏览区域
    @ViewBuilder
    private var timelineSection: some View {
        if !isLibraryPreparing && !dataManager.timeGroups.isEmpty {
            VStack(spacing: 14) {
                HStack {
                    Text("按时间整理")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)
                    Spacer()
                }

                VStack(spacing: 10) {
                    ForEach(dataManager.timeGroups) { timeGroupInfo in
                        HomeEntryRow(
                            icon: timeGroupInfo.timeGroup.icon,
                            title: timeGroupInfo.timeGroup.title,
                            detail: L10n.shortPhotoCount(timeGroupInfo.photosCount),
                            tint: PhotoDelStyle.accent
                        ) {
                            navigationPath.append(SwipeViewDestination.timeGroup(timeGroupInfo.timeGroup.rawValue))
                        }
                    }
                }
            }
        }
    }

    // MARK: - 辅助方法
    private func getPhotoCount(for category: PhotoCategory) -> Int {
        switch category {
        case .all:
            return dataManager.photoLibraryManager.totalPhotosCount
        case .videos:
            return dataManager.photoLibraryManager.videosCount
        case .screenshots:
            return dataManager.photoLibraryManager.screenshotsCount
        case .favorites:
            return dataManager.photoLibraryManager.favoritesCount
        }
    }

    private var primarySummaryText: String {
        if dataManager.photoLibraryManager.totalPhotosCount == 0 && dataManager.photoLibraryManager.isLoading {
            return L10n.string("正在读取照片信息 \(libraryLoadingProgressText) · 可先进入整理")
        }
        return L10n.string("\(dataManager.photoLibraryManager.totalPhotosCount) 张待整理 · \(dataManager.deleteCandidates.count) 张待删除")
    }

    private var primaryPhotoCountValue: String {
        if dataManager.photoLibraryManager.totalPhotosCount == 0 && dataManager.photoLibraryManager.isLoading {
            return libraryLoadingProgressText
        }
        return "\(dataManager.photoLibraryManager.totalPhotosCount)"
    }

    private var primaryPhotoCountLabel: String {
        if dataManager.photoLibraryManager.totalPhotosCount == 0 && dataManager.photoLibraryManager.isLoading {
            return L10n.string("读取中")
        }
        return L10n.string("待整理")
    }

    private func getPhotoCountDetail(for category: PhotoCategory) -> String {
        let count = getPhotoCount(for: category)
        if count == 0 && dataManager.photoLibraryManager.isLoading {
            return L10n.string("读取中 \(libraryLoadingProgressText)")
        }
        return L10n.shortPhotoCount(count)
    }

    private var libraryLoadingProgressText: String {
        let progress = min(max(dataManager.photoLibraryManager.loadingProgress, 0), 1)
        guard progress > 0.01 else { return "..." }
        return L10n.percent(Int(progress * 100))
    }

}

// MARK: - 首页组件
struct HomeStatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label.appLocalized)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(PhotoDelStyle.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HomeEntryRow: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(PhotoDelStyle.elevatedSurface)
                        .frame(width: 38, height: 38)

                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                }

                Text(title.appLocalized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                    .lineLimit(1)

                Spacer()

                Text(detail.appLocalized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .photoDelCard(radius: 15)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 扫描态组件
struct ScanningSwipeGlyph: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PhotoDelStyle.elevatedSurface)
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
                .foregroundColor(PhotoDelStyle.accent)
                .offset(x: -70, y: 4)

            Image(systemName: "trash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDelStyle.destructive)
                .offset(x: 76, y: 28)
        }
        .frame(height: 108)
        .onAppear {
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
            Circle()
                .fill(PhotoDelStyle.elevatedSurface)
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(title.appLocalized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PhotoDelStyle.elevatedSurface)
                    .frame(width: 54, height: 6)
            }

            Spacer()

            Text(L10n.string("准备中"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PhotoDelStyle.tertiaryText)
        }
        .padding(14)
        .photoDelCard()
    }
}

#Preview {
    HomeView()
        .environmentObject(DataManager())
}
