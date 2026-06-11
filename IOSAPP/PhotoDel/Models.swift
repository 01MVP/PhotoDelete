//
//  Models.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import Foundation
import SwiftUI
import Photos

// MARK: - 照片分类
enum PhotoCategory: String, CaseIterable {
    case all = "全部照片"
    case videos = "视频"
    case screenshots = "截图"
    case favorites = "收藏"

    var title: String {
        switch self {
        case .all: return L10n.string("全部照片")
        case .videos: return L10n.string("视频")
        case .screenshots: return L10n.string("截图")
        case .favorites: return L10n.string("收藏")
        }
    }

    var icon: String {
        switch self {
        case .all: return "photo.on.rectangle"
        case .videos: return "video"
        case .screenshots: return "iphone"
        case .favorites: return "heart.fill"
        }
    }
}

// MARK: - 手势控制
enum SwipeGestureAction: String, CaseIterable, Identifiable {
    case delete
    case keep
    case favorite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .delete: return L10n.string("删除")
        case .keep: return L10n.string("保留")
        case .favorite: return L10n.string("收藏")
        }
    }

    var detailTitle: String {
        switch self {
        case .delete: return L10n.string("删除候选")
        case .keep: return L10n.string("保留跳过")
        case .favorite: return L10n.string("加入收藏")
        }
    }

    var icon: String {
        switch self {
        case .delete: return "trash"
        case .keep: return "checkmark"
        case .favorite: return "heart"
        }
    }

    var tint: Color {
        switch self {
        case .delete: return PhotoDelStyle.destructive
        case .keep: return PhotoDelStyle.positive
        case .favorite: return PhotoDelStyle.iconTint(for: "favorite")
        }
    }
}

enum SwipeGestureDirection: String, CaseIterable, Identifiable {
    case left
    case right
    case up

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return L10n.string("左滑")
        case .right: return L10n.string("右滑")
        case .up: return L10n.string("上滑")
        }
    }

    var icon: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        }
    }
}

struct SwipeGesturePreset: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let leftAction: SwipeGestureAction
    let rightAction: SwipeGestureAction
    let upAction: SwipeGestureAction

    func action(for direction: SwipeGestureDirection) -> SwipeGestureAction {
        switch direction {
        case .left: return leftAction
        case .right: return rightAction
        case .up: return upAction
        }
    }

    static let standard = SwipeGesturePreset(
        id: "standard",
        title: L10n.string("左删右留"),
        subtitle: L10n.string("左滑删除，右滑保留，上滑收藏"),
        leftAction: .delete,
        rightAction: .keep,
        upAction: .favorite
    )

    static let reversed = SwipeGesturePreset(
        id: "reversed",
        title: L10n.string("左留右删"),
        subtitle: L10n.string("左滑保留，右滑删除，上滑收藏"),
        leftAction: .keep,
        rightAction: .delete,
        upAction: .favorite
    )

    static let verticalDelete = SwipeGesturePreset(
        id: "verticalDelete",
        title: L10n.string("上滑删除"),
        subtitle: L10n.string("上滑删除，左滑保留，右滑收藏"),
        leftAction: .keep,
        rightAction: .favorite,
        upAction: .delete
    )

    static let presets: [SwipeGesturePreset] = [
        .standard,
        .reversed,
        .verticalDelete
    ]
}

enum SwipeGesturePreferences {
    static func defaultAction(for direction: SwipeGestureDirection) -> SwipeGestureAction {
        SwipeGesturePreset.standard.action(for: direction)
    }

    static func normalizedAction(_ rawValue: String, fallback: SwipeGestureAction) -> SwipeGestureAction {
        SwipeGestureAction(rawValue: rawValue) ?? fallback
    }
}

// MARK: - 时间分组
enum TimeGroup: String, CaseIterable {
    case today = "今天的照片"
    case thisWeek = "本周的照片"
    case thisMonth = "本月的照片"
    case lastMonth = "上个月的照片"
    case olderPhotos = "更早的照片"

    var title: String {
        switch self {
        case .today: return L10n.string("今天的照片")
        case .thisWeek: return L10n.string("本周的照片")
        case .thisMonth: return L10n.string("本月的照片")
        case .lastMonth: return L10n.string("上个月的照片")
        case .olderPhotos: return L10n.string("更早的照片")
        }
    }

