//
//  Models.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import Foundation
import SwiftUI
import Photos

// MARK: - 照片分类
enum PhotoCategory: String, CaseIterable {
    case all = "全部照片"
    case videos = "视频"
    case screenshots = "截图"
    case livePhotos = "实况照片"
    case favorites = "收藏"

    var title: String {
        switch self {
        case .all: return L10n.string("全部照片")
        case .videos: return L10n.string("视频")
        case .screenshots: return L10n.string("截图")
        case .livePhotos: return L10n.string("实况照片")
        case .favorites: return L10n.favoritesCategoryTitle
        }
    }

    var icon: String {
        switch self {
        case .all: return "photo.on.rectangle"
        case .videos: return "video"
        case .screenshots: return "iphone"
        case .livePhotos: return "livephoto"
        case .favorites: return "heart"
        }
    }
}

// MARK: - 手势控制
enum SwipeGestureAction: String, CaseIterable, Identifiable {
    case previous
    case next
    case close
    case delete
    case keep
    case favorite

    var id: String { rawValue }

    static var configurableCases: [SwipeGestureAction] {
        [.previous, .next, .delete, .keep, .favorite]
    }

    var title: String {
        switch self {
        case .previous: return L10n.string("上一张")
        case .next: return L10n.string("下一张")
        case .close: return L10n.string("返回")
        case .delete: return L10n.string("删除")
        case .keep: return L10n.string("保留")
        case .favorite: return L10n.string("收藏")
        }
    }

    var detailTitle: String {
        switch self {
        case .previous: return L10n.string("浏览上一张")
        case .next: return L10n.string("浏览下一张")
        case .close: return L10n.string("返回列表")
        case .delete: return L10n.string("加入待删除")
        case .keep: return L10n.string("跳过")
        case .favorite: return L10n.string("加入收藏")
        }
    }

    var icon: String {
        switch self {
        case .previous: return "chevron.left"
        case .next: return "chevron.right"
        case .close: return "chevron.down"
        case .delete: return "trash"
        case .keep: return "checkmark"
        case .favorite: return "heart"
        }
    }

