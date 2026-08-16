//
//  CleanupAchievements.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/12/26.
//

import SwiftUI

enum CleanupAchievementTint: String, Equatable {
    case accent
    case positive
    case warning
    case destructive
    case favorite

    var color: Color {
        switch self {
        case .accent:
            return PhotoDeleteStyle.accent
        case .positive:
            return PhotoDeleteStyle.positive
        case .warning:
            return PhotoDeleteStyle.warning
        case .destructive:
            return PhotoDeleteStyle.destructive
        case .favorite:
            return PhotoDeleteStyle.iconTint(for: "favorite")
        }
    }
}

struct CleanupAchievement: Identifiable, Equatable {
    let id: String
    let category: CleanupAchievementCategory
    let titleKey: String
    let subtitleKey: String
    let systemImage: String
    let tint: CleanupAchievementTint

    var title: String {
        L10n.key(titleKey)
    }

    var subtitle: String {
        L10n.key(subtitleKey)
    }
}

struct CleanupAchievementProgress: Identifiable, Equatable {
    let achievement: CleanupAchievement
    let currentValue: Double
    let targetValue: Double
    let metric: CleanupAchievementMetric

    var id: String {
        achievement.id
    }

    var isUnlocked: Bool {
        currentValue >= targetValue
    }

    var progress: Double {
        guard targetValue > 0 else { return 1 }
        return min(max(currentValue / targetValue, 0), 1)
    }

    var remainingValue: Double {
        max(targetValue - currentValue, 0)
    }

    var remainingDescription: String {
        switch metric {
        case .sessions:
            return L10n.string("还差 \(Int(ceil(remainingValue))) 次整理")
        case .deletedPhotos:
            return L10n.string("还差 \(Int(ceil(remainingValue))) 张删除")
        case .spaceSavedMB:
            return L10n.string("还差 \(CleanupStatsFormatter.space(remainingValue))")
        case .streakDays:
            return L10n.string("还差 \(Int(ceil(remainingValue))) 天连续整理")
        }
    }

    var valueDescription: String {
        switch metric {
        case .sessions:
            return L10n.string("\(Int(currentValue))/\(Int(targetValue)) 次")
        case .deletedPhotos:
            return L10n.string("\(Int(currentValue))/\(Int(targetValue)) 张")
        case .spaceSavedMB:
            return L10n.string("\(CleanupStatsFormatter.space(currentValue))/\(CleanupStatsFormatter.space(targetValue))")
        case .streakDays:
            return L10n.string("\(Int(currentValue))/\(Int(targetValue)) 天")
        }
    }
}

enum CleanupAchievementMetric: Equatable {
    case sessions
    case deletedPhotos
    case spaceSavedMB
    case streakDays
}

enum CleanupAchievementCategory: String, CaseIterable, Identifiable, Equatable {
    case rhythm
    case deletion
    case space
    case streak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rhythm:
            return L10n.string("整理节奏")
        case .deletion:
            return L10n.string("删除数量")
        case .space:
            return L10n.string("删除内容")
        case .streak:
            return L10n.string("连续整理")
        }
    }
}

private struct CleanupAchievementDefinition {
    let achievement: CleanupAchievement
    let metric: CleanupAchievementMetric
    let targetValue: Double
}

