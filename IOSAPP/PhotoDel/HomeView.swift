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
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                PhotoDelScreenBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        // 顶部标题
                        VStack(spacing: 8) {
                            Text("PhotoDel")
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .foregroundColor(PhotoDelStyle.primaryText)

                            if dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                                Text("选择分类开始整理")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(PhotoDelStyle.secondaryText)
                            } else {
                                Text("需要访问照片库权限")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(PhotoDelStyle.accent)
                            }
                        }
                        .padding(.top, 24)

                        if !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                            authorizationSection
                        } else if isLibraryPreparing {
                            libraryLoadingSection
                        } else if dataManager.photoLibraryManager.totalPhotosCount == 0 {
                            emptyLibrarySection
                        } else {
                            categorySection

                            timelineSection
                        }

                        // 底部安全区域
                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.horizontal, 24)
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

    private var isLibraryPreparing: Bool {
        dataManager.isPreparingLibrary || dataManager.photoLibraryManager.isLoading
    }

    // MARK: - 权限授权区域
    private var authorizationSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 58, weight: .medium))
                    .foregroundColor(PhotoDelStyle.accent)

                Text("需要访问照片库")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text("PhotoDel需要访问您的照片库来帮助您整理照片。我们不会上传或分享您的照片。")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }

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
    }

    // MARK: - 照片库加载区域
    private var libraryLoadingSection: some View {
        VStack(spacing: 18) {
            ProgressView(value: dataManager.photoLibraryManager.loadingProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: PhotoDelStyle.accent))
                .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                Text("正在扫描照片库")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text("\(Int(dataManager.photoLibraryManager.loadingProgress * 100))%")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(PhotoDelStyle.secondaryText)

                Text("首次打开需要一点时间。完成前不会显示空分类。")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .photoDelCard()
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

    // MARK: - 照片分类区域
    private var categorySection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("照片分类")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                Spacer()
            }

            VStack(spacing: 12) {
                ForEach(PhotoCategory.allCases, id: \.rawValue) { category in
                    CategoryCard(
                        category: category,
                        count: getPhotoCount(for: category),
                        progress: getProgressFor(category: category)
                    ) {
                        navigationPath.append(SwipeViewDestination.category(category))
                    }
                }
            }
        }
    }

    // MARK: - 时间线浏览区域
    private var timelineSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("时间线浏览")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                Spacer()
            }

            VStack(spacing: 12) {
                ForEach(dataManager.timeGroups) { timeGroupInfo in
                    TimelineCard(
                        timeGroup: timeGroupInfo.timeGroup,
                        count: timeGroupInfo.photosCount,
                        progress: timeGroupInfo.progress
                    ) {
                        navigationPath.append(SwipeViewDestination.timeGroup(timeGroupInfo.timeGroup.rawValue))
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

    private func getPhotoCount(for timeGroup: TimeGroup) -> Int {
        return dataManager.getPhotosForTimeGroup(timeGroup).count
    }

    private func getProgressFor(category: PhotoCategory) -> Double {
        let totalPhotos = getPhotoCount(for: category)
        guard totalPhotos > 0 else { return 0.0 }

        let organizedCount = dataManager.getOrganizedCount(for: category)
        return Double(organizedCount) / Double(totalPhotos)
    }
}

// MARK: - 分类卡片
struct CategoryCard: View {
    let category: PhotoCategory
    let count: Int
    let progress: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(PhotoDelStyle.elevatedSurface)
                        .frame(width: 42, height: 42)

                    Image(systemName: category.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.iconTint(for: category == .videos ? "video" : category == .favorites ? "favorite" : "photo"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text("\(count) 张")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PhotoDelStyle.tertiaryText)

                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: PhotoDelStyle.accent))
                        .frame(width: 48)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .photoDelCard()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 时间线卡片
struct TimelineCard: View {
    let timeGroup: TimeGroup
    let count: Int
    let progress: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(PhotoDelStyle.elevatedSurface)
                        .frame(width: 42, height: 42)

                    Image(systemName: timeGroup.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(timeGroup.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text("\(count) 张")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PhotoDelStyle.tertiaryText)

                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: PhotoDelStyle.accent))
                        .frame(width: 48)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .photoDelCard()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    HomeView()
        .environmentObject(DataManager())
}