    var icon: String {
        switch self {
        case .today: return "calendar"
        case .thisWeek: return "calendar.badge.clock"
        case .thisMonth: return "calendar.circle"
        case .lastMonth: return "calendar.badge.minus"
        case .olderPhotos: return "calendar.badge.exclamationmark"
        }
    }
}

enum TimeGroupResolver {
    static func group(for creationDate: Date, now: Date = Date(), calendar: Calendar = .current) -> TimeGroup {
        if calendar.isDate(creationDate, inSameDayAs: now) {
            return .today
        }

        if isSameWeek(creationDate, now, calendar: calendar) {
            return .thisWeek
        }

        if isSameMonth(creationDate, now, calendar: calendar) {
            return .thisMonth
        }

        if let lastMonth = calendar.date(byAdding: .month, value: -1, to: now),
           isSameMonth(creationDate, lastMonth, calendar: calendar) {
            return .lastMonth
        }

        return .olderPhotos
    }

    private static func isSameWeek(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        let lhsComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: lhs)
        let rhsComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: rhs)
        return lhsComponents.yearForWeekOfYear == rhsComponents.yearForWeekOfYear &&
            lhsComponents.weekOfYear == rhsComponents.weekOfYear
    }

    private static func isSameMonth(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        let lhsComponents = calendar.dateComponents([.year, .month], from: lhs)
        let rhsComponents = calendar.dateComponents([.year, .month], from: rhs)
        return lhsComponents.year == rhsComponents.year &&
            lhsComponents.month == rhsComponents.month
    }
}

// MARK: - 相册类型
enum AlbumType: String, CaseIterable {
    case all = "全部照片"
    case recents = "最近项目"
    case favorites = "收藏"
    case screenshots = "截图"
    case videos = "视频"
    case userCreated = "用户相册"

    var title: String {
        switch self {
        case .all: return L10n.string("全部照片")
        case .recents: return L10n.string("最近项目")
        case .favorites: return L10n.string("收藏")
        case .screenshots: return L10n.string("截图")
        case .videos: return L10n.string("视频")
        case .userCreated: return L10n.string("用户相册")
        }
    }

    var icon: String {
        switch self {
        case .all: return "photo.on.rectangle"
        case .recents: return "clock.arrow.circlepath"
        case .favorites: return "heart.fill"
        case .screenshots: return "iphone"
        case .videos: return "video"
        case .userCreated: return "folder"
        }
    }
}

// MARK: - 相册信息
struct AlbumInfo: Identifiable {
    let id: String
    let title: String
    let assetCollection: PHAssetCollection?
    let type: AlbumType
    let photosCount: Int
    let thumbnailAsset: PHAsset?

    init(assetCollection: PHAssetCollection?, type: AlbumType, photosCount: Int = 0, thumbnailAsset: PHAsset? = nil) {
        if let collection = assetCollection {
            self.id = collection.localIdentifier
            self.title = collection.localizedTitle ?? type.title
            self.assetCollection = collection
        } else {
            self.id = type.rawValue
            self.title = type.title
            self.assetCollection = nil
        }
        self.type = type
        self.photosCount = photosCount
        self.thumbnailAsset = thumbnailAsset
    }

    init(id: String, title: String, assetCollection: PHAssetCollection?, type: AlbumType, photosCount: Int = 0, thumbnailAsset: PHAsset? = nil) {
        self.id = id
        self.title = title
        self.assetCollection = assetCollection
        self.type = type
        self.photosCount = photosCount
        self.thumbnailAsset = thumbnailAsset
    }
}

// MARK: - 时间组信息
struct TimeGroupInfo: Identifiable {
    let id: String
    let timeGroup: TimeGroup
    let photosCount: Int
    let progress: Double // 整理进度 0.0-1.0

    init(timeGroup: TimeGroup, photosCount: Int, progress: Double = 0.0) {
        self.id = timeGroup.rawValue
        self.timeGroup = timeGroup
        self.photosCount = photosCount
        self.progress = progress
    }
}

// MARK: - 整理统计
struct OrganizeStats {
    var totalPhotos: Int = 0
    var deletedPhotos: Int = 0
    var spaceSaved: Double = 0.0 // MB

    var formattedSpaceSaved: String {
        if spaceSaved < 1000 {
            return String(format: "%.1f MB", spaceSaved)
        } else {
            return String(format: "%.1f GB", spaceSaved / 1000)
        }
    }
}
