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

    var icon: String {
        switch self {
        case .all: return "photo.on.rectangle"
        case .videos: return "video"
        case .screenshots: return "iphone"
        case .favorites: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .all: return .blue
        case .videos: return .purple
        case .screenshots: return .green
        case .favorites: return .yellow
        }
    }
}

// MARK: - 时间分组
enum TimeGroup: String, CaseIterable {
    case today = "今天的照片"
    case thisWeek = "本周的照片"
    case thisMonth = "本月的照片"
    case lastMonth = "上个月的照片"
    case olderPhotos = "更早的照片"

    var icon: String {
        switch self {
        case .today: return "calendar"
        case .thisWeek: return "calendar.badge.clock"
        case .thisMonth: return "calendar.circle"
        case .lastMonth: return "calendar.badge.minus"
        case .olderPhotos: return "calendar.badge.exclamationmark"
        }
    }

    var color: Color {
        switch self {
        case .today: return .green
        case .thisWeek: return .blue
        case .thisMonth: return .purple
        case .lastMonth: return .orange
        case .olderPhotos: return .gray
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

    var color: Color {
        switch self {
        case .all: return .blue
        case .recents: return .green
        case .favorites: return .red
        case .screenshots: return .purple
        case .videos: return .orange
        case .userCreated: return .gray
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
            self.title = collection.localizedTitle ?? type.rawValue
            self.assetCollection = collection
        } else {
            self.id = type.rawValue
            self.title = type.rawValue
            self.assetCollection = nil
        }
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

    var progressColor: Color {
        if progress >= 0.9 { return .yellow } // 90%以上 - 黄色
        else if progress >= 0.8 { return .green } // 80-90% - 绿色
        else if progress >= 0.6 { return .blue } // 60-80% - 蓝色
        else if progress >= 0.4 { return .cyan } // 40-60% - 青色
        else { return .purple } // 40%以下 - 紫色
    }
}

// MARK: - 整理统计
struct OrganizeStats {
    var totalPhotos: Int = 0
    var deletedPhotos: Int = 0
    var keptPhotos: Int = 0
    var favoritedPhotos: Int = 0
    var spaceSaved: Double = 0.0 // MB

    var formattedSpaceSaved: String {
        if spaceSaved < 1000 {
            return String(format: "%.1f MB", spaceSaved)
        } else {
            return String(format: "%.1f GB", spaceSaved / 1000)
        }
    }
}
