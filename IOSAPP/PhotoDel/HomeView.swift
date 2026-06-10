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
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // 顶部标题
                        VStack(spacing: 8) {
                            Text("PhotoDel")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            if dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                                Text("选择分类开始整理")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.gray)
                            } else {
                                Text("需要访问照片库权限")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.top, 20)

                        // 权限状态和授权
                        if !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                            authorizationSection
                        }

                        // 照片分类（仅在已授权时显示）
                        if dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                            categorySection

                            // 时间线浏览
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

    // MARK: - 权限授权区域
    private var authorizationSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundColor(.blue)

                Text("需要访问照片库")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("PhotoDel需要访问您的照片库来帮助您整理照片。我们不会上传或分享您的照片。")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }

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
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - 照片分类区域
    private var categorySection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("照片分类")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
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
                    .foregroundColor(.white)
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

    private var progressColor: Color {
        if progress >= 0.9 { return .yellow } // 90%以上 - 黄色
        else if progress >= 0.8 { return .green } // 80-90% - 绿色
        else if progress >= 0.6 { return .blue } // 60-80% - 蓝色
        else if progress >= 0.4 { return .cyan } // 40-60% - 青色
        else { return .purple } // 40%以下 - 紫色
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(category.color)
                        .frame(width: 40, height: 40)

                    Image(systemName: category.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }

                // 文字信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Text("\(count)张")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.gray)
                }

                Spacer()

                // 进度指示器
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 24, height: 24)
                        .rotationEffect(.degrees(-90))
                }

                // 箭头
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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

    private var progressColor: Color {
        if progress >= 0.9 { return .yellow } // 90%以上 - 黄色
        else if progress >= 0.8 { return .green } // 80-90% - 绿色
        else if progress >= 0.6 { return .blue } // 60-80% - 蓝色
        else if progress >= 0.4 { return .cyan } // 40-60% - 青色
        else { return .purple } // 40%以下 - 紫色
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(timeGroup.color)
                        .frame(width: 40, height: 40)

                    Image(systemName: timeGroup.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }

                // 文字信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeGroup.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Text("\(count)张")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.gray)
                }

                Spacer()

                // 进度指示器
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                        .frame(width: 32, height: 32)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(progressColor)
                }

                // 箭头
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    HomeView()
        .environmentObject(DataManager())
}
