//
//  TimeOrganizeView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/21/26.
//

import SwiftUI

struct TimeOrganizeView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedScope: AdvancedTimeScope = .month
    @State private var visiblePeriodLimit = 24

    private let visibleScopes: [AdvancedTimeScope] = [.month]
    private let periodLimitStep = 24

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                LazyVStack(spacing: 16) {
                    if visibleScopes.count > 1 {
                        Picker(L10n.string("时间维度"), selection: $selectedScope) {
                            ForEach(visibleScopes) { scope in
                                Text(scope.title)
                                    .tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if shouldShowPreparingState {
                        OrganizeLoadingCard(
                            title: L10n.string("正在整理时间线"),
                            message: L10n.string("读取完成后会显示可整理的日期、月份和年份。"),
                            progress: dataManager.photoLibraryManager.loadingProgress
                        )
                    } else if visibleSummaries.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visibleSummaries.enumerated()), id: \.element.id) { index, summary in
                                NavigationLink(value: SwipeViewDestination.period(summary.scope, summary.intervalStart)) {
                                    TimePeriodRow(summary: summary)
                                }
                                .buttonStyle(.plain)

                                if index != visibleSummaries.count - 1 {
                                    Divider()
                                        .background(PhotoDeleteStyle.hairline)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .photoDeleteCard()

                        if hasMorePeriods {
                            Button(action: showMorePeriods) {
                                Text(L10n.string("显示更多"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(PhotoDeleteStyle.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .photoDeleteMinimumTapTarget()
                        }
                    }
                }
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, PhotoDeleteStyle.rootContentTopSpacing)
                .padding(.bottom, 96)
                .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L10n.string("时间"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            refreshSummaries()
        }
        .onChange(of: selectedScope) { _ in
            visiblePeriodLimit = periodLimitStep
            refreshSummaries()
        }
        .onChange(of: dataManager.cleanupStatsRevision) { _ in
            refreshSummaries(resetCachedScopes: true)
        }
        .onReceive(dataManager.photoLibraryManager.$allPhotos) { _ in
            refreshSummaries(resetCachedScopes: true)
        }
    }

    private var allVisibleSummaries: [PhotoPeriodSummary] {
        VisibleListPagination.filteredItems(
            dataManager.periodSummariesByScope[selectedScope] ?? [],
            include: { $0.assetCount > 0 }
        )
    }

    private var visibleSummaries: [PhotoPeriodSummary] {
        VisibleListPagination.visibleItems(allVisibleSummaries, limit: visiblePeriodLimit)
    }

    private var hasMorePeriods: Bool {
        VisibleListPagination.hasMore(totalCount: allVisibleSummaries.count, limit: visiblePeriodLimit)
    }

    private var shouldShowPreparingState: Bool {
        dataManager.isPreparingLibrary ||
            dataManager.photoLibraryManager.isLoading ||
            (
                dataManager.photoLibraryManager.hasPhotoLibraryAccess &&
                !dataManager.photoLibraryManager.hasLoadedPhotoLibrary &&
                dataManager.periodSummariesByScope.isEmpty
            ) ||
            (dataManager.isLoadingPeriodSummaries && visibleSummaries.isEmpty)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar")
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.secondaryText)

            Text(L10n.string("还没有可按时间整理的照片"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            Text(L10n.string("当前授权范围内没有带拍摄时间的照片。"))
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .photoDeleteCard()
    }

    private func refreshSummaries(resetCachedScopes: Bool = false) {
        guard dataManager.photoLibraryManager.hasPhotoLibraryAccess else {
            return
        }

        dataManager.refreshPhotoPeriodSummaries(
            for: [selectedScope],
            resetCachedScopes: resetCachedScopes
        )
    }

    private func showMorePeriods() {
        withAnimation(.easeInOut(duration: 0.18)) {
            visiblePeriodLimit = VisibleListPagination.advancedLimit(
                totalCount: allVisibleSummaries.count,
                currentLimit: visiblePeriodLimit,
                step: periodLimitStep
            )
        }
    }
}

private struct TimePeriodRow: View {
    let summary: PhotoPeriodSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(TimeOrganizeFormatter.title(for: summary))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)

                Text(TimeOrganizeFormatter.subtitle(for: summary))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            Text(L10n.shortPhotoCount(summary.assetCount))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct OrganizeLoadingCard: View {
    let title: String
    let message: String
    let progress: Double

    var body: some View {
        VStack(spacing: 16) {
            if progress > 0.01 {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    .frame(maxWidth: 230)
                    .clipShape(Capsule(style: .continuous))
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    .scaleEffect(1.05)
            }

            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(message)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .photoDeleteCard()
    }
}

private enum TimeOrganizeFormatter {
    static func title(for summary: PhotoPeriodSummary) -> String {
        switch summary.scope {
        case .day:
            return AppDateFormatter.string(from: summary.intervalStart, template: "MMMEd")
        case .week:
            return AdvancedTimeScope.week.title
        case .month:
            return AppDateFormatter.string(from: summary.intervalStart, template: "yMMM")
        case .year:
            return AppDateFormatter.string(from: summary.intervalStart, template: "y")
        }
    }

    static func subtitle(for summary: PhotoPeriodSummary) -> String {
        String(
            format: L10n.string("剩余 %lld 张 · 共 %lld 张"),
            Int64(summary.remainingCount),
            Int64(summary.assetCount)
        )
    }
}

#Preview {
    NavigationStack {
        TimeOrganizeView()
            .environmentObject(DataManager())
    }
}
