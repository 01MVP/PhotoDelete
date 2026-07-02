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
    var showsHistory = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingClearConfirmation = false

    private var allProgress: [CleanupAchievementProgress] {
        statsStore.achievementProgresses
    }

    private var unlockedProgress: [CleanupAchievementProgress] {
        allProgress.filter(\.isUnlocked)
    }

    private var nextProgress: CleanupAchievementProgress? {
        statsStore.nextAchievementProgress
    }

    private var summary: CleanupStatsSummary {
        statsStore.summary
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
                VStack(spacing: PhotoDeleteStyle.sectionSpacing) {
                    archiveSummarySection
                    nextBadgeSection

                    badgeWallSection

                    if showsHistory {
                        historySection
                    }
                }
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, PhotoDeleteStyle.rootContentTopSpacing)
                .padding(.bottom, 36)
                .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(showsHistory ? L10n.string("成就与历史") : L10n.string("清理成就"))
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
        .confirmationDialog(L10n.string("清空本机统计记录？"), isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button(L10n.string("清空统计记录"), role: .destructive) {
                statsStore.clearAll()
            }
            Button(L10n.string("取消"), role: .cancel) {}
        } message: {
            Text(L10n.string("只会清空删图的本机统计，不会影响照片。"))
        }
    }

    private var archiveSummarySection: some View {
        VStack(spacing: 16) {
            HStack {
                Text(showsHistory ? L10n.string("清理档案") : L10n.string("清理成就"))
                    .photoDeleteSectionHeading()

                Spacer()
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    PhotoDeleteIconTile(
                        icon: "seal.fill",
                        tint: PhotoDeleteStyle.warning,
                        size: 38,
                        cornerRadius: 11
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("徽章、连续整理和节省空间进度"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.primaryText)
                            .lineLimit(2)

                        Text(L10n.string("所有记录只保存在本机。"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text("\(unlockedProgress.count)/\(allProgress.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(PhotoDeleteStyle.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                HStack(spacing: 8) {
                    StatCard(
                        value: "\(unlockedProgress.count)/\(allProgress.count)",
                        label: L10n.string("已获得"),
                        color: PhotoDeleteStyle.warning
                    )
                    StatCard(
                        value: "\(summary.sessions)",
                        label: L10n.string("清理次数"),
                        color: PhotoDeleteStyle.accent
                    )
                    StatCard(
                        value: "\(summary.deletedPhotos)",
                        label: L10n.string("累计删除"),
                        color: PhotoDeleteStyle.destructive
                    )
                    StatCard(
                        value: summary.formattedSpaceSaved,
                        label: L10n.string("累计节省"),
                        color: PhotoDeleteStyle.positive
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .photoDeleteCard()
        }
        .accessibilityElement(children: .combine)
    }

    private var nextBadgeSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L10n.string("下一个徽章"))
                    .photoDeleteSectionHeading()

                Spacer()
            }

            VStack(spacing: 0) {
                if let nextProgress {
                    CleanupAchievementNextRow(progress: nextProgress)
                } else {
                    CleanupAchievementAllUnlockedRow()
                }
            }
            .photoDeleteCard()
        }
    }

    private var badgeWallSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("里程碑徽章"))
                    .photoDeleteSectionHeading()

                Text(L10n.string("按类型点亮每一枚清理徽章"))
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

    @ViewBuilder
    private var historySection: some View {
        VStack(spacing: 16) {
            SupporterMonthlySection(summaries: statsStore.monthlySummaries)

            SupporterHistorySection(sessions: Array(statsStore.sessions.prefix(50)))

            Button(role: .destructive) {
                showingClearConfirmation = true
            } label: {
                Text(L10n.string("清空统计记录"))
                    .frame(maxWidth: .infinity)
            }
            .photoDeleteSecondaryButton()
        }
    }
}

private struct CleanupAchievementCategoryProgressGroup: Identifiable {
    let category: CleanupAchievementCategory
    let items: [CleanupAchievementProgress]

    var id: String { category.id }
}

private struct CleanupAchievementNextRow: View {
    let progress: CleanupAchievementProgress