    var tint: Color {
        switch self {
        case .previous, .next, .close: return PhotoDeleteStyle.accent
        case .delete: return PhotoDeleteStyle.destructive
        case .keep: return PhotoDeleteStyle.positive
        case .favorite: return PhotoDeleteStyle.iconTint(for: "favorite")
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
    let titleKey: String
    let subtitleKey: String
    let leftAction: SwipeGestureAction
    let rightAction: SwipeGestureAction
    let upAction: SwipeGestureAction

    var title: String {
        L10n.key(titleKey)
    }

    var subtitle: String {
        L10n.key(subtitleKey)
    }

    func action(for direction: SwipeGestureDirection) -> SwipeGestureAction {
        switch direction {
        case .left: return leftAction
        case .right: return rightAction
        case .up: return upAction
        }
    }

    static let standard = SwipeGesturePreset(
        id: "standard",
        titleKey: "左右浏览，上滑删除",
        subtitleKey: "左滑下一张，右滑上一张，上滑删除",
        leftAction: .next,
        rightAction: .previous,
        upAction: .delete
    )

    static let reversed = SwipeGesturePreset(
        id: "leftDelete",
        titleKey: "左滑删除",
        subtitleKey: "左滑删除，右滑下一张，上滑收藏",
        leftAction: .delete,
        rightAction: .next,
        upAction: .favorite
    )

    static let verticalDelete = SwipeGesturePreset(
        id: "classic",
        titleKey: "左删右留",
        subtitleKey: "左滑删除，右滑保留，上滑收藏",
        leftAction: .delete,
        rightAction: .keep,
        upAction: .favorite
    )

    static let presets: [SwipeGesturePreset] = [
        .standard,
        .reversed,
        .verticalDelete
    ]
}

enum SwipeGesturePreferences {
    private static let gestureMigrationVersion = "browse-left-next-v1"

    static func defaultAction(for direction: SwipeGestureDirection) -> SwipeGestureAction {
        SwipeGesturePreset.standard.action(for: direction)
    }

    static func normalizedAction(_ rawValue: String, fallback: SwipeGestureAction) -> SwipeGestureAction {
        SwipeGestureAction(rawValue: rawValue) ?? fallback
    }

    static func migrateStoredDefaultsIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: AppConstants.gestureDefaultMigrationKey) != gestureMigrationVersion else {
            return
        }

        let leftValue = defaults.string(forKey: AppConstants.leftSwipeActionKey)
        let rightValue = defaults.string(forKey: AppConstants.rightSwipeActionKey)
        let upValue = defaults.string(forKey: AppConstants.upSwipeActionKey)

        let matchesLeftDeleteDefault = leftValue == SwipeGestureAction.delete.rawValue &&
            rightValue == SwipeGestureAction.keep.rawValue &&
            (upValue == nil || upValue == SwipeGestureAction.favorite.rawValue)

        let matchesOlderRightDeleteDefault = leftValue == SwipeGestureAction.keep.rawValue &&
            rightValue == SwipeGestureAction.delete.rawValue &&
            (upValue == nil || upValue == SwipeGestureAction.favorite.rawValue)

        let matchesPreviousBrowseDefault = leftValue == SwipeGestureAction.previous.rawValue &&
            rightValue == SwipeGestureAction.next.rawValue &&
            upValue == SwipeGestureAction.delete.rawValue

        if matchesLeftDeleteDefault || matchesOlderRightDeleteDefault || matchesPreviousBrowseDefault {
            defaults.set(SwipeGesturePreset.standard.leftAction.rawValue, forKey: AppConstants.leftSwipeActionKey)
            defaults.set(SwipeGesturePreset.standard.rightAction.rawValue, forKey: AppConstants.rightSwipeActionKey)
            defaults.set(SwipeGesturePreset.standard.upAction.rawValue, forKey: AppConstants.upSwipeActionKey)
        }

        defaults.set(gestureMigrationVersion, forKey: AppConstants.gestureDefaultMigrationKey)
    }
}

enum ReviewPlaybackPreferences {
    static func applyLaunchDefaults(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: AppConstants.reviewVideoMutedKey)
    }
}

enum PhotoReviewMode: String, CaseIterable, Identifiable {
    case card
    case browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .card: return L10n.string("卡片")
        case .browser: return L10n.string("双行")
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .card: return L10n.string("当前是卡片模式")
        case .browser: return L10n.string("当前是双行浏览模式")
        }
    }

    var toggleAccessibilityHint: String {
        switch self {
        case .card: return L10n.string("切换到双行浏览")
        case .browser: return L10n.string("切换到卡片模式")
        }
    }

    var toolbarTitle: String {
        title
    }

    var toolbarIcon: String {
        icon
    }

    var switchAnnouncement: String {
        switch self {
        case .card: return L10n.string("已切换到卡片模式")
        case .browser: return L10n.string("已切换到双行浏览")
        }
    }

    var icon: String {
        switch self {
        case .card: return "rectangle.portrait"
        case .browser: return "rectangle.grid.2x2"
        }
    }

    var toggled: PhotoReviewMode {
        switch self {
        case .card: return .browser
        case .browser: return .card
        }
    }

    static func normalized(_ rawValue: String?) -> PhotoReviewMode {
        guard let rawValue else { return .card }
        return PhotoReviewMode(rawValue: rawValue) ?? .card
    }
}

// MARK: - 时间分组
enum TimeGroup: String, CaseIterable {
    case today
    case thisWeek
    case thisMonth
    case lastMonth
    case olderPhotos

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

    var legacyRawValue: String {
        switch self {
        case .today: return "今天的照片"
        case .thisWeek: return "本周的照片"
        case .thisMonth: return "本月的照片"
        case .lastMonth: return "上个月的照片"
        case .olderPhotos: return "更早的照片"
        }
    }

