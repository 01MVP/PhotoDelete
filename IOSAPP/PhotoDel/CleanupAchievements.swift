//
//  CleanupAchievements.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 6/12/26.
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
            return PhotoDelStyle.accent
        case .positive:
            return PhotoDelStyle.positive
        case .warning:
            return PhotoDelStyle.warning
        case .destructive:
            return PhotoDelStyle.destructive
        case .favorite:
            return PhotoDelStyle.iconTint(for: "favorite")
        }
    }
}

struct CleanupAchievement: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: CleanupAchievementTint
}

struct CleanupAchievementProgress: Equatable {
    let achievement: CleanupAchievement
    let currentValue: Double
    let targetValue: Double
    let metric: CleanupAchievementMetric

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
}

enum CleanupAchievementMetric: Equatable {
    case sessions
    case deletedPhotos
    case spaceSavedMB
    case streakDays
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
                title: L10n.string("第一次清理"),
                subtitle: L10n.string("完成第一轮照片整理"),
                systemImage: "sparkles",
                tint: .accent
            ),
            metric: .sessions,
            targetValue: 1
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "delete_10",
                title: L10n.string("轻装上阵"),
                subtitle: L10n.string("累计删除 10 张照片"),
                systemImage: "trash",
                tint: .destructive
            ),
            metric: .deletedPhotos,
            targetValue: 10
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "save_100mb",
                title: L10n.string("腾出空间"),
                subtitle: L10n.string("累计节省 100 MB"),
                systemImage: "internaldrive",
                tint: .positive
            ),
            metric: .spaceSavedMB,
            targetValue: 100
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "streak_3",
                title: L10n.string("三天连续整理"),
                subtitle: L10n.string("连续 3 天都有清理记录"),
                systemImage: "flame",
                tint: .warning
            ),
            metric: .streakDays,
            targetValue: 3
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "delete_50",
                title: L10n.string("相册减负"),
                subtitle: L10n.string("累计删除 50 张照片"),
                systemImage: "photo.stack",
                tint: .destructive
            ),
            metric: .deletedPhotos,
            targetValue: 50
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "save_1gb",
                title: L10n.string("空间回收者"),
                subtitle: L10n.string("累计节省 1 GB"),
                systemImage: "externaldrive.badge.checkmark",
                tint: .positive
            ),
            metric: .spaceSavedMB,
            targetValue: 1_000
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "delete_100",
                title: L10n.string("清理达人"),
                subtitle: L10n.string("累计删除 100 张照片"),
                systemImage: "checkmark.seal",
                tint: .accent
            ),
            metric: .deletedPhotos,
            targetValue: 100
        ),
        CleanupAchievementDefinition(
            achievement: CleanupAchievement(
                id: "streak_7",
                title: L10n.string("一周不断档"),
                subtitle: L10n.string("连续 7 天都有清理记录"),
                systemImage: "calendar.badge.checkmark",
                tint: .warning
            ),
            metric: .streakDays,
            targetValue: 7
        )
    ]

    static func unlockedAchievements(summary: CleanupStatsSummary, streakDays: Int) -> [CleanupAchievement] {
        definitions
            .filter { value(for: $0.metric, summary: summary, streakDays: streakDays) >= $0.targetValue }
            .map(\.achievement)
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
