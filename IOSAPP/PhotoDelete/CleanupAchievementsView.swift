//
//  CleanupAchievementsView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/12/26.
//

import SwiftUI

struct CleanupAchievementsEntryCard: View {
    @ObservedObject var statsStore: CleanupStatsStore

    private var unlockedCount: Int {
        statsStore.unlockedAchievements.count
    }

    private var totalCount: Int {
        statsStore.achievementProgresses.count
    }

    private var nextProgress: CleanupAchievementProgress? {
        statsStore.nextAchievementProgress
    }

    var body: some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(
                icon: "seal.fill",
                tint: PhotoDeleteStyle.warning,
                size: 42,
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(L10n.string("清理成就"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(L10n.string("\(unlockedCount)/\(totalCount)"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(PhotoDeleteStyle.warning)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(PhotoDeleteStyle.warning.opacity(0.14))
                        )
                }

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
        }
        .padding(15)
        .photoDeleteCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("清理成就，已获得 \(unlockedCount) 枚，共 \(totalCount) 枚"))
    }

    private var subtitle: String {
        if let nextProgress {
            return L10n.string("下一个目标：\(nextProgress.achievement.title)，\(nextProgress.remainingDescription)。")
        }
        return L10n.string("全部徽章已获得，继续保持整理节奏。")
    }
}

struct CleanupAchievementsView: View {
    @ObservedObject var statsStore: CleanupStatsStore
    var showsDoneButton = false

    @Environment(\.dismiss) private var dismiss

    private var allProgress: [CleanupAchievementProgress] {
        statsStore.achievementProgresses
    }

    private var unlockedProgress: [CleanupAchievementProgress] {
        allProgress.filter(\.isUnlocked)
    }

    private var closeProgress: [CleanupAchievementProgress] {
        statsStore.closeAchievementProgresses
    }

    private var groupedAllProgress: [CleanupAchievementCategoryProgressGroup] {
        CleanupAchievementCategory.allCases.compactMap { category in
            let items = allProgress.filter { $0.achievement.category == category }
            return items.isEmpty ? nil : CleanupAchievementCategoryProgressGroup(category: category, items: items)
        }
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(spacing: 18) {
                    introHeader
                    overviewCard

                    achievementSection(
                        title: L10n.string("已获得"),
                        subtitle: L10n.string("已经完成的清理里程碑"),
                        progressItems: unlockedProgress,
                        emptyTitle: L10n.string("还没有获得徽章"),
                        emptySubtitle: L10n.string("完成一次清理后会点亮第一枚徽章。")
                    )

                    achievementSection(
                        title: L10n.string("接近完成"),
                        subtitle: L10n.string("优先追踪最接近的目标"),
                        progressItems: closeProgress,
                        emptyTitle: L10n.string("暂无待完成目标"),
                        emptySubtitle: L10n.string("当前所有徽章都已经点亮。")
                    )

                    allAchievementSection
                }
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(L10n.string("清理成就"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.accent)
                }
            }
        }
    }

    private var introHeader: some View {
        Text(L10n.string("记录删除、节省空间和连续整理进度"))
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(PhotoDeleteStyle.secondaryText)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewCard: some View {
        HStack(spacing: 10) {
            CleanupAchievementOverviewMetric(
                value: "\(unlockedProgress.count)",
                label: L10n.string("已获得"),
                tint: PhotoDeleteStyle.warning
            )

            CleanupAchievementOverviewMetric(
                value: "\(statsStore.currentStreakDays)",
                label: L10n.string("连续天数"),
                tint: PhotoDeleteStyle.positive
            )

            CleanupAchievementOverviewMetric(
                value: statsStore.summary.formattedSpaceSaved,
                label: L10n.string("累计节省"),
                tint: PhotoDeleteStyle.accent
            )
        }
        .padding(14)
        .photoDeleteCard()
    }

    private func achievementSection(
        title: String,
        subtitle: String,
        progressItems: [CleanupAchievementProgress],
        emptyTitle: String,
        emptySubtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            if progressItems.isEmpty {
                CleanupAchievementEmptyCard(title: emptyTitle, subtitle: emptySubtitle)
            } else {
                LazyVStack(spacing: 9) {
                    ForEach(progressItems) { progress in
                        CleanupAchievementProgressRow(progress: progress)
                    }
                }
            }
        }
    }

    private var allAchievementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("全部徽章"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(L10n.string("按类型查看每一枚清理里程碑"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            if groupedAllProgress.isEmpty {
                CleanupAchievementEmptyCard(
                    title: L10n.string("暂无徽章"),
                    subtitle: L10n.string("完成清理后会在这里记录。")
                )
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(groupedAllProgress) { group in
                        CleanupAchievementCategoryGroup(
                            title: group.category.title,
                            progressItems: group.items
                        )
                    }
                }
            }
        }
    }
}

private struct CleanupAchievementCategoryProgressGroup: Identifiable {
    let category: CleanupAchievementCategory
    let items: [CleanupAchievementProgress]

    var id: String { category.id }
}

private struct CleanupAchievementOverviewMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(tint.opacity(0.1))
        )
    }
}

private struct CleanupAchievementCategoryGroup: View {
    let title: String
    let progressItems: [CleanupAchievementProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .lineLimit(1)

            LazyVStack(spacing: 9) {
                ForEach(progressItems) { progress in
                    CleanupAchievementProgressRow(progress: progress)
                }
            }
        }
    }
}

private struct CleanupAchievementProgressRow: View {
    let progress: CleanupAchievementProgress

    var body: some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(
                icon: progress.achievement.systemImage,
                tint: progress.achievement.tint.color,
                size: 40,
                cornerRadius: 12,
                style: progress.isUnlocked ? .solid : .soft
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(progress.achievement.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if progress.isUnlocked {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.positive)
                    }

                    Spacer(minLength: 6)

                    Text(progress.valueDescription)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(progress.isUnlocked ? PhotoDeleteStyle.positive : PhotoDeleteStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Text(progress.achievement.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                ProgressView(value: progress.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: progress.achievement.tint.color))
                    .clipShape(Capsule(style: .continuous))
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PhotoDeleteStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            progress.isUnlocked ? progress.achievement.tint.color.opacity(0.26) : PhotoDeleteStyle.cardStroke,
                            lineWidth: 1
                        )
                )
        )
        .accessibilityElement(children: .combine)
    }
}

private struct CleanupAchievementEmptyCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(
                icon: "seal",
                tint: PhotoDeleteStyle.tertiaryText,
                size: 38,
                cornerRadius: 11
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            Spacer()
        }
        .padding(14)
        .photoDeleteCard(radius: 16)
    }
}