    var body: some View {
        HStack(spacing: 12) {
            CleanupAchievementMedal(progress: progress, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(progress.achievement.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(progress.remainingDescription)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            Text(progress.valueDescription)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(progress.achievement.tint.color)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: PhotoDeleteStyle.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

private struct CleanupAchievementAllUnlockedRow: View {
    var body: some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(
                icon: "checkmark.seal.fill",
                tint: PhotoDeleteStyle.positive,
                size: 38,
                cornerRadius: 11
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("全部徽章已点亮"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(L10n.string("已经完成所有清理里程碑。"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: PhotoDeleteStyle.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

private struct CleanupAchievementCategoryGroup: View {
    let title: String
    let progressItems: [CleanupAchievementProgress]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var badgeMinimumWidth: CGFloat = 80

    private var unlockedCount: Int {
        progressItems.filter(\.isUnlocked).count
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 10)]
        }

        return [GridItem(.adaptive(minimum: max(78, badgeMinimumWidth), maximum: 96), spacing: 8)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)

                Spacer()

                Text("\(unlockedCount)/\(progressItems.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
            }

            LazyVGrid(
                columns: columns,
                spacing: 8
            ) {
                ForEach(progressItems) { progress in
                    CleanupAchievementBadgeTile(progress: progress)
                }
            }
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct CleanupAchievementBadgeTile: View {
    let progress: CleanupAchievementProgress

    @ScaledMetric(relativeTo: .body) private var medalSize: CGFloat = 42
    @ScaledMetric(relativeTo: .body) private var tileMinHeight: CGFloat = 92

    var body: some View {
        VStack(spacing: 7) {
            CleanupAchievementMedal(progress: progress, size: medalSize)

            Text(progress.achievement.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)

            Text(progress.isUnlocked ? L10n.string("已点亮") : progress.valueDescription)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(progress.isUnlocked ? progress.achievement.tint.color : PhotoDeleteStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, minHeight: tileMinHeight)
        .padding(.vertical, 4)
        .opacity(progress.isUnlocked ? 1 : 0.58)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(progress.achievement.title)，\(progress.achievement.subtitle)，\(progress.valueDescription)"))
    }
}

private struct CleanupAchievementMedal: View {
    let progress: CleanupAchievementProgress
    var size: CGFloat = 56
    var isFeatured = false

    private var tint: Color {
        progress.achievement.tint.color
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    progress.isUnlocked
                    ? AnyShapeStyle(LinearGradient(
                        colors: [tint.opacity(0.98), tint.opacity(0.68)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    : AnyShapeStyle(PhotoDeleteStyle.surface)
                )
                .overlay(
                    Circle()
                        .stroke(
                            progress.isUnlocked ? tint.opacity(0.36) : PhotoDeleteStyle.cardStroke,
                            lineWidth: progress.isUnlocked ? 1.5 : 1
                        )
                )
                .shadow(
                    color: progress.isUnlocked ? tint.opacity(isFeatured ? 0.26 : 0.18) : .clear,
                    radius: isFeatured ? 10 : 6,
                    y: isFeatured ? 5 : 3
                )

            Image(systemName: progress.achievement.systemImage)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: max(size * 0.38, 18), weight: .semibold))
                .foregroundColor(progress.isUnlocked ? .white : tint.opacity(0.78))
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            statusMarker
        }
    }

    @ViewBuilder
    private var statusMarker: some View {
        let markerSize = max(size * 0.28, 15)

        if progress.isUnlocked {
            Image(systemName: "checkmark")
                .font(.system(size: markerSize * 0.54, weight: .bold))
                .foregroundColor(.white)
                .frame(width: markerSize, height: markerSize)
                .background(Circle().fill(PhotoDeleteStyle.positive))
                .overlay(Circle().stroke(PhotoDeleteStyle.surface, lineWidth: 2))
        } else {
            Image(systemName: "lock.fill")
                .font(.system(size: markerSize * 0.48, weight: .bold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
                .frame(width: markerSize, height: markerSize)
                .background(Circle().fill(PhotoDeleteStyle.elevatedSurface))
                .overlay(Circle().stroke(PhotoDeleteStyle.surface, lineWidth: 1.5))
        }
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