    static func fromIdentifier(_ identifier: String) -> TimeGroup? {
        TimeGroup(rawValue: identifier) ?? TimeGroup.allCases.first { $0.legacyRawValue == identifier }
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
    case all
    case recents
    case favorites
    case screenshots
    case videos
    case livePhotos
    case userCreated

    var title: String {
        switch self {
        case .all: return L10n.string("全部照片")
        case .recents: return L10n.string("最近项目")
        case .favorites: return L10n.favoritesCategoryTitle
        case .screenshots: return L10n.string("截图")
        case .videos: return L10n.string("视频")
        case .livePhotos: return L10n.string("实况照片")
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
        case .livePhotos: return "livephoto"
        case .userCreated: return "folder"
        }
    }

    var legacyRawValue: String {
        switch self {
        case .all: return "全部照片"
        case .recents: return "最近项目"
        case .favorites: return "收藏"
        case .screenshots: return "截图"
        case .videos: return "视频"
        case .livePhotos: return "实况照片"
        case .userCreated: return "用户相册"
        }
    }

    static func fromStoredValue(_ value: String) -> AlbumType? {
        AlbumType(rawValue: value) ?? AlbumType.allCases.first { $0.legacyRawValue == value }
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

enum HistoricalTodayResolver {
    static func isHistoricalToday(
        _ creationDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let creationComponents = calendar.dateComponents([.year, .month, .day], from: creationDate)
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)

        guard let creationYear = creationComponents.year,
              let currentYear = todayComponents.year else {
            return false
        }

        return creationYear < currentYear &&
            creationComponents.month == todayComponents.month &&
            creationComponents.day == todayComponents.day
    }
}

// MARK: - 整理统计
struct OrganizeStats {
    var totalPhotos: Int = 0
    var deletedPhotos: Int = 0
    var spaceSaved: Double = 0.0 // MB

    var formattedSpaceSaved: String {
        CleanupStatsFormatter.space(spaceSaved)
    }
}

// MARK: - App Appearance
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L10n.string("跟随系统")
        case .light: return L10n.string("日间模式")
        case .dark: return L10n.string("夜间模式")
        }
    }

    var detail: String {
        switch self {
        case .system: return L10n.string("根据 iPhone 外观自动切换")
        case .light: return L10n.string("明亮背景，适合白天整理")
        case .dark: return L10n.string("深色背景，适合夜间整理")
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 进阶功能
enum AdvancedTimeScope: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return L10n.string("日")
        case .week: return L10n.string("周")
        case .month: return L10n.string("月")
        case .year: return L10n.string("年")
        }
    }

    var actionTitle: String {
        switch self {
        case .day: return L10n.string("整理这一天")
        case .week: return L10n.string("整理这一周")
        case .month: return L10n.string("整理这个月")
        case .year: return L10n.string("整理这一年")
        }
    }

    var rangeDescription: String {
        switch self {
        case .day: return L10n.string("按当天照片继续整理")
        case .week: return L10n.string("按这一周照片继续整理")
        case .month: return L10n.string("按这个月照片继续整理")
        case .year: return L10n.string("按这一年照片继续整理")
        }
    }

    var icon: String {
        switch self {
        case .day: return "calendar"
        case .week: return "calendar.badge.clock"
        case .month: return "calendar.circle"
        case .year: return "calendar.badge.exclamationmark"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

enum AdvancedCleanupKind: String, CaseIterable, Identifiable {
    case similarPhotos
    case largeFiles
    case imageCompression
    case videoCompression
    case videos

    var id: String { rawValue }

    static var visibleCases: [AdvancedCleanupKind] {
        allCases.filter { kind in
            switch kind {
            case .imageCompression:
                return AppConstants.isImageCompressionVisible
            default:
                return true
            }
        }
    }

    var title: String {
        switch self {
        case .similarPhotos: return L10n.string("相似照片")
        case .largeFiles: return L10n.string("大文件")
        case .imageCompression: return L10n.string("图片压缩")
        case .videoCompression: return L10n.string("视频压缩")
        case .videos: return L10n.string("视频")
        }
    }

    var icon: String {
        switch self {
        case .similarPhotos: return "square.stack.3d.down.right"
        case .largeFiles: return "internaldrive"
        case .imageCompression: return "photo.badge.arrow.down"
        case .videoCompression: return "arrow.down.forward.and.arrow.up.backward"
        case .videos: return "video.fill"
        }
    }

    var tint: Color {
        switch self {
        case .similarPhotos: return PhotoDeleteTheme.current.secondaryAccent
        case .largeFiles: return PhotoDeleteStyle.warning
        case .imageCompression: return PhotoDeleteStyle.accent
        case .videoCompression: return PhotoDeleteStyle.positive
        case .videos: return PhotoDeleteStyle.iconTint(for: "video")
        }
    }
}

struct PhotoDaySummary: Identifiable, Equatable {
    let date: Date
    let photoCount: Int
    let screenshotCount: Int
    let videoCount: Int
    let reviewedCount: Int
    let estimatedSizeMB: Double

    var id: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    var progress: Double {
        guard photoCount > 0 else { return 0 }
        return min(Double(reviewedCount) / Double(photoCount), 1)
    }

    var formattedEstimatedSize: String {
        CleanupStatsFormatter.space(estimatedSizeMB)
    }
}

struct PhotoMonthSummary: Identifiable, Equatable {
    let monthStart: Date
    let assetCount: Int
    let screenshotCount: Int
    let videoCount: Int
    let reviewedCount: Int
    let estimatedSizeMB: Double

    var id: String {
        let components = Calendar.current.dateComponents([.year, .month], from: monthStart)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    var progress: Double {
        guard assetCount > 0 else { return 0 }
        return min(Double(reviewedCount) / Double(assetCount), 1)
    }

    var remainingCount: Int {
        max(assetCount - reviewedCount, 0)
    }

    var formattedEstimatedSize: String {
        CleanupStatsFormatter.space(estimatedSizeMB)
    }
}

struct PhotoPeriodSummary: Identifiable, Equatable {
    let scope: AdvancedTimeScope
    let intervalStart: Date
    let intervalEnd: Date
    let assetCount: Int
    let screenshotCount: Int
    let videoCount: Int
    let reviewedCount: Int
    let estimatedSizeMB: Double

    var id: String {
        let start = Int(intervalStart.timeIntervalSince1970)
        return "\(scope.rawValue)-\(start)"
    }

    var progress: Double {
        guard assetCount > 0 else { return 0 }
        return min(Double(reviewedCount) / Double(assetCount), 1)
    }

    var remainingCount: Int {
        max(assetCount - reviewedCount, 0)
    }

    var formattedEstimatedSize: String {
        CleanupStatsFormatter.space(estimatedSizeMB)
    }

    static func empty(
        scope: AdvancedTimeScope,
        containing date: Date,
        calendar: Calendar = .current
    ) -> PhotoPeriodSummary {
        let interval = calendar.dateInterval(for: scope, containing: date)
        return PhotoPeriodSummary(
            scope: scope,
            intervalStart: interval.start,
            intervalEnd: interval.end,
            assetCount: 0,
            screenshotCount: 0,
            videoCount: 0,
            reviewedCount: 0,
            estimatedSizeMB: 0
        )
    }
}

extension Calendar {
    func dateInterval(for scope: AdvancedTimeScope, containing date: Date) -> DateInterval {
        if let interval = dateInterval(of: scope.calendarComponent, for: date) {
            return interval
        }

        let start = startOfDay(for: date)
        let end = self.date(byAdding: scope.calendarComponent, value: 1, to: start)
            ?? self.date(byAdding: .day, value: 1, to: start)
            ?? start
        return DateInterval(start: start, end: end)
    }
}

struct DeviceStorageSnapshot: Equatable {
    let totalBytes: Int64
    let freeBytes: Int64

    static let empty = DeviceStorageSnapshot(totalBytes: 0, freeBytes: 0)

    var usedBytes: Int64 {
        max(totalBytes - freeBytes, 0)
    }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    var formattedUsed: String {
        Self.formatBytes(usedBytes)
    }

    var formattedFree: String {
        Self.formatBytes(freeBytes)
    }

    var formattedTotal: String {
        Self.formatBytes(totalBytes)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 GB" }
        let gigabytes = Double(bytes) / 1_073_741_824
        if gigabytes >= 100 {
            return "\(gigabytes.formatted(.number.grouping(.never).precision(.fractionLength(0)))) GB"
        }
        return "\(gigabytes.formatted(.number.grouping(.never).precision(.fractionLength(1)))) GB"
    }
}

struct AdvancedCleanupQueue: Identifiable, Equatable {
    let kind: AdvancedCleanupKind
    let assetCount: Int
    let estimatedSpaceMB: Double

    var id: String { kind.id }

    var formattedSpace: String {
        CleanupStatsFormatter.space(estimatedSpaceMB)
    }
}

struct AdvancedLibraryStats: Equatable {
    let totalAssets: Int
    let reviewedAssets: Int
    let deletedAssets: Int
    let organizedAssets: Int
    let estimatedSpaceSavedMB: Double
    let pendingDeleteAssets: Int
    let storageSnapshot: DeviceStorageSnapshot

    var formattedSpaceSaved: String {
        CleanupStatsFormatter.space(estimatedSpaceSavedMB)
    }
}

struct AdvancedLibrarySnapshot: Equatable {
    let stats: AdvancedLibraryStats
    let daySummaries: [PhotoDaySummary]
    let monthSummaries: [PhotoMonthSummary]
    let cleanupQueues: [AdvancedCleanupQueue]

    static func demo(referenceDate: Date = Date(), calendar: Calendar = .current) -> AdvancedLibrarySnapshot {
        let monthStart = calendar.dateInterval(of: .month, for: referenceDate)?.start ?? referenceDate
        let monthPatterns: [(Int, Int, Int, Int, Int, Double)] = [
            (0, 632, 82, 38, 428, 3_420),
            (-1, 1_248, 326, 64, 1_026, 5_860),
            (-2, 924, 196, 51, 498, 4_120),
            (-3, 704, 88, 42, 704, 2_960),
            (-4, 386, 72, 24, 158, 1_840),
            (-5, 518, 108, 29, 130, 2_360),
            (-6, 812, 141, 58, 324, 3_540),
            (-7, 436, 67, 31, 214, 1_920),
            (-8, 1_104, 238, 77, 712, 6_240)
        ]
        let monthSummaries = monthPatterns.compactMap { offset, assets, screenshots, videos, reviewed, size -> PhotoMonthSummary? in
            guard let month = calendar.date(byAdding: .month, value: offset, to: monthStart) else { return nil }
            return PhotoMonthSummary(
                monthStart: month,
                assetCount: assets,
                screenshotCount: screenshots,
                videoCount: videos,
                reviewedCount: reviewed,
                estimatedSizeMB: size
            )
        }

        let pattern: [(Int, Int, Int, Int, Double)] = [
            (1, 24, 2, 0, 78), (2, 42, 9, 1, 164), (4, 18, 1, 0, 54),
            (6, 86, 24, 4, 620), (8, 35, 7, 0, 116), (9, 54, 14, 2, 260),
            (11, 28, 4, 1, 148), (13, 73, 17, 3, 512), (15, 31, 5, 0, 92),
            (18, 96, 28, 6, 1_320), (21, 63, 11, 2, 342), (23, 39, 8, 0, 128),
            (26, 44, 12, 1, 236), (29, 58, 16, 2, 410)
        ]

        let summaries = pattern.compactMap { day, photos, screenshots, videos, size -> PhotoDaySummary? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { return nil }
            return PhotoDaySummary(
                date: date,
                photoCount: photos,
                screenshotCount: screenshots,
                videoCount: videos,
                reviewedCount: Int(Double(photos) * 0.58),
                estimatedSizeMB: size
            )
        }

        return AdvancedLibrarySnapshot(
            stats: AdvancedLibraryStats(
                totalAssets: 8_426,
                reviewedAssets: 2_184,
                deletedAssets: 642,
                organizedAssets: 2_184,
                estimatedSpaceSavedMB: 4_860,
                pendingDeleteAssets: 37,
                storageSnapshot: DeviceStorageSnapshot(totalBytes: 256 * 1_073_741_824, freeBytes: 42 * 1_073_741_824)
            ),
            daySummaries: summaries,
            monthSummaries: monthSummaries,
            cleanupQueues: [
                AdvancedCleanupQueue(kind: .similarPhotos, assetCount: 184, estimatedSpaceMB: 860),
                AdvancedCleanupQueue(kind: .largeFiles, assetCount: 46, estimatedSpaceMB: 3_240),
                AdvancedCleanupQueue(kind: .imageCompression, assetCount: 96, estimatedSpaceMB: 720),
                AdvancedCleanupQueue(kind: .videoCompression, assetCount: 28, estimatedSpaceMB: 2_760),
                AdvancedCleanupQueue(kind: .videos, assetCount: 62, estimatedSpaceMB: 7_800)
            ].filter { AdvancedCleanupKind.visibleCases.contains($0.kind) }
        )
    }
}

struct AdvancedSimilarPhotoGroup: Identifiable {
    let assets: [PHAsset]
    let estimatedSpaceMB: Double

    var id: String {
        assets.map(\.localIdentifier).joined(separator: "|")
    }

    var title: String {
        guard let date = representativeDate else { return L10n.string("相似照片") }
        return AdvancedSimilarPhotoGroupFormatter.groupTitle(for: date)
    }

    var representativeDate: Date? {
        assets.first?.creationDate
    }

    var suggestedDeleteCount: Int {
        max(assets.count - 1, 0)
    }

    var formattedEstimatedSpace: String {
        CleanupStatsFormatter.space(estimatedSpaceMB)
    }
}

struct CleanupCelebration: Identifiable, Equatable {
    let id: UUID
    let deletedPhotos: Int
    let favoritedPhotos: Int
    let organizedPhotos: Int
    let estimatedSpaceSavedMB: Double
    let totalDeletedPhotos: Int
    let totalSpaceSavedMB: Double
    let currentStreakDays: Int
    let newAchievements: [CleanupAchievement]
    let nextAchievementProgress: CleanupAchievementProgress?
    let date: Date

    init(
        id: UUID = UUID(),
        deletedPhotos: Int,
        favoritedPhotos: Int,
        organizedPhotos: Int,
        estimatedSpaceSavedMB: Double,
        totalDeletedPhotos: Int,
        totalSpaceSavedMB: Double,
        currentStreakDays: Int = 0,
        newAchievements: [CleanupAchievement] = [],
        nextAchievementProgress: CleanupAchievementProgress? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.deletedPhotos = deletedPhotos
        self.favoritedPhotos = favoritedPhotos
        self.organizedPhotos = organizedPhotos
        self.estimatedSpaceSavedMB = estimatedSpaceSavedMB
        self.totalDeletedPhotos = totalDeletedPhotos
        self.totalSpaceSavedMB = totalSpaceSavedMB
        self.currentStreakDays = currentStreakDays
        self.newAchievements = newAchievements
        self.nextAchievementProgress = nextAchievementProgress
        self.date = date
    }

    var formattedSpaceSaved: String {
        CleanupStatsFormatter.space(estimatedSpaceSavedMB)
    }

    var formattedTotalSpaceSaved: String {
        CleanupStatsFormatter.space(totalSpaceSavedMB)
    }
}

private enum AdvancedSimilarPhotoGroupFormatter {
    static func groupTitle(for date: Date) -> String {
        AppDateFormatter.string(from: date, template: "MMMd")
    }
}