enum CleanupAchievementEvaluator {
    private static let definitions: [CleanupAchievementDefinition] = [
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "first_cleanup",
                category: .rhythm,
                titleKey: "第一次清理",
                subtitleKey: "完成第一轮照片整理",
                systemImage: "sparkles",
                tint: .accent
            ),
            metric: .sessions,
            targetValue: 1
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "sessions_5",
                category: .rhythm,
                titleKey: "开始有节奏",
                subtitleKey: "完成 5 次整理",
                systemImage: "checklist",
                tint: .accent
            ),
            metric: .sessions,
            targetValue: 5
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "sessions_20",
                category: .rhythm,
                titleKey: "长期整理者",
                subtitleKey: "完成 20 次整理",
                systemImage: "calendar",
                tint: .accent
            ),
            metric: .sessions,
            targetValue: 20
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "delete_10",
                category: .deletion,
                titleKey: "轻装上阵",
                subtitleKey: "累计删除 10 张照片",
                systemImage: "trash",
                tint: .destructive
            ),
            metric: .deletedPhotos,
            targetValue: 10
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "delete_50",
                category: .deletion,
                titleKey: "相册减负",
                subtitleKey: "累计删除 50 张照片",
                systemImage: "photo.stack",
                tint: .destructive
            ),
            metric: .deletedPhotos,
            targetValue: 50
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "delete_100",
                category: .deletion,
                titleKey: "清理达人",
                subtitleKey: "累计删除 100 张照片",
                systemImage: "checkmark.seal",
                tint: .accent
            ),
            metric: .deletedPhotos,
            targetValue: 100
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "delete_500",
                category: .deletion,
                titleKey: "大扫除",
                subtitleKey: "累计删除 500 张照片",
                systemImage: "trash.slash",
                tint: .destructive
            ),
            metric: .deletedPhotos,
            targetValue: 500
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "save_100mb",
                category: .space,
                titleKey: "清理 100 MB",
                subtitleKey: "累计删除内容约 100 MB",
                systemImage: "internaldrive",
                tint: .positive
            ),
            metric: .spaceSavedMB,
            targetValue: 100
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "streak_3",
                category: .streak,
                titleKey: "三天连续整理",
                subtitleKey: "连续 3 天都有清理记录",
                systemImage: "flame",
                tint: .warning
            ),
            metric: .streakDays,
            targetValue: 3
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "save_1gb",
                category: .space,
                titleKey: "清理 1 GB",
                subtitleKey: "累计删除内容约 1 GB",
                systemImage: "externaldrive.badge.checkmark",
                tint: .positive
            ),
            metric: .spaceSavedMB,
            targetValue: 1_000
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "save_10gb",
                category: .space,
                titleKey: "清理 10 GB",
                subtitleKey: "累计删除内容约 10 GB",
                systemImage: "externaldrive.fill",
                tint: .positive
            ),
            metric: .spaceSavedMB,
            targetValue: 10_000
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "save_100gb",
                category: .space,
                titleKey: "清理 100 GB",
                subtitleKey: "累计删除内容约 100 GB",
                systemImage: "archivebox.fill",
                tint: .positive
            ),
            metric: .spaceSavedMB,
            targetValue: 100_000
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "streak_7",
                category: .streak,
                titleKey: "一周不断档",
                subtitleKey: "连续 7 天都有清理记录",
                systemImage: "calendar.badge.checkmark",
                tint: .warning
            ),
            metric: .streakDays,
            targetValue: 7
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "streak_30",
                category: .streak,
                titleKey: "连续整理 30 天",
                subtitleKey: "连续 30 天都有清理记录",
                systemImage: "flame.fill",
                tint: .warning
            ),
            metric: .streakDays,
            targetValue: 30
        )
    ]

    static func unlockedAchievements(summary: CleanupStatsSummary, streakDays: Int) -> [CleanupAchievement] {
        definitions
            .filter { value(for: $0.metric, summary: summary, streakDays: streakDays) >= $0.targetValue }
            .map(\.achievement)
    }

    static func allProgress(summary: CleanupStatsSummary, streakDays: Int) -> [CleanupAchievementProgress] {
        definitions.map { definition in
            CleanupAchievementProgress(
                achievement: definition.achievement,
                currentValue: value(for: definition.metric, summary: summary, streakDays: streakDays),
                targetValue: definition.targetValue,
                metric: definition.metric
            )
        }
    }

    static func closeProgress(
        summary: CleanupStatsSummary,
        streakDays: Int,
        limit: Int = 3
    ) -> [CleanupAchievementProgress] {
        guard limit > 0 else { return [] }

        let lockedProgress = allProgress(summary: summary, streakDays: streakDays)
            .enumerated()
            .filter { !$0.element.isUnlocked }
            .sorted { lhs, rhs in
                if lhs.element.progress == rhs.element.progress {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.progress > rhs.element.progress
            }
            .map(\.element)

        let closeProgress = lockedProgress.filter { $0.progress >= 0.5 }
        return Array((closeProgress.isEmpty ? lockedProgress : closeProgress).prefix(limit))
    }

    static func newlyUnlockedAchievements(
        previousSummary: CleanupStatsSummary,
        currentSummary: CleanupStatsSummary,
        previousStreakDays: Int,
        currentStreakDays: Int
    ) -> [CleanupAchievement] {
        definitions.compactMap { definition in
            let previousValue = value(
                for: definition.metric,
                summary: previousSummary,
                streakDays: previousStreakDays
            )
            let currentValue = value(
                for: definition.metric,
                summary: currentSummary,
                streakDays: currentStreakDays
            )
            guard previousValue < definition.targetValue, currentValue >= definition.targetValue else {
                return nil
            }
            return definition.achievement
        }
    }

    static func nextProgress(summary: CleanupStatsSummary, streakDays: Int) -> CleanupAchievementProgress? {
        definitions.compactMap { definition -> CleanupAchievementProgress? in
            let currentValue = value(for: definition.metric, summary: summary, streakDays: streakDays)
            guard currentValue < definition.targetValue else { return nil }
            return CleanupAchievementProgress(
                achievement: definition.achievement,
                currentValue: currentValue,
                targetValue: definition.targetValue,
                metric: definition.metric
            )
        }
        .max { lhs, rhs in
            if lhs.progress == rhs.progress {
                return lhs.targetValue > rhs.targetValue
            }
            return lhs.progress < rhs.progress
        }
    }

    private static func value(
        for metric: CleanupAchievementMetric,
        summary: CleanupStatsSummary,
        streakDays: Int
    ) -> Double {
        switch metric {
        case .sessions:
            return Double(summary.sessions)
        case .deletedPhotos:
            return Double(summary.deletedPhotos)
        case .spaceSavedMB:
            return summary.estimatedSpaceSavedMB
        case .streakDays:
            return Double(streakDays)
        }
    }
}
