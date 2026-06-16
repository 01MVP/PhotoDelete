//
//  AdvancedView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/11/26.
//

import SwiftUI
import Photos
import Combine

struct AdvancedView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedScope: AdvancedTimeScope = .month
    @State private var selectedPeriodDate = Date()
    @State private var dashboardSnapshot = AdvancedLibrarySnapshot.demo(referenceDate: Date())
    @State private var periodSummariesByScope: [AdvancedTimeScope: [PhotoPeriodSummary]] = [:]
    @State private var activePeriodRoute: AdvancedPeriodRoute?
    @State private var advancedRefreshWorkItem: DispatchWorkItem?
    @State private var lastDashboardRefreshKey: AdvancedDashboardRefreshKey?
    @State private var showingSupporterBenefits = false

    private var isLocked: Bool {
        !purchaseManager.isSupporter
    }

    private var isAwaitingPhotoLibraryAccess: Bool {
        !isLocked && !dataManager.photoLibraryManager.hasPhotoLibraryAccess
    }

    private var entitlementStatusMessage: String? {
        switch purchaseManager.entitlementState {
        case .unknown, .verifying, .verified, .cachedOffline, .locked:
            nil
        }
    }

    private var headerSubtitle: String {
        if isLocked {
            L10n.string("示例展示，解锁后查看真实清理队列")
        } else if isAwaitingPhotoLibraryAccess {
            L10n.string("进阶功能需要读取本机照片库，才能生成真实月份进度和清理队列。")
        } else {
            L10n.string("按日周月年和清理队列整理照片")
        }
    }

    var body: some View {
        NavigationStack {
            advancedRootContent
                .navigationTitle(L10n.string("进阶"))
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(isPresented: isShowingActivePeriodRoute) {
                    if let activePeriodRoute {
                        AdvancedPeriodSwipeDestination(
                            scope: activePeriodRoute.scope,
                            intervalStart: activePeriodRoute.intervalStart
                        )
                            .environmentObject(dataManager)
                    }
                }
        }
        .onChange(of: selectedScope) { _ in
            selectedPeriodDate = Date()
        }
        .onChange(of: purchaseManager.entitlementState) { _ in
            refreshAdvancedDashboard(resetSelectedPeriod: true, force: true)
        }
        .onChange(of: dataManager.cleanupStatsRevision) { _ in
            scheduleAdvancedDashboardRefresh()
        }
        .onReceive(dataManager.photoLibraryManager.$isLoading) { isLoading in
            if !isLoading {
                scheduleAdvancedDashboardRefresh()
            }
        }
        .onReceive(dataManager.photoLibraryManager.$allPhotos) { _ in
            guard !isPreparingRealAdvancedData else { return }
            scheduleAdvancedDashboardRefresh()
        }
        .task {
            dataManager.syncPhotoLibraryAuthorization()
            refreshAdvancedDashboard(resetSelectedPeriod: true)
        }
    }

    private var advancedRootContent: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                let snapshot = dashboardSnapshot
                let periodSummaries = visiblePeriodSummaries
                let selectedPeriod = selectedPeriodSummary(in: periodSummaries)

                VStack(spacing: 18) {
                    rootStatusText
                    achievementEntry

                    VStack(spacing: 18) {
                        if isAwaitingPhotoLibraryAccess {
                            PhotoAuthorizationCard(
                                subtitle: L10n.string("进阶功能需要读取本机照片库，才能生成真实月份进度和清理队列。"),
                                onRequestAccess: { dataManager.requestPhotoLibraryAccess() }
                            )
                        } else if shouldShowAdvancedPreparingCard {
                            AdvancedLibraryPreparingCard(progress: advancedLoadingProgress)
                        } else {
                            AdvancedTimeScopePicker(selectedScope: $selectedScope)

                            AdvancedPeriodNavigator(
                                summary: selectedPeriod,
                                canGoForward: canAdvance(from: selectedPeriod),
                                onPrevious: { moveSelectedPeriod(by: -1) },
                                onNext: { moveSelectedPeriod(by: 1) }
                            )

                            AdvancedPeriodProgressCard(summary: selectedPeriod, isDemo: isLocked)

                            periodProgressSection(
                                summaries: periodSummaries,
                                selectedPeriod: selectedPeriod,
                                isLocked: isLocked
                            )

                            periodActionCard(summary: selectedPeriod, isLocked: isLocked)

                            cleanupEntrySection(
                                queues: snapshot.cleanupQueues,
                                isLocked: isLocked
                            )
                        }
                    }
                    .opacity(isLocked ? 0.42 : 1)
                    .redacted(reason: shouldRedactAdvancedContent ? .placeholder : [])
                    .allowsHitTesting(!isLocked && !shouldRedactAdvancedContent)
                    .accessibilityHidden(isLocked || shouldRedactAdvancedContent)

                    Spacer()
                        .frame(height: isLocked ? 24 : 96)
                }
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, PhotoDeleteStyle.rootContentTopSpacing)
                .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isLocked {
                AdvancedBottomPaywall(
                    priceText: purchaseManager.supporterPriceText,
                    isLoading: purchaseManager.isLoading,
                    errorMessage: purchaseManager.errorMessage,
                    statusMessage: entitlementStatusMessage,
                    onPurchase: purchaseSupporter,
                    onRestore: restorePurchases,
                    onShowBenefits: { showingSupporterBenefits = true }
                )
            }
        }
        .sheet(isPresented: $showingSupporterBenefits) {
            SupporterBenefitsSheet()
        }
    }

    private var visiblePeriodSummaries: [PhotoPeriodSummary] {
        if let summaries = periodSummariesByScope[selectedScope] {
            return summaries
        }
        return demoPeriodSummaries(for: selectedScope)
    }

    private var isPreparingRealAdvancedData: Bool {
        !isLocked &&
            dataManager.photoLibraryManager.hasPhotoLibraryAccess &&
            (
                dataManager.isPreparingLibrary ||
                dataManager.photoLibraryManager.isLoading ||
                !dataManager.photoLibraryManager.hasLoadedPhotoLibrary
            )
    }

    private var shouldShowAdvancedPreparingCard: Bool {
        isPreparingRealAdvancedData &&
            !dataManager.photoLibraryManager.hasCachedPhotoLibrarySnapshot
    }

    private var shouldRedactAdvancedContent: Bool {
        !isLocked &&
            dataManager.photoLibraryManager.hasPhotoLibraryAccess &&
            !dataManager.photoLibraryManager.hasLoadedPhotoLibrary &&
            dataManager.photoLibraryManager.hasCachedPhotoLibrarySnapshot
    }

    private var shouldDeferAdvancedDashboardRefresh: Bool {
        !isLocked &&
            dataManager.photoLibraryManager.hasPhotoLibraryAccess &&
            !dataManager.photoLibraryManager.hasLoadedPhotoLibrary
    }

    private var advancedLoadingProgress: Double {
        let progress = dataManager.photoLibraryManager.loadingProgress
        guard progress > 0 else { return 0.04 }
        return min(max(progress, 0.04), 1)
    }

    private var dashboardRefreshKey: AdvancedDashboardRefreshKey {
        AdvancedDashboardRefreshKey(
            isLocked: isLocked,
            hasPhotoLibraryAccess: dataManager.photoLibraryManager.hasPhotoLibraryAccess,
            isPreparingRealAdvancedData: isPreparingRealAdvancedData,
            allPhotoCount: dataManager.photoLibraryManager.allPhotos.count,
            screenshotCount: dataManager.photoLibraryManager.screenshots.count,
            videoCount: dataManager.photoLibraryManager.videos.count,
            reviewedCount: dataManager.reviewedAssetIDs.count,
            deleteCandidateCount: dataManager.deleteCandidates.count,
            favoriteCandidateCount: dataManager.favoriteCandidates.count,
            cleanupStatsRevision: dataManager.cleanupStatsRevision
        )
    }

    private var isShowingActivePeriodRoute: Binding<Bool> {
        Binding(
            get: { activePeriodRoute != nil },
            set: { isPresented in
                if !isPresented {
                    activePeriodRoute = nil
                }
            }
        )
    }

    private var rootStatusText: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PhotoDeleteStyle.secondaryText)
                    .accessibilityHidden(true)
            }

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(PhotoDeleteStyle.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var achievementEntry: some View {
        NavigationLink {
            CleanupAchievementsView(statsStore: dataManager.cleanupStatsStore)
        } label: {
            CleanupAchievementsEntryCard(statsStore: dataManager.cleanupStatsStore)
        }
        .buttonStyle(.plain)
    }

    private func periodProgressSection(
        summaries: [PhotoPeriodSummary],
        selectedPeriod: PhotoPeriodSummary,
        isLocked: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("时间进度"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Spacer()

                if !isLocked, !summaries.isEmpty {
                    NavigationLink {
                        AdvancedPeriodListView(summaries: summaries)
                            .environmentObject(dataManager)
                    } label: {
                        Text(L10n.string("全部"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(L10n.string("示例"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.tertiaryText)
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(summaries.prefix(18)) { summary in
                        Button {
                            selectedPeriodDate = summary.intervalStart
                            activePeriodRoute = AdvancedPeriodRoute(
                                scope: summary.scope,
                                intervalStart: summary.intervalStart
                            )
                        } label: {
                            AdvancedPeriodChip(
                                summary: summary,
                                isSelected: summary.id == selectedPeriod.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func periodActionCard(
        summary: PhotoPeriodSummary,
        isLocked: Bool
    ) -> some View {
        Group {
            if isLocked {
                Button(action: purchaseSupporter) {
                    AdvancedPeriodActionContent(summary: summary)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    AdvancedPeriodSwipeDestination(
                        scope: summary.scope,
                        intervalStart: summary.intervalStart
                    )
                        .environmentObject(dataManager)
                } label: {
                    AdvancedPeriodActionContent(summary: summary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cleanupEntrySection(
        queues: [AdvancedCleanupQueue],
        isLocked: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("清理入口"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Spacer()

                Text(isLocked ? L10n.string("示例") : L10n.string("专门列表"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.tertiaryText)
            }

            VStack(spacing: 0) {
                ForEach(Array(queues.enumerated()), id: \.element.id) { index, queue in
                    if isLocked {
                        Button(action: purchaseSupporter) {
                            AdvancedCleanupEntryRow(queue: queue, isLocked: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            cleanupDestination(for: queue.kind)
                        } label: {
                            AdvancedCleanupEntryRow(queue: queue, isLocked: false)
                        }
                        .buttonStyle(.plain)
                    }

                    if index != queues.count - 1 {
                        Divider()
                            .background(PhotoDeleteStyle.hairline)
                            .padding(.leading, 62)
                    }
                }
            }
            .photoDeleteCard()
        }
    }

    @ViewBuilder
    private func cleanupDestination(for kind: AdvancedCleanupKind) -> some View {
        switch kind {
        case .similarPhotos:
            AdvancedSimilarPhotoGroupsView()
                .environmentObject(dataManager)
        case .videoCompression:
            AdvancedVideoCompressionView()
                .environmentObject(dataManager)
        case .largeFiles, .screenshots, .videos:
            AdvancedAssetListView(mode: .cleanup(kind))
                .environmentObject(dataManager)
        }
    }

    private func selectedPeriodSummary(in summaries: [PhotoPeriodSummary]) -> PhotoPeriodSummary {
        let selectedInterval = Calendar.current.dateInterval(for: selectedScope, containing: selectedPeriodDate)
        if let selected = summaries.first(where: { Calendar.current.isDate($0.intervalStart, inSameDayAs: selectedInterval.start) || $0.intervalStart == selectedInterval.start }) {
            return selected
        }

        if let containing = summaries.first(where: { selectedPeriodDate >= $0.intervalStart && selectedPeriodDate < $0.intervalEnd }) {
            return containing
        }

        return PhotoPeriodSummary.empty(scope: selectedScope, containing: selectedPeriodDate)
    }

    private func demoPeriodSummaries(for scope: AdvancedTimeScope) -> [PhotoPeriodSummary] {
        let calendar = Calendar.current
        let currentInterval = calendar.dateInterval(for: scope, containing: Date.now)
        let count = demoPeriodCount(for: scope)
        var summaries: [PhotoPeriodSummary] = []
        summaries.reserveCapacity(count)

        for index in 0..<count {
            guard let start = calendar.date(
                byAdding: scope.calendarComponent,
                value: -index,
                to: currentInterval.start
            ) else { continue }

            let interval = calendar.dateInterval(for: scope, containing: start)
            let base = max(1, count - index)
            let assetCount = demoAssetCount(for: scope, base: base)
            let reviewedCount = demoReviewedCount(assetCount: assetCount, index: index)

            summaries.append(
                PhotoPeriodSummary(
                    scope: scope,
                    intervalStart: interval.start,
                    intervalEnd: interval.end,
                    assetCount: assetCount,
                    screenshotCount: max(assetCount / 5, 0),
                    videoCount: max(assetCount / 16, 0),
                    reviewedCount: reviewedCount,
                    estimatedSizeMB: demoEstimatedSizeMB(for: scope, assetCount: assetCount)
                )
            )
        }

        return summaries
    }

    private func demoPeriodCount(for scope: AdvancedTimeScope) -> Int {
        switch scope {
        case .day:
            return 14
        case .week:
            return 12
        case .month:
            return 18
        case .year:
            return 5
        }
    }

    private func demoAssetCount(for scope: AdvancedTimeScope, base: Int) -> Int {
        switch scope {
        case .day:
            return 18 + base * 3
        case .week:
            return 72 + base * 9
        case .month:
            return 320 + base * 42
        case .year:
            return 1_800 + base * 220
        }
    }

    private func demoReviewedCount(assetCount: Int, index: Int) -> Int {
        let progress = min(0.82, 0.28 + Double(index % 6) * 0.1)
        return Int(Double(assetCount) * progress)
    }

    private func demoEstimatedSizeMB(for scope: AdvancedTimeScope, assetCount: Int) -> Double {
        let averageAssetSizeMB: Double
        switch scope {
        case .day, .week, .month:
            averageAssetSizeMB = 3.1
        case .year:
            averageAssetSizeMB = 3.8
        }
        return Double(assetCount) * averageAssetSizeMB
    }

    private func moveSelectedPeriod(by offset: Int) {
        guard let next = Calendar.current.date(
            byAdding: selectedScope.calendarComponent,
            value: offset,
            to: selectedPeriodDate
        ) else { return }

        guard offset < 0 || canAdvance(to: next) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            selectedPeriodDate = next
        }
        HapticManager.impact(.light)
    }

    private func canAdvance(from summary: PhotoPeriodSummary) -> Bool {
        guard let next = Calendar.current.date(
            byAdding: selectedScope.calendarComponent,
            value: 1,
            to: summary.intervalStart
        ) else { return false }
        return canAdvance(to: next)
    }

    private func canAdvance(to date: Date) -> Bool {
        let nextStart = Calendar.current.dateInterval(for: selectedScope, containing: date).start
        let currentStart = Calendar.current.dateInterval(for: selectedScope, containing: Date()).start
        return nextStart <= currentStart
    }

    private func purchaseSupporter() {
        Task { await purchaseManager.purchaseSupporter() }
    }

    private func restorePurchases() {
        Task { await purchaseManager.restorePurchases() }
    }

    private func scheduleAdvancedDashboardRefresh() {
        advancedRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            refreshAdvancedDashboard(resetSelectedPeriod: false)
        }
        advancedRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func refreshAdvancedDashboard(resetSelectedPeriod: Bool, force: Bool = false) {
        if resetSelectedPeriod {
            selectedPeriodDate = Date()
        }

        guard !shouldDeferAdvancedDashboardRefresh else { return }
        let refreshKey = dashboardRefreshKey
        guard force || refreshKey != lastDashboardRefreshKey else { return }
        lastDashboardRefreshKey = refreshKey

        if isLocked || !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
            dashboardSnapshot = AdvancedLibrarySnapshot.demo(referenceDate: Date())
            periodSummariesByScope = Dictionary(
                uniqueKeysWithValues: AdvancedTimeScope.allCases.map { scope in
                    (scope, demoPeriodSummaries(for: scope))
                }
            )
            return
        }

        dashboardSnapshot = AdvancedLibrarySnapshot(
            stats: dataManager.makeSettingsStatsSummary(),
            daySummaries: [],
            monthSummaries: [],
            cleanupQueues: dataManager.makeAdvancedCleanupQueues()
        )
        periodSummariesByScope = dataManager.makePhotoPeriodSummariesByScope()
    }
}

private struct AdvancedDashboardRefreshKey: Equatable {
    let isLocked: Bool
    let hasPhotoLibraryAccess: Bool
    let isPreparingRealAdvancedData: Bool
    let allPhotoCount: Int
    let screenshotCount: Int
    let videoCount: Int
    let reviewedCount: Int
    let deleteCandidateCount: Int
    let favoriteCandidateCount: Int
    let cleanupStatsRevision: UUID
}

private struct AdvancedPeriodRoute: Identifiable, Hashable {
    let scope: AdvancedTimeScope
    let intervalStart: Date

    var id: String {
        PhotoPeriodSummary.empty(scope: scope, containing: intervalStart).id
    }
}

private struct AdvancedPeriodSwipeDestination: View {
    let scope: AdvancedTimeScope
    let intervalStart: Date

    var body: some View {
        SwipePhotoView(
            selectedCategory: nil,
            selectedTimeGroup: nil,
            selectedAlbumInfo: nil,
            selectedDate: intervalStart,
            selectedAdvancedTimeScope: scope
        )
    }
}

private struct AdvancedTimeScopePicker: View {
    @Binding var selectedScope: AdvancedTimeScope

    var body: some View {
        Picker(L10n.string("时间维度"), selection: $selectedScope) {
            ForEach(AdvancedTimeScope.allCases) { scope in
                Text(scope.title)
                    .tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct AdvancedPeriodNavigator: View {
    let summary: PhotoPeriodSummary
    let canGoForward: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) {
                Label(L10n.string("上一段时间"), systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(PhotoDeleteStyle.surface))
                    .photoDeleteMinimumTapTarget()
            }
            .buttonStyle(.plain)
            .foregroundColor(PhotoDeleteStyle.primaryText)

            VStack(spacing: 3) {
                Text(AdvancedPeriodFormatter.title(for: summary))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(AdvancedPeriodFormatter.subtitle(for: summary))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)

            Button(action: onNext) {
                Label(L10n.string("下一段时间"), systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(PhotoDeleteStyle.surface))
                    .photoDeleteMinimumTapTarget()
            }
            .buttonStyle(.plain)
            .foregroundColor(canGoForward ? PhotoDeleteStyle.primaryText : PhotoDeleteStyle.tertiaryText)
            .disabled(!canGoForward)
        }
        .padding(12)
        .photoDeleteCard()
    }
}

private struct AdvancedPeriodProgressCard: View {
    let summary: PhotoPeriodSummary
    let isDemo: Bool

    var body: some View {
        HStack(spacing: 16) {
            AdvancedProgressRing(progress: summary.progress, size: 78, lineWidth: 8) {
                Text("\(Int(summary.progress * 100))%")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(L10n.string("\(AdvancedPeriodFormatter.compactTitle(for: summary))清理进度"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        if isDemo {
                            AdvancedDemoTag()
                        }
                    }

                    Text(L10n.string("已整理 \(summary.reviewedCount)/\(summary.assetCount) 项，预计占用 \(summary.formattedEstimatedSize)。"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                HStack(spacing: 6) {
                    AdvancedMiniMetric(title: L10n.string("照片"), value: "\(summary.assetCount)")
                    AdvancedMiniMetric(title: L10n.string("视频"), value: "\(summary.videoCount)")
                    AdvancedMiniMetric(title: L10n.string("截图"), value: "\(summary.screenshotCount)")
                }
            }
        }
        .padding(16)
        .photoDeleteCard()
    }
}

private struct AdvancedMiniMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
        )
    }
}

private struct AdvancedPeriodChip: View {
    let summary: PhotoPeriodSummary
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                AdvancedProgressRing(progress: summary.progress, size: 34, lineWidth: 4) {
                    EmptyView()
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(AdvancedPeriodFormatter.chipTitle(for: summary))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .lineLimit(1)

                    Text(L10n.string("\(summary.assetCount) 项 · \(Int(summary.progress * 100))%"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 94, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? PhotoDeleteStyle.accent.opacity(0.16) : PhotoDeleteStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? PhotoDeleteStyle.accent.opacity(0.65) : PhotoDeleteStyle.hairline, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(Text(isSelected ? L10n.string("已选") : L10n.string("未选择")))
    }
}

private struct AdvancedPeriodActionContent: View {
    let summary: PhotoPeriodSummary

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PhotoDeleteStyle.accent.opacity(0.16))
                    .frame(width: 42, height: 42)

                Image(systemName: summary.scope == .day ? "calendar" : "calendar.badge.checkmark")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.scope.actionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(L10n.string("剩余 \(summary.remainingCount) 项，\(summary.scope.rangeDescription)"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct AdvancedCleanupEntryRow: View {
    let queue: AdvancedCleanupQueue
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(
                icon: queue.kind.icon,
                tint: queue.kind.tint,
                size: 38,
                cornerRadius: 11
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(queue.kind.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    if isLocked {
                        AdvancedDemoTag()
                    }
                }

                Text(L10n.string("\(queue.assetCount) 项 · \(queue.formattedSpace) · \(queue.kind.subtitle)"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer()

            Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

private struct AdvancedBottomPaywall: View {
    let priceText: String
    let isLoading: Bool
    let errorMessage: String?
    let statusMessage: String?
    let onPurchase: () -> Void
    let onRestore: () -> Void
    let onShowBenefits: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Capsule(style: .continuous)
                .fill(PhotoDeleteStyle.hairline)
                .frame(width: 38, height: 4)
                .padding(.bottom, 4)

            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(L10n.string("解锁全部进阶功能"))
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(L10n.string("一次性解锁按日期清理、大文件清理、视频压缩和相似照片清理。"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button(action: onPurchase) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.primaryButtonText))
                            .scaleEffect(0.78)
                    }
                    Text(isLoading ? L10n.string("处理中...") : String(format: L10n.string("一次性解锁 %@"), priceText))
                }
            }
            .photoDeletePrimaryButton()
            .disabled(isLoading)

            Button(action: onRestore) {
                Text(L10n.string("恢复购买"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            Button(action: onShowBenefits) {
                Text(L10n.string("查看免费版与支持者版区别"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .underline()
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PhotoDeleteStyle.background.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct AdvancedLibraryPreparingCard: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 13) {
                ZStack {
                    Circle()
                        .fill(PhotoDeleteStyle.accent.opacity(0.14))
                        .frame(width: 42, height: 42)

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                        .scaleEffect(0.82)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("正在整理照片数据"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(L10n.string("首次打开会在本机扫描照片、截图和视频，完成后自动显示真实进阶入口。"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                .accessibilityLabel(L10n.string("照片数据整理进度"))
        }
        .padding(16)
        .photoDeleteCard()
    }
}

private struct AdvancedPeriodListView: View {
    @EnvironmentObject var dataManager: DataManager
    let summaries: [PhotoPeriodSummary]

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                            NavigationLink {
                                AdvancedPeriodSwipeDestination(
                                    scope: summary.scope,
                                    intervalStart: summary.intervalStart
                                )
                                    .environmentObject(dataManager)
                            } label: {
                                AdvancedPeriodListRow(summary: summary)
                            }
                            .buttonStyle(.plain)

                            if index != summaries.count - 1 {
                                Divider()
                                    .background(PhotoDeleteStyle.hairline)
                                    .padding(.leading, 70)
                            }
                        }
                    }
                    .photoDeleteCard()

                    Spacer()
                        .frame(height: 72)
                }
                .padding(PhotoDeleteStyle.screenHorizontalPadding)
            }
        }
        .advancedDetailNavigation(title: L10n.string("时间进度"))
    }
}

private struct AdvancedPeriodListRow: View {
    let summary: PhotoPeriodSummary

    var body: some View {
        HStack(spacing: 13) {
            AdvancedProgressRing(progress: summary.progress, size: 40, lineWidth: 4) {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(AdvancedPeriodFormatter.title(for: summary))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(L10n.string("\(summary.assetCount) 项 · 已整理 \(Int(summary.progress * 100))% · \(summary.formattedEstimatedSize)"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

private struct AdvancedAssetListView: View {
    @EnvironmentObject var dataManager: DataManager
    let mode: AdvancedAssetListMode

    @State private var assets: [PHAsset] = []
    @State private var totalSizeMB: Double = 0
    @State private var selectedAssetIDs: Set<String> = []
    @State private var showBatchConfirm = false
    @State private var previewAsset: AdvancedPreviewAsset?

    private var selectedAssets: [PHAsset] {
        assets.filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(spacing: 14) {
                    if case .cleanup(let kind) = mode {
                        AdvancedFilterPills(kind: kind)
                    }

                    AdvancedAssetListSummaryCard(
                        title: summaryTitle,
                        subtitle: summarySubtitle,
                        buttonTitle: selectedAssetIDs.isEmpty ? L10n.string("选择") : L10n.string("取消"),
                        action: toggleBulkSelection
                    )

                    if assets.isEmpty {
                        AdvancedEmptyState(
                            icon: mode.icon,
                            title: L10n.string("没有可整理的内容"),
                            subtitle: L10n.string("当前照片库里暂时没有符合这个入口的项目。")
                        )
                    } else {
                        LazyVStack(spacing: 9) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                AdvancedAssetRow(
                                    asset: asset,
                                    photoLibraryManager: dataManager.photoLibraryManager,
                                    estimatedSizeMB: dataManager.estimatedSizeMB(for: asset),
                                    isSelected: selectedAssetIDs.contains(asset.localIdentifier),
                                    onToggleSelection: { toggleSelection(asset) },
                                    onPreview: { previewAsset = AdvancedPreviewAsset(asset: asset) }
                                )
                            }
                        }
                    }

                    Spacer()
                        .frame(height: 24)
                }
                .padding(PhotoDeleteStyle.screenHorizontalPadding)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selectedAssetIDs.isEmpty {
                AdvancedSelectionActionBar(
                    count: selectedAssetIDs.count,
                    action: addSelectedAssetsToDeleteCandidates
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .advancedDetailNavigation(title: mode.title)
        .fullScreenCover(isPresented: $showBatchConfirm, onDismiss: {
            selectedAssetIDs.removeAll()
            reloadAssets()
        }) {
            BatchConfirmView()
                .environmentObject(dataManager)
        }
        .sheet(item: $previewAsset) { item in
            AdvancedAssetPreviewView(
                asset: item.asset,
                photoLibraryManager: dataManager.photoLibraryManager
            )
        }
        .task(id: mode.id) {
            reloadAssets()
        }
    }

    private var summaryTitle: String {
        switch mode {
        case .cleanup(.largeFiles):
            return L10n.string("共 \(assets.count) 个大文件")
        case .cleanup(.videoCompression):
            return L10n.string("共 \(assets.count) 个可压缩视频")
        case .cleanup(.screenshots):
            return L10n.string("共 \(assets.count) 张截图")
        case .cleanup(.videos):
            return L10n.string("共 \(assets.count) 个视频")
        case .cleanup(.similarPhotos):
            return L10n.string("共 \(assets.count) 张相似照片")
        }
    }

    private var summarySubtitle: String {
        switch mode {
        case .cleanup(.largeFiles):
            return L10n.string("按占用空间从大到小排序，合计约 \(CleanupStatsFormatter.space(totalSizeMB))。")
        case .cleanup(.videoCompression):
            return L10n.string("选择要生成压缩副本的视频，合计约 \(CleanupStatsFormatter.space(totalSizeMB))。")
        case .cleanup(.screenshots):
            return L10n.string("像相册一样浏览截图，合计约 \(CleanupStatsFormatter.space(totalSizeMB))。")
        case .cleanup(.videos):
            return L10n.string("按视频占用优先处理，合计约 \(CleanupStatsFormatter.space(totalSizeMB))。")
        case .cleanup(.similarPhotos):
            return L10n.string("建议优先处理相似组，合计约 \(CleanupStatsFormatter.space(totalSizeMB))。")
        }
    }

    private func reloadAssets() {
        let loadedAssets: [PHAsset]
        switch mode {
        case .cleanup(let kind):
            loadedAssets = dataManager.getPhotosForAdvancedCleanup(kind)
        }

        assets = loadedAssets
        totalSizeMB = loadedAssets.reduce(0) { $0 + dataManager.estimatedSizeMB(for: $1) }
        selectedAssetIDs = selectedAssetIDs.filter { selectedID in
            loadedAssets.contains { $0.localIdentifier == selectedID }
        }
    }

    private func toggleSelection(_ asset: PHAsset) {
        HapticManager.impact(.light)
        let id = asset.localIdentifier
        if selectedAssetIDs.contains(id) {
            selectedAssetIDs.remove(id)
        } else {
            selectedAssetIDs.insert(id)
        }
    }

    private func toggleBulkSelection() {
        HapticManager.impact(.light)
        if selectedAssetIDs.isEmpty {
            selectedAssetIDs = Set(assets.prefix(20).map(\.localIdentifier))
        } else {
            selectedAssetIDs.removeAll()
        }
    }

    private func addSelectedAssetsToDeleteCandidates() {
        let assets = selectedAssets
        guard !assets.isEmpty else { return }
        for asset in assets {
            _ = dataManager.markReviewed(asset)
            dataManager.addToDeleteCandidates(asset)
        }
        HapticManager.notify(.success)
        showBatchConfirm = true
    }
}

private struct AdvancedVideoCompressionView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var assets: [PHAsset] = []
    @State private var totalSizeMB: Double = 0
    @State private var videoSizeMBByAssetID: [String: Double] = [:]
    @State private var selectedAssetIDs: Set<String> = []
    @State private var compressionPlan: VideoCompressionPlan = .default
    @State private var isCompressing = false
    @State private var processedVideoCount = 0
    @State private var compressionTotalCount = 0
    @State private var currentCompressionProgress: Double = 0
    @State private var currentCompressionMessage: String?
    @State private var compressionErrorMessage: String?
    @State private var compressionResult: AdvancedVideoCompressionResult?
    @State private var showingCompressionCompletion = false
    @State private var previewAsset: AdvancedPreviewAsset?
    @State private var showBatchConfirm = false
    @State private var compressionOptionsContext: AdvancedVideoCompressionOptionsContext?
    @State private var compressionTask: Task<Void, Never>?
    @State private var sizeLoadingTask: Task<Void, Never>?

    private var selectedAssets: [PHAsset] {
        assets.filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var selectedCompressionEstimate: VideoCompressionEstimate {
        dataManager.estimatedVideoCompressionEstimate(
            for: selectedAssets,
            plan: compressionPlan,
            knownOriginalSizeMBByAssetID: videoSizeMBByAssetID
        )
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(spacing: 14) {
                    if isCompressing {
                        AdvancedVideoCompressionProgressCard(
                            processedCount: processedVideoCount,
                            totalCount: compressionTotalCount,
                            currentProgress: currentCompressionProgress,
                            message: currentCompressionMessage
                        )
                    }

                    if let compressionResult {
                        AdvancedVideoCompressionResultCard(
                            result: compressionResult,
                            onPreview: previewCompressedVideo,
                            onDeleteOriginals: queueOriginalVideosForDeletion
                        )
                    }

                    if let compressionErrorMessage {
                        AdvancedVideoCompressionMessageCard(
                            icon: "exclamationmark.triangle.fill",
                            message: compressionErrorMessage,
                            tint: PhotoDeleteStyle.warning
                        )
                    }

                    if assets.isEmpty {
                        AdvancedEmptyState(
                            icon: AdvancedCleanupKind.videoCompression.icon,
                            title: L10n.string("未找到可压缩的视频"),
                            subtitle: L10n.string("当前照片库里暂时没有可压缩的视频。")
                        )
                    } else {
                        AdvancedVideoCompressionListHeader(
                            count: assets.count,
                            totalSizeMB: totalSizeMB,
                            selectedCount: selectedAssetIDs.count,
                            isDisabled: isCompressing,
                            action: toggleBulkSelection
                        )

                        LazyVStack(spacing: 9) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                AdvancedAssetRow(
                                    asset: asset,
                                    photoLibraryManager: dataManager.photoLibraryManager,
                                    estimatedSizeMB: displaySizeMB(for: asset),
                                    sizeText: displaySizeText(for: asset),
                                    isSelected: selectedAssetIDs.contains(asset.localIdentifier),
                                    onToggleSelection: { toggleSelection(asset) },
                                    onPreview: { previewAsset = AdvancedPreviewAsset(asset: asset) }
                                )
                            }
                        }
                    }

                    if !dataManager.videoCompressionHistoryStore.sessions.isEmpty {
                        AdvancedVideoCompressionHistoryCard(
                            sessions: Array(dataManager.videoCompressionHistoryStore.sessions.prefix(4)),
                            photoLibraryManager: dataManager.photoLibraryManager
                        )
                    }

                    Spacer()
                        .frame(height: 24)
                }
                .padding(PhotoDeleteStyle.screenHorizontalPadding)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selectedAssetIDs.isEmpty {
                AdvancedVideoCompressionActionBar(
                    count: selectedAssetIDs.count,
                    estimate: selectedCompressionEstimate,
                    processedCount: processedVideoCount,
                    isCompressing: isCompressing,
                    onCompress: presentCompressionOptions,
                    onDelete: deleteSelectedVideos
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .advancedDetailNavigation(title: AdvancedCleanupKind.videoCompression.title)
        .fullScreenCover(isPresented: $showBatchConfirm, onDismiss: {
            reloadAssets()
        }) {
            BatchConfirmView()
                .environmentObject(dataManager)
        }
        .alert(L10n.string("压缩完成"), isPresented: $showingCompressionCompletion) {
            if compressionResult?.createdAssetIdentifiers.isEmpty == false {
                Button(L10n.string("预览压缩副本")) {
                    previewCompressedVideo()
                }
            }
            if compressionResult?.hasMeaningfulSavings == true {
                Button(L10n.string("删除原视频"), role: .destructive) {
                    queueOriginalVideosForDeletion()
                }
            }
            Button(L10n.string("稍后"), role: .cancel) {}
        } message: {
            if let compressionResult {
                Text(compressionCompletionMessage(for: compressionResult))
            }
        }
        .sheet(item: $previewAsset) { item in
            AdvancedAssetPreviewView(
                asset: item.asset,
                photoLibraryManager: dataManager.photoLibraryManager
            )
        }
        .sheet(item: $compressionOptionsContext) { context in
            AdvancedVideoCompressionOptionsSheet(
                context: context,
                initialPlan: compressionPlan,
                knownOriginalSizeMBByAssetID: videoSizeMBByAssetID
            ) { plan, videos in
                compressionPlan = plan
                compressSelectedVideos(videos: videos, plan: plan)
            }
            .environmentObject(dataManager)
        }
        .task {
            reloadAssets()
        }
        .onDisappear {
            compressionTask?.cancel()
            sizeLoadingTask?.cancel()
        }
    }

    private func reloadAssets() {
        let loadedAssets = dataManager.getPhotosForAdvancedCleanup(.videoCompression)
        assets = loadedAssets
        totalSizeMB = loadedAssets.reduce(0) { $0 + displaySizeMB(for: $1) }
        selectedAssetIDs = selectedAssetIDs.filter { selectedID in
            loadedAssets.contains { $0.localIdentifier == selectedID }
        }
        loadVideoSizes(for: loadedAssets)
    }

    private func displaySizeMB(for asset: PHAsset) -> Double {
        videoSizeMBByAssetID[asset.localIdentifier] ?? dataManager.estimatedSizeMB(for: asset)
    }

    private func displaySizeText(for asset: PHAsset) -> String {
        guard let sizeMB = videoSizeMBByAssetID[asset.localIdentifier] else {
            return L10n.string("计算中")
        }
        return CleanupStatsFormatter.space(sizeMB)
    }

    private func refreshTotalSize() {
        totalSizeMB = assets.reduce(0) { $0 + displaySizeMB(for: $1) }
    }

    private func loadVideoSizes(for loadedAssets: [PHAsset]) {
        sizeLoadingTask?.cancel()
        sizeLoadingTask = Task {
            for asset in loadedAssets {
                if Task.isCancelled { break }
                let alreadyLoaded = await MainActor.run {
                    videoSizeMBByAssetID[asset.localIdentifier] != nil
                }
                if alreadyLoaded { continue }

                do {
                    let sizeMB = try await dataManager.photoLibraryManager.estimatedVideoFileSizeMB(for: asset)
                    await MainActor.run {
                        videoSizeMBByAssetID[asset.localIdentifier] = sizeMB
                        refreshTotalSize()
                    }
                } catch {
                    continue
                }
            }
        }
    }

    private func toggleSelection(_ asset: PHAsset) {
        guard !isCompressing else { return }
        HapticManager.impact(.light)
        let id = asset.localIdentifier
        if selectedAssetIDs.contains(id) {
            selectedAssetIDs.remove(id)
        } else {
            selectedAssetIDs.insert(id)
        }
        compressionResult = nil
        compressionErrorMessage = nil
    }

    private func toggleBulkSelection() {
        guard !isCompressing else { return }
        HapticManager.impact(.light)
        if selectedAssetIDs.isEmpty {
            selectedAssetIDs = Set(assets.prefix(12).map(\.localIdentifier))
        } else {
            selectedAssetIDs.removeAll()
        }
        compressionResult = nil
        compressionErrorMessage = nil
    }

    private func presentCompressionOptions() {
        let videos = selectedAssets
        guard !videos.isEmpty, !isCompressing else { return }
        compressionOptionsContext = AdvancedVideoCompressionOptionsContext(assets: videos)
    }

    private func deleteSelectedVideos() {
        let videos = selectedAssets
        guard !videos.isEmpty, !isCompressing else { return }

        for asset in videos {
            _ = dataManager.markReviewed(asset)
            dataManager.addToDeleteCandidates(asset)
        }
        HapticManager.notify(.warning)
        showBatchConfirm = true
    }

    private func compressSelectedVideos(videos: [PHAsset], plan: VideoCompressionPlan) {
        guard !videos.isEmpty, !isCompressing else { return }
        isCompressing = true
        processedVideoCount = 0
        compressionTotalCount = videos.count
        currentCompressionProgress = 0
        currentCompressionMessage = L10n.string("正在准备压缩")
        compressionErrorMessage = nil
        compressionResult = nil
        compressionTask?.cancel()
        compressionTask = Task {
            var resultItems: [AdvancedVideoCompressionResultItem] = []
            var failedCount = 0
            var firstErrorMessage: String?

            for (index, asset) in videos.enumerated() {
                if Task.isCancelled {
                    break
                }

                await MainActor.run {
                    processedVideoCount = index
                    currentCompressionProgress = 0
                    currentCompressionMessage = String(format: L10n.string("正在处理第 %lld 个视频"), Int64(index + 1))
                }

                do {
                    let result = try await dataManager.photoLibraryManager.compressVideo(
                        asset,
                        plan: plan
                    ) { progress, message in
                        currentCompressionProgress = progress
                        currentCompressionMessage = message
                    }
                    resultItems.append(AdvancedVideoCompressionResultItem(result: result))
                } catch is CancellationError {
                    break
                } catch {
                    failedCount += 1
                    if firstErrorMessage == nil {
                        firstErrorMessage = error.localizedDescription
                    }
                }

                await MainActor.run {
                    processedVideoCount = index + 1
                    currentCompressionProgress = 0
                }
            }

            let wasCancelled = Task.isCancelled
            await MainActor.run {
                isCompressing = false
                compressionTask = nil
                currentCompressionProgress = 0
                currentCompressionMessage = nil

                if !resultItems.isEmpty {
                    let completedResult = AdvancedVideoCompressionResult(
                        items: resultItems,
                        failedCount: failedCount,
                        completedAt: Date(),
                        plan: plan
                    )
                    compressionResult = completedResult
                    dataManager.recordVideoCompressionSession(
                        videoCount: completedResult.successCount,
                        failedCount: failedCount,
                        originalSizeMB: completedResult.originalSizeMB,
                        compressedSizeMB: completedResult.compressedSizeMB,
                        date: completedResult.completedAt,
                        items: completedResult.historyItems
                    )
                    selectedAssetIDs.removeAll()
                    reloadAssets()
                    showingCompressionCompletion = true
                    HapticManager.notify(.success)
                } else if !wasCancelled {
                    compressionErrorMessage = firstErrorMessage ?? L10n.string("视频压缩失败，请稍后再试。")
                    HapticManager.notify(.warning)
                }

                if failedCount > 0 && !resultItems.isEmpty {
                    compressionErrorMessage = String(format: L10n.string("有 %lld 个视频未完成"), Int64(failedCount))
                }
            }
        }
    }

    private func previewCompressedVideo() {
        guard let createdID = compressionResult?.createdAssetIdentifiers.first else {
            compressionErrorMessage = L10n.string("暂时找不到压缩副本。")
            return
        }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: [createdID], options: nil)
        guard let asset = result.firstObject else {
            compressionErrorMessage = L10n.string("暂时找不到压缩副本。")
            return
        }

        previewAsset = AdvancedPreviewAsset(asset: asset)
    }

    private func queueOriginalVideosForDeletion() {
        guard let compressionResult else { return }
        guard compressionResult.hasMeaningfulSavings else {
            compressionErrorMessage = L10n.string("这次没有明显减少空间，建议先保留原视频。")
            return
        }

        let originalIDs = Set(compressionResult.items.map(\.originalAssetIdentifier))
        let originalAssets = dataManager.photoLibraryManager.videos.filter { originalIDs.contains($0.localIdentifier) }
        guard !originalAssets.isEmpty else {
            compressionErrorMessage = L10n.string("暂时找不到原视频。")
            return
        }

        for asset in originalAssets {
            _ = dataManager.markReviewed(asset)
            dataManager.addToDeleteCandidates(asset)
        }
        HapticManager.notify(.warning)
        showBatchConfirm = true
    }

    private func compressionCompletionMessage(for result: AdvancedVideoCompressionResult) -> String {
        if result.hasMeaningfulSavings {
            return String(format: L10n.string("原视频 %@，压缩后 %@，约减少 %@。原视频尚未删除。"), result.formattedOriginalSize, result.formattedCompressedSize, result.formattedSavedSize)
        }
        return String(format: L10n.string("原视频 %@，压缩后 %@。本次没有明显减少空间，建议保留原视频。"), result.formattedOriginalSize, result.formattedCompressedSize)
    }
}

private struct AdvancedVideoCompressionResultItem: Identifiable, Equatable {
    let originalAssetIdentifier: String
    let createdAssetIdentifier: String?
    let originalSizeMB: Double
    let compressedSizeMB: Double
    let originalDimensions: CGSize
    let outputDimensions: CGSize

    var id: String { originalAssetIdentifier }

    init(result: VideoCompressionResult) {
        self.originalAssetIdentifier = result.originalAssetIdentifier
        self.createdAssetIdentifier = result.createdAssetIdentifier
        self.originalSizeMB = result.originalSizeMB
        self.compressedSizeMB = result.compressedSizeMB
        self.originalDimensions = result.originalDimensions
        self.outputDimensions = result.outputDimensions
    }

    var savedSizeMB: Double {
        max(originalSizeMB - compressedSizeMB, 0)
    }

    var hasMeaningfulSavings: Bool {
        savedSizeMB >= max(1, originalSizeMB * 0.02)
    }
}

private struct AdvancedVideoCompressionResult: Equatable {
    let items: [AdvancedVideoCompressionResultItem]
    let failedCount: Int
    let completedAt: Date
    let plan: VideoCompressionPlan

    var successCount: Int {
        items.count
    }

    var originalSizeMB: Double {
        items.reduce(0) { $0 + $1.originalSizeMB }
    }

    var compressedSizeMB: Double {
        items.reduce(0) { $0 + $1.compressedSizeMB }
    }

    var savedSizeMB: Double {
        max(originalSizeMB - compressedSizeMB, 0)
    }

    var hasMeaningfulSavings: Bool {
        savedSizeMB >= max(1, originalSizeMB * 0.02)
    }

    var formattedOriginalSize: String {
        CleanupStatsFormatter.space(originalSizeMB)
    }

    var formattedCompressedSize: String {
        CleanupStatsFormatter.space(compressedSizeMB)
    }

    var formattedSavedSize: String {
        CleanupStatsFormatter.space(savedSizeMB)
    }

    var savedRatioPercent: Int {
        guard originalSizeMB > 0 else { return 0 }
        return max(Int((savedSizeMB / originalSizeMB * 100).rounded()), 0)
    }

    var createdAssetIdentifiers: [String] {
        items.compactMap(\.createdAssetIdentifier)
    }

    var historyItems: [VideoCompressionSessionItem] {
        items.map { item in
            VideoCompressionSessionItem(
                originalAssetIdentifier: item.originalAssetIdentifier,
                createdAssetIdentifier: item.createdAssetIdentifier,
                originalSizeMB: item.originalSizeMB,
                compressedSizeMB: item.compressedSizeMB
            )
        }
    }

    var keptResolutionText: String {
        guard let firstItem = items.first else { return L10n.string("保持原分辨率") }
        let original = dimensionsText(firstItem.originalDimensions)
        let output = dimensionsText(firstItem.outputDimensions)
        if original == output {
            return String(format: L10n.string("分辨率保持 %@"), original)
        }
        return String(format: L10n.string("分辨率 %@ → %@"), original, output)
    }

    private func dimensionsText(_ size: CGSize) -> String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return L10n.string("未知") }
        return "\(width)×\(height)"
    }
}

private struct AdvancedVideoCompressionListHeader: View {
    let count: Int
    let totalSizeMB: Double
    let selectedCount: Int
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("视频列表"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(String(format: L10n.string("%lld 个视频 · 合计约 %@"), Int64(count), CleanupStatsFormatter.space(totalSizeMB)))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: action) {
                Text(selectedCount == 0 ? L10n.string("选择") : L10n.string("取消"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(
                        Capsule()
                            .fill(PhotoDeleteStyle.accent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
        .padding(.top, 2)
    }
}

private struct AdvancedVideoCompressionOptionsContext: Identifiable {
    let id = UUID()
    let assets: [PHAsset]

    var count: Int { assets.count }
}

private struct AdvancedVideoCompressionPlanCard: View {
    let plan: VideoCompressionPlan
    let estimate: VideoCompressionEstimate
    let selectedCount: Int
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("当前压缩方案"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Spacer()

                Button(action: action) {
                    Label(L10n.string("调整"), systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(PhotoDeleteStyle.accent)
                .disabled(isDisabled || selectedCount == 0)
            }

            HStack(spacing: 10) {
                AdvancedVideoCompressionMetric(label: L10n.string("质量"), value: plan.quality.title)
                AdvancedVideoCompressionMetric(label: L10n.string("分辨率"), value: plan.resolution.title)
                AdvancedVideoCompressionMetric(label: L10n.string("预计压缩后"), value: selectedCount == 0 ? L10n.string("先选择视频") : estimate.formattedCompressedRange)
            }

            Label(L10n.string("压缩副本会保存到照片库，原视频不会自动删除。"), systemImage: "info.circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct AdvancedVideoCompressionOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager

    let context: AdvancedVideoCompressionOptionsContext
    let knownOriginalSizeMBByAssetID: [String: Double]
    let onStart: (VideoCompressionPlan, [PHAsset]) -> Void
    @State private var plan: VideoCompressionPlan

    init(
        context: AdvancedVideoCompressionOptionsContext,
        initialPlan: VideoCompressionPlan,
        knownOriginalSizeMBByAssetID: [String: Double],
        onStart: @escaping (VideoCompressionPlan, [PHAsset]) -> Void
    ) {
        self.context = context
        self.knownOriginalSizeMBByAssetID = knownOriginalSizeMBByAssetID
        self.onStart = onStart
        _plan = State(initialValue: initialPlan)
    }

    private var estimate: VideoCompressionEstimate {
        dataManager.estimatedVideoCompressionEstimate(
            for: context.assets,
            plan: plan,
            knownOriginalSizeMBByAssetID: knownOriginalSizeMBByAssetID
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AdvancedVideoCompressionEstimateCard(
                        count: context.count,
                        estimate: estimate
                    )

                    AdvancedVideoCompressionOptionSection(
                        title: L10n.string("压缩质量"),
                        subtitle: L10n.string("质量越高，文件越大；节省空间会牺牲更多细节。")
                    ) {
                        VStack(spacing: 8) {
                            ForEach(VideoCompressionQuality.allCases) { quality in
                                AdvancedVideoCompressionOptionRow(
                                    title: quality.title,
                                    subtitle: quality.subtitle,
                                    isSelected: plan.quality == quality
                                ) {
                                    plan.quality = quality
                                }
                            }
                        }
                    }

                    AdvancedVideoCompressionOptionSection(
                        title: L10n.string("分辨率"),
                        subtitle: L10n.string("降低分辨率会显著减少体积，但细节会少一些。")
                    ) {
                        VStack(spacing: 8) {
                            ForEach(VideoCompressionResolution.allCases) { resolution in
                                AdvancedVideoCompressionOptionRow(
                                    title: resolution.title,
                                    subtitle: resolution.subtitle,
                                    isSelected: plan.resolution == resolution
                                ) {
                                    plan.resolution = resolution
                                }
                            }
                        }
                    }

                    Label(L10n.string("预计大小会因原视频编码、运动复杂度和 HDR 状态产生偏差，最终以压缩完成报告为准。"), systemImage: "info.circle")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(PhotoDeleteStyle.background.ignoresSafeArea())
            .navigationTitle(L10n.string("压缩方案"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("取消")) {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    let selectedPlan = plan
                    let selectedAssets = context.assets
                    dismiss()
                    onStart(selectedPlan, selectedAssets)
                } label: {
                    VStack(spacing: 3) {
                        Text(String(format: L10n.string("开始压缩 %lld 个视频"), Int64(context.count)))
                            .font(.system(size: 15, weight: .semibold))
                        Text(String(format: L10n.string("预计压缩后 %@"), estimate.formattedCompressedRange))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(PhotoDeleteStyle.primaryButtonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(PhotoDeleteStyle.accent)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.bottom, 14)
                .padding(.top, 8)
                .background(PhotoDeleteStyle.background.opacity(0.94))
            }
        }
    }
}

private struct AdvancedVideoCompressionEstimateCard: View {
    let count: Int
    let estimate: VideoCompressionEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.positive)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: L10n.string("准备压缩 %lld 个视频"), Int64(count)))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(String(format: L10n.string("原文件合计 %@"), estimate.formattedOriginalSize))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                AdvancedVideoCompressionMetric(label: L10n.string("预计压缩后"), value: estimate.formattedCompressedRange)
                AdvancedVideoCompressionMetric(label: L10n.string("预计节省"), value: estimate.formattedSavedRange)
            }
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct AdvancedVideoCompressionOptionSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
    }
}

private struct AdvancedVideoCompressionOptionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? PhotoDeleteStyle.positive : PhotoDeleteStyle.secondaryText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? PhotoDeleteStyle.positive.opacity(0.12) : PhotoDeleteStyle.elevatedSurface)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AdvancedVideoCompressionProgressCard: View {
    let processedCount: Int
    let totalCount: Int
    let currentProgress: Double
    let message: String?

    private var combinedProgress: Double {
        guard totalCount > 0 else { return 0 }
        return min((Double(processedCount) + min(max(currentProgress, 0), 1)) / Double(totalCount), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: combinedProgress)
                .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.positive))
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: L10n.string("正在压缩 %lld/%lld"), Int64(processedCount), Int64(totalCount)))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(message ?? L10n.string("保持屏幕打开，压缩完成后会保存到照片库。"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct AdvancedVideoCompressionResultCard: View {
    let result: AdvancedVideoCompressionResult
    let onPreview: () -> Void
    let onDeleteOriginals: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: result.hasMeaningfulSavings ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(result.hasMeaningfulSavings ? PhotoDeleteStyle.positive : PhotoDeleteStyle.warning)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: L10n.string("已生成 %lld 个压缩副本"), Int64(result.successCount)))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(result.hasMeaningfulSavings ? String(format: L10n.string("本次约减少 %@（%lld%%）"), result.formattedSavedSize, Int64(result.savedRatioPercent)) : L10n.string("这次没有明显减少空间，建议保留原视频。"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                AdvancedVideoCompressionMetric(label: L10n.string("方案"), value: result.plan.title)
                AdvancedVideoCompressionMetric(label: L10n.string("原视频"), value: result.formattedOriginalSize)
                AdvancedVideoCompressionMetric(label: L10n.string("压缩后"), value: result.formattedCompressedSize)
            }

            HStack(spacing: 10) {
                AdvancedVideoCompressionMetric(label: L10n.string("分辨率"), value: result.keptResolutionText)
            }

            Text(L10n.string("压缩副本已保存到照片库。请先预览副本，确认效果后再删除原视频。"))
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if result.failedCount > 0 {
                Label(String(format: L10n.string("%lld 个视频未完成"), Int64(result.failedCount)), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.warning)
            }

            HStack(spacing: 10) {
                Button(action: onPreview) {
                    Label(L10n.string("预览压缩副本"), systemImage: "play.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .photoDeleteSecondaryButton()
                .disabled(result.createdAssetIdentifiers.isEmpty)

                Button(role: .destructive, action: onDeleteOriginals) {
                    Label(L10n.string("删除原视频"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .photoDeleteSecondaryButton()
                .disabled(!result.hasMeaningfulSavings)
            }
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct AdvancedVideoCompressionMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.secondaryText)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
        )
    }
}

private struct AdvancedVideoCompressionHistoryCard: View {
    let sessions: [VideoCompressionSession]
    let photoLibraryManager: PhotoLibraryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("最近压缩记录"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    HStack(spacing: 12) {
                        Image(systemName: "video.badge.checkmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.positive)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.formattedDate)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)

                            Text(String(format: L10n.string("%lld 个视频 · %@ → %@"), Int64(session.videoCount), session.formattedOriginalSize, session.formattedCompressedSize))
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }

                        Spacer()

                        Text(session.formattedSavedSize)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(session.savedSizeMB > 0 ? PhotoDeleteStyle.positive : PhotoDeleteStyle.warning)
                    }
                    .padding(.vertical, 10)

                    if !session.items.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(Array(session.items.prefix(3))) { item in
                                AdvancedVideoCompressionHistoryItemRow(
                                    item: item,
                                    photoLibraryManager: photoLibraryManager
                                )
                            }

                            if session.items.count > 3 {
                                Text(String(format: L10n.string("还有 %lld 条压缩明细"), Int64(session.items.count - 3)))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.leading, 36)
                        .padding(.bottom, 8)
                    }

                    if session.id != sessions.last?.id {
                        Divider()
                            .background(PhotoDeleteStyle.hairline)
                            .padding(.leading, 36)
                    }
                }
            }
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct AdvancedVideoCompressionHistoryItemRow: View {
    let item: VideoCompressionSessionItem
    let photoLibraryManager: PhotoLibraryManager

    private var originalAsset: PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [item.originalAssetIdentifier], options: nil).firstObject
    }

    private var compressedAsset: PHAsset? {
        guard let createdAssetIdentifier = item.createdAssetIdentifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [createdAssetIdentifier], options: nil).firstObject
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 6) {
                thumbnail(for: originalAsset)
                thumbnail(for: compressedAsset)
            }

            VStack(alignment: .leading, spacing: 6) {
                historyLine(
                    label: L10n.string("原视频"),
                    title: title(for: originalAsset, fallback: L10n.string("原视频可能已删除")),
                    size: item.formattedOriginalSize
                )

                historyLine(
                    label: L10n.string("压缩副本"),
                    title: title(for: compressedAsset, fallback: L10n.string("压缩副本可能已删除")),
                    size: item.formattedCompressedSize
                )
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
        )
    }

    @ViewBuilder
    private func thumbnail(for asset: PHAsset?) -> some View {
        if let asset {
            AdvancedAssetThumbnail(
                asset: asset,
                photoLibraryManager: photoLibraryManager,
                size: 34
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "questionmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                )
        }
    }

    private func historyLine(label: String, title: String, size: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)

                Text(size)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.positive)
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .lineLimit(1)
        }
    }

    private func title(for asset: PHAsset?, fallback: String) -> String {
        guard let asset else { return fallback }
        return AdvancedAssetFormatter.title(for: asset, photoLibraryManager: photoLibraryManager)
    }
}

private struct AdvancedVideoCompressionMessageCard: View {
    let icon: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(tint)

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct AdvancedVideoCompressionActionBar: View {
    let count: Int
    let estimate: VideoCompressionEstimate
    let processedCount: Int
    let isCompressing: Bool
    let onCompress: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !isCompressing {
                Text(String(format: L10n.string("已选择 %lld 个视频 · 预计压缩后 %@"), Int64(count), estimate.formattedCompressedRange))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button(role: .destructive, action: onDelete) {
                    Label(L10n.string("删除选中"), systemImage: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.warning)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(PhotoDeleteStyle.warning.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .disabled(isCompressing)

                Button(action: onCompress) {
                    HStack(spacing: 8) {
                        if isCompressing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.primaryButtonText))
                                .scaleEffect(0.78)
                        } else {
                            Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                        }

                        Text(buttonTitle)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryButtonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(PhotoDeleteStyle.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCompressing)
            }
        }
        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
        .padding(.bottom, 24)
        .padding(.top, 10)
        .background(
            PhotoDeleteStyle.background.opacity(0.94)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var buttonTitle: String {
        if isCompressing {
            return String(format: L10n.string("正在压缩 %lld/%lld"), Int64(processedCount), Int64(count))
        }
        return L10n.string("压缩选中")
    }
}

private struct AdvancedSimilarPhotoGroupsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var groups: [AdvancedSimilarPhotoGroup] = []
    @State private var selectedAssetIDs: Set<String> = []
    @State private var showBatchConfirm = false
    @State private var previewAsset: AdvancedPreviewAsset?

    private var selectedAssets: [PHAsset] {
        groups.flatMap(\.assets).filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(spacing: 14) {
                    AdvancedFilterPills(kind: .similarPhotos)

                    AdvancedAssetListSummaryCard(
                        title: L10n.string("发现 \(groups.count) 组相似照片"),
                        subtitle: L10n.string("预计可减少 \(groups.reduce(0) { $0 + $1.suggestedDeleteCount }) 张，逐组确认更稳妥。"),
                        buttonTitle: selectedAssetIDs.isEmpty ? L10n.string("建议选择") : L10n.string("取消"),
                        action: toggleRecommendedSelection
                    )

                    if groups.isEmpty {
                        AdvancedEmptyState(
                            icon: AdvancedCleanupKind.similarPhotos.icon,
                            title: L10n.string("暂未发现相似照片"),
                            subtitle: L10n.string("相似照片会按拍摄时间和画面比例聚组。")
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(groups) { group in
                                AdvancedSimilarPhotoGroupCard(
                                    group: group,
                                    photoLibraryManager: dataManager.photoLibraryManager,
                                    selectedAssetIDs: selectedAssetIDs,
                                    onSelectRecommended: { selectRecommended(in: group) },
                                    onToggleAsset: toggleSelection,
                                    onPreview: { previewAsset = AdvancedPreviewAsset(asset: $0) }
                                )
                            }
                        }
                    }

                    Spacer()
                        .frame(height: 24)
                }
                .padding(24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selectedAssetIDs.isEmpty {
                AdvancedSelectionActionBar(
                    count: selectedAssetIDs.count,
                    action: addSelectedAssetsToDeleteCandidates
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .advancedDetailNavigation(title: L10n.string("相似照片"))
        .fullScreenCover(isPresented: $showBatchConfirm, onDismiss: {
            selectedAssetIDs.removeAll()
            reloadGroups()
        }) {
            BatchConfirmView()
                .environmentObject(dataManager)
        }
        .sheet(item: $previewAsset) { item in
            AdvancedAssetPreviewView(
                asset: item.asset,
                photoLibraryManager: dataManager.photoLibraryManager
            )
        }
        .task {
            reloadGroups()
        }
    }

    private func toggleRecommendedSelection() {
        HapticManager.impact(.light)
        if selectedAssetIDs.isEmpty {
            selectedAssetIDs = Set(groups.flatMap { $0.assets.dropFirst().map(\.localIdentifier) })
        } else {
            selectedAssetIDs.removeAll()
        }
    }

    private func selectRecommended(in group: AdvancedSimilarPhotoGroup) {
        HapticManager.impact(.light)
        for asset in group.assets.dropFirst() {
            selectedAssetIDs.insert(asset.localIdentifier)
        }
    }

    private func toggleSelection(_ asset: PHAsset) {
        HapticManager.impact(.light)
        let id = asset.localIdentifier
        if selectedAssetIDs.contains(id) {
            selectedAssetIDs.remove(id)
        } else {
            selectedAssetIDs.insert(id)
        }
    }

    private func addSelectedAssetsToDeleteCandidates() {
        let assets = selectedAssets
        guard !assets.isEmpty else { return }
        for asset in assets {
            _ = dataManager.markReviewed(asset)
            dataManager.addToDeleteCandidates(asset)
        }
        HapticManager.notify(.success)
        showBatchConfirm = true
    }

    private func reloadGroups() {
        groups = dataManager.makeSimilarPhotoGroups(maxGroups: 80)
        selectedAssetIDs = selectedAssetIDs.filter { selectedID in
            groups.contains { group in
                group.assets.contains { $0.localIdentifier == selectedID }
            }
        }
    }
}

private struct AdvancedSimilarPhotoGroupCard: View {
    let group: AdvancedSimilarPhotoGroup
    let photoLibraryManager: PhotoLibraryManager
    let selectedAssetIDs: Set<String>
    let onSelectRecommended: () -> Void
    let onToggleAsset: (PHAsset) -> Void
    let onPreview: (PHAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(String(format: L10n.string("%lld 张相近候选 · 可节省 %@"), Int64(group.assets.count), group.formattedEstimatedSpace))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }

                Spacer()

                Button(action: onSelectRecommended) {
                    Text(L10n.string("保留首张，选择其余"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.positive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(PhotoDeleteStyle.positive.opacity(0.14))
                        )
                        .photoDeleteMinimumTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(L10n.string("选择除首张外的相似照片，稍后统一确认删除。")))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(group.assets, id: \.localIdentifier) { asset in
                        AdvancedSelectableThumbnail(
                            asset: asset,
                            photoLibraryManager: photoLibraryManager,
                            isSelected: selectedAssetIDs.contains(asset.localIdentifier),
                            showsRecommendedBadge: asset.localIdentifier == group.assets.first?.localIdentifier,
                            onToggleSelection: { onToggleAsset(asset) },
                            onPreview: { onPreview(asset) }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct AdvancedAssetListSummaryCard: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryButtonText)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(PhotoDeleteStyle.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct AdvancedAssetRow: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let estimatedSizeMB: Double
    var sizeText: String?
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onPreview: () -> Void

    private var title: String {
        AdvancedAssetFormatter.title(for: asset, photoLibraryManager: photoLibraryManager)
    }

    private var metadata: String {
        AdvancedAssetFormatter.metadata(for: asset, photoLibraryManager: photoLibraryManager)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPreview) {
                AdvancedAssetThumbnail(
                    asset: asset,
                    photoLibraryManager: photoLibraryManager,
                    size: 62
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(asset.mediaType == .video ? L10n.string("视频预览") : L10n.string("照片预览"))

            Button(action: onToggleSelection) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.primaryText)
                            .lineLimit(1)

                        Text(metadata)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 8) {
                        Text(sizeText ?? CleanupStatsFormatter.space(estimatedSizeMB))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.positive)
                            .lineLimit(1)

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(isSelected ? PhotoDeleteStyle.accent : PhotoDeleteStyle.tertiaryText)
                            .photoDeleteMinimumTapTarget()
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? L10n.string("取消选择") : L10n.string("选择"))
            .accessibilityValue(Text("\(isSelected ? L10n.string("已选") : L10n.string("未选择")), \(title), \(metadata)"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .padding(10)
        .photoDeleteCard()
    }
}

private struct AdvancedSelectableThumbnail: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let isSelected: Bool
    let showsRecommendedBadge: Bool
    let onToggleSelection: () -> Void
    let onPreview: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onPreview) {
                AdvancedAssetThumbnail(
                    asset: asset,
                    photoLibraryManager: photoLibraryManager,
                    size: 66
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(asset.mediaType == .video ? L10n.string("视频预览") : L10n.string("照片预览"))

            Button(action: onToggleSelection) {
                Label(isSelected ? L10n.string("取消选择") : L10n.string("选择"), systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? PhotoDeleteStyle.accent : Color.white.opacity(0.84))
                    .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 2)
                    .frame(width: 32, height: 32)
                    .photoDeleteMinimumTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(isSelected ? L10n.string("已选") : L10n.string("未选择")))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if showsRecommendedBadge {
                Text(L10n.string("保留"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PhotoDeleteStyle.primaryButtonText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(PhotoDeleteStyle.positive))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(5)
            }
        }
        .frame(width: 66, height: 66)
    }
}

private struct AdvancedAssetThumbnail: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let size: CGFloat

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var loadingAssetID: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(PhotoDeleteStyle.elevatedSurface)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                        )
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            if asset.mediaType == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(PhotoDeleteStyle.background.opacity(0.72)))
                    .padding(5)
            }
        }
        .frame(width: size, height: size)
        .onAppear(perform: loadImage)
        .onDisappear {
            photoLibraryManager.cancelImageRequest(requestID)
            loadingAssetID = nil
        }
    }

    private func loadImage() {
        photoLibraryManager.cancelImageRequest(requestID)
        let requestedID = asset.localIdentifier
        loadingAssetID = requestedID
        image = nil
        requestID = photoLibraryManager.loadFastThumbnail(
            for: asset,
            size: CGSize(width: size * 3, height: size * 3)
        ) { loadedImage in
            guard loadingAssetID == requestedID else { return }
            image = loadedImage
            requestID = nil
        }
    }
}

private struct AdvancedAssetPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var requestID: PHImageRequestID?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    PhotoDeleteStyle.background.ignoresSafeArea()

                    if asset.mediaType == .video {
                        PhotoAssetVideoPlayerView(
                            asset: asset,
                            photoLibraryManager: photoLibraryManager
                        )
                    } else if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 36, weight: .medium))
                                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                            }

                            Text(isLoading ? L10n.string("正在读取照片") : L10n.string("无法读取这张照片"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                        }
                    }
                }
                .onAppear {
                    if asset.mediaType != .video {
                        loadImage(in: geometry.size)
                    }
                }
            }
            .navigationTitle(asset.mediaType == .video ? L10n.string("视频预览") : L10n.string("照片预览"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("关闭")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.accent)
                }
            }
        }
        .onDisappear {
            photoLibraryManager.cancelImageRequest(requestID)
        }
    }

    private func loadImage(in size: CGSize) {
        guard requestID == nil, image == nil else { return }
        let targetSize = CGSize(
            width: max(size.width * displayScale, 900),
            height: max(size.height * displayScale, 1_200)
        )

        requestID = photoLibraryManager.loadHighQualityPreview(for: asset, size: targetSize) { loadedImage in
            image = loadedImage
            isLoading = false
            requestID = nil
        }
    }
}

private struct AdvancedSelectionActionBar: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text(L10n.string("加入待删除 \(count) 项"))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(PhotoDeleteStyle.primaryButtonText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PhotoDeleteStyle.accent)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
        .padding(.bottom, 24)
        .background(
            PhotoDeleteStyle.background.opacity(0.92)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct AdvancedFilterPills: View {
    let kind: AdvancedCleanupKind

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    Text(filter)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PhotoDeleteStyle.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(PhotoDeleteStyle.surface)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                                )
                        )
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .combine)
    }

    private var filters: [String] {
        switch kind {
        case .similarPhotos:
            return [L10n.string("推荐"), L10n.string("连拍"), L10n.string("截图"), L10n.string("本月")]
        case .largeFiles:
            return [L10n.string("全部"), L10n.string("视频"), L10n.string("图片"), L10n.string("本月")]
        case .videoCompression:
            return [L10n.string("全部"), L10n.string("大文件"), L10n.string("较长"), L10n.string("可压缩")]
        case .screenshots:
            return [L10n.string("全部"), L10n.string("本月"), L10n.string("较旧"), L10n.string("已选")]
        case .videos:
            return [L10n.string("全部"), L10n.string("大文件"), L10n.string("较长"), L10n.string("本月")]
        }
    }
}

private extension View {
    func advancedDetailNavigation(title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

private struct AdvancedProgressRing<Content: View>: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(PhotoDeleteStyle.elevatedSurface, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    PhotoDeleteStyle.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            content
        }
        .frame(width: size, height: size)
    }
}

private struct AdvancedDemoTag: View {
    var body: some View {
        Text(L10n.string("示例"))
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(PhotoDeleteStyle.warning)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(PhotoDeleteStyle.warning.opacity(0.14))
            )
    }
}

private struct AdvancedEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                ContentUnavailableView(
                    title,
                    systemImage: icon,
                    description: Text(subtitle)
                )
                .foregroundStyle(PhotoDeleteStyle.secondaryText)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 38, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)

                    VStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.primaryText)

                        Text(subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .photoDeleteCard()
    }
}

private enum AdvancedAssetListMode {
    case cleanup(AdvancedCleanupKind)

    var id: String {
        switch self {
        case .cleanup(let kind):
            return "cleanup-\(kind.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .cleanup(let kind):
            return kind.title
        }
    }

    var icon: String {
        switch self {
        case .cleanup(let kind):
            return kind.icon
        }
    }
}

private struct AdvancedPreviewAsset: Identifiable {
    let asset: PHAsset

    var id: String {
        asset.localIdentifier
    }
}

private enum AdvancedAssetFormatter {
    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yyyyMd")
        return formatter
    }()

    static func title(for asset: PHAsset, photoLibraryManager: PhotoLibraryManager) -> String {
        if asset.mediaType == .video {
            return L10n.string("视频")
        }
        if photoLibraryManager.isScreenshot(asset) {
            return L10n.string("截图")
        }
        return L10n.string("照片")
    }

    static func metadata(for asset: PHAsset, photoLibraryManager: PhotoLibraryManager) -> String {
        var parts: [String] = []

        if asset.mediaType == .video {
            parts.append(L10n.string("视频 \(formattedDuration(asset.duration))"))
        } else if photoLibraryManager.isScreenshot(asset) {
            parts.append(L10n.string("截图"))
        } else {
            parts.append(L10n.string("图片"))
        }

        if asset.pixelWidth > 0 && asset.pixelHeight > 0 {
            parts.append("\(asset.pixelWidth)×\(asset.pixelHeight)")
        }

        if let creationDate = asset.creationDate {
            parts.append(date.string(from: creationDate))
        }

        return parts.joined(separator: " · ")
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private enum AdvancedPeriodFormatter {
    static func title(for summary: PhotoPeriodSummary) -> String {
        switch summary.scope {
        case .day:
            return dayTitle.string(from: summary.intervalStart)
        case .week:
            return weekTitle(for: summary.intervalStart)
        case .month:
            return fullMonth.string(from: summary.intervalStart)
        case .year:
            return yearTitle.string(from: summary.intervalStart)
        }
    }

    static func compactTitle(for summary: PhotoPeriodSummary) -> String {
        switch summary.scope {
        case .day:
            return dayCompact.string(from: summary.intervalStart)
        case .week:
            return weekCompact(for: summary.intervalStart)
        case .month:
            return monthTitle.string(from: summary.intervalStart)
        case .year:
            return yearTitle.string(from: summary.intervalStart)
        }
    }

    static func chipTitle(for summary: PhotoPeriodSummary) -> String {
        switch summary.scope {
        case .day:
            return dayChip.string(from: summary.intervalStart)
        case .week:
            return weekChip(for: summary.intervalStart)
        case .month:
            return shortMonth.string(from: summary.intervalStart)
        case .year:
            return yearTitle.string(from: summary.intervalStart)
        }
    }

    static func subtitle(for summary: PhotoPeriodSummary) -> String {
        switch summary.scope {
        case .day:
            return L10n.string("当天")
        case .week:
            let start = dayRange.string(from: summary.intervalStart)
            let endDate = Calendar.current.date(byAdding: .day, value: -1, to: summary.intervalEnd) ?? summary.intervalEnd
            let end = dayRange.string(from: endDate)
            return "\(start) - \(end)"
        case .month:
            return L10n.string("本月照片清理进度")
        case .year:
            return L10n.string("全年照片清理进度")
        }
    }

    private static func weekTitle(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return L10n.string("\(components.yearForWeekOfYear ?? 0) 年第 \(components.weekOfYear ?? 0) 周")
    }

    private static func weekCompact(for date: Date) -> String {
        let week = Calendar.current.component(.weekOfYear, from: date)
        return L10n.string("第 \(week) 周")
    }

    private static func weekChip(for date: Date) -> String {
        let week = Calendar.current.component(.weekOfYear, from: date)
        return L10n.string("周 \(week)")
    }

    private static let dayTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("y年M月d日")
        return formatter
    }()

    private static let dayCompact: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M月d日")
        return formatter
    }()

    private static let dayChip: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M/d")
        return formatter
    }()

    private static let dayRange: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M/d")
        return formatter
    }()

    private static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M月")
        return formatter
    }()

    private static let shortMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M月")
        return formatter
    }()

    private static let fullMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("y年M月")
        return formatter
    }()

    private static let yearTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("y年")
        return formatter
    }()
}

#Preview {
    AdvancedView()
        .environmentObject(DataManager())
        .environmentObject(PurchaseManager())
}
