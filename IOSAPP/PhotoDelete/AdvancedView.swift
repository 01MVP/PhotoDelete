//
//  AdvancedView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/11/26.
//

import SwiftUI
import Photos
import Combine
import UIKit

struct AdvancedView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedScope: AdvancedTimeScope = .month
    @State private var selectedPeriodDate = Date()
    @State private var dashboardSnapshot = AdvancedLibrarySnapshot.demo(referenceDate: Date())
    @State private var activePeriodRoute: AdvancedPeriodRoute?
    @State private var advancedRefreshWorkItem: DispatchWorkItem?
    @State private var lastDashboardRefreshKey: AdvancedDashboardRefreshKey?
    @State private var showingSupporterBenefits = false
    @State private var visibleAdvancedPeriodLimit = 5

    private var isLocked: Bool {
        !purchaseManager.isSupporter
    }

    private var isAwaitingPhotoLibraryAccess: Bool {
        !isLocked && !dataManager.photoLibraryManager.hasPhotoLibraryAccess
    }

    private var entitlementStatusMessage: String? {
        if let trialStatusText = purchaseManager.supporterTrialStatusText {
            return trialStatusText
        }

        switch purchaseManager.entitlementState {
        case .unknown, .verifying, .verified, .cachedOffline, .locked:
            return nil
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
            visibleAdvancedPeriodLimit = 5
            refreshAdvancedDashboard(resetSelectedPeriod: false, force: true)
        }
        .onChange(of: purchaseManager.entitlementState) { _ in
            refreshAdvancedDashboard(resetSelectedPeriod: true, force: true)
        }
        .onChange(of: purchaseManager.supporterTrialStartDate) { _ in
            refreshAdvancedDashboard(resetSelectedPeriod: true, force: true)
        }
        .onChange(of: dataManager.cleanupStatsRevision) { _ in
            scheduleAdvancedDashboardRefresh()
        }
        .onChange(of: dataManager.advancedCleanupQueuesRevision) { _ in
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
            await purchaseManager.refreshEntitlementsSilently()
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

                VStack(spacing: 16) {
                    if purchaseManager.isUsingTrialSupporterAccess {
                        AdvancedTrialStatusBanner(
                            remainingDays: purchaseManager.supporterTrialDaysRemaining,
                            isLoading: purchaseManager.isLoading,
                            onPurchase: purchaseSupporter
                        )
                    }

                    if isAwaitingPhotoLibraryAccess {
                        PhotoAuthorizationCard(
                            subtitle: L10n.string("进阶功能需要读取本机照片库，才能生成真实月份进度和清理队列。"),
                            onRequestAccess: { dataManager.requestPhotoLibraryAccess() }
                        )
                    } else if shouldShowAdvancedPreparingCard {
                        AdvancedLibraryPreparingCard(progress: advancedLoadingProgress)
                    } else {
                        cleanupEntrySection(
                            queues: snapshot.cleanupQueues,
                            isLocked: isLocked
                        )
                        .redacted(reason: shouldRedactAdvancedContent ? .placeholder : [])
                        .allowsHitTesting(!shouldRedactAdvancedContent)

                        advancedPeriodListSection(
                            summaries: periodSummaries,
                            isLocked: isLocked
                        )
                        .redacted(reason: shouldRedactAdvancedContent ? .placeholder : [])
                        .allowsHitTesting(!shouldRedactAdvancedContent)
                    }

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
                    canStartTrial: purchaseManager.canStartSupporterTrial,
                    isLoading: purchaseManager.isLoading,
                    errorMessage: purchaseManager.errorMessage,
                    statusMessage: entitlementStatusMessage,
                    onStartTrial: startSupporterTrial,
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
        if isLocked {
            return demoPeriodSummaries(for: selectedScope).filter { $0.assetCount > 0 }
        }

        if let summaries = dataManager.periodSummariesByScope[selectedScope] {
            return summaries.filter { $0.assetCount > 0 }
        }
        return []
    }

    private var displayedAdvancedPeriodSummaries: [PhotoPeriodSummary] {
        Array(visiblePeriodSummaries.prefix(visibleAdvancedPeriodLimit))
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
            cleanupStatsRevision: dataManager.cleanupStatsRevision,
            advancedCleanupQueuesRevision: dataManager.advancedCleanupQueuesRevision
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

    private func advancedPeriodListSection(
        summaries: [PhotoPeriodSummary],
        isLocked: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("按时间清理"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(L10n.string("按日、周、月、年继续整理。"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }

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
                }
            }

            AdvancedTimeScopePicker(selectedScope: $selectedScope)

            if summaries.isEmpty {
                if !isLocked && dataManager.isLoadingPeriodSummaries {
                    AdvancedEmptyState(
                        icon: "clock",
                        title: L10n.string("正在整理时间线"),
                        subtitle: L10n.string("读取完成后会显示可整理的日期、月份和年份。")
                    )
                } else {
                    AdvancedEmptyState(
                        icon: "calendar",
                        title: L10n.string("还没有可按时间整理的照片"),
                        subtitle: L10n.string("当前授权范围内没有带拍摄时间的照片。")
                    )
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedAdvancedPeriodSummaries.enumerated()), id: \.element.id) { index, summary in
                        Button {
                            openAdvancedPeriod(summary, isLocked: isLocked)
                        } label: {
                            AdvancedTimePeriodRow(summary: summary, isLocked: isLocked)
                        }
                        .buttonStyle(.plain)

                        if index != displayedAdvancedPeriodSummaries.count - 1 {
                            Divider()
                                .background(PhotoDeleteStyle.hairline)
                                .padding(.leading, 62)
                        }
                    }
                }
                .photoDeleteCard()
            }
        }
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

    private func cleanupEntrySection(
        queues: [AdvancedCleanupQueue],
        isLocked: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("高效清理"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(L10n.string("集中处理相似照片、大文件、图片和视频压缩。"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            if queues.isEmpty && dataManager.isLoadingAdvancedCleanupQueues {
                AdvancedEmptyState(
                    icon: "sparkles",
                    title: L10n.string("正在准备清理入口"),
                    subtitle: L10n.string("稍后会显示可处理的照片和视频。")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(queues.enumerated()), id: \.element.id) { index, queue in
                        if isLocked {
                            Button(action: openLockedAdvancedFeature) {
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
    }

    @ViewBuilder
    private func cleanupDestination(for kind: AdvancedCleanupKind) -> some View {
        switch kind {
        case .similarPhotos:
            AdvancedSimilarPhotoGroupsView()
                .environmentObject(dataManager)
        case .imageCompression:
            AdvancedImageCompressionView()
                .environmentObject(dataManager)
        case .videoCompression:
            AdvancedVideoCompressionView()
                .environmentObject(dataManager)
        case .largeFiles, .videos:
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

    private func openAdvancedPeriod(_ summary: PhotoPeriodSummary, isLocked: Bool) {
        guard !isLocked else {
            openLockedAdvancedFeature()
            return
        }

        selectedPeriodDate = summary.intervalStart
        activePeriodRoute = AdvancedPeriodRoute(
            scope: summary.scope,
            intervalStart: summary.intervalStart
        )
    }

    private func openLockedAdvancedFeature() {
        showingSupporterBenefits = true
    }

    private func purchaseSupporter() {
        Task { await purchaseManager.purchaseSupporter() }
    }

    private func startSupporterTrial() {
        purchaseManager.startSupporterTrial()
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
            return
        }

        dashboardSnapshot = AdvancedLibrarySnapshot(
            stats: dataManager.makeSettingsStatsSummary(),
            daySummaries: [],
            monthSummaries: [],
            cleanupQueues: dataManager.advancedCleanupQueues
        )
        dataManager.refreshAdvancedCleanupQueues()
        dataManager.refreshPhotoPeriodSummaries(for: [selectedScope])
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
    let advancedCleanupQueuesRevision: UUID
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

                    Text(String(
                        format: L10n.string("已整理 %lld/%lld 项，合计约 %@。"),
                        Int64(summary.reviewedCount),
                        Int64(summary.assetCount),
                        summary.formattedEstimatedSize
                    ))
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
                Text(queue.kind.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(detailText)
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

    private var detailText: String {
        switch queue.kind {
        case .similarPhotos, .largeFiles:
            return L10n.string("\(queue.assetCount) 项 · \(queue.formattedSpace)")
        case .imageCompression, .videoCompression, .videos:
            return L10n.string("\(queue.assetCount) 项")
        }
    }
}

private struct AdvancedTimePeriodRow: View {
    let summary: PhotoPeriodSummary
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            AdvancedPeriodProgressBadge(progress: summary.progress)

            VStack(alignment: .leading, spacing: 4) {
                Text(AdvancedPeriodFormatter.title(for: summary))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(detailText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 8)

            Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
        }
        .padding(14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        String(
            format: L10n.string("剩余 %lld 张 · 合计约 %@"),
            Int64(summary.remainingCount),
            summary.formattedEstimatedSize
        )
    }
}

private struct AdvancedPeriodProgressBadge: View {
    let progress: Double

    var body: some View {
        AdvancedProgressRing(progress: progress, size: 48, lineWidth: 5) {
            Text("\(Int(progress * 100))%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityHidden(true)
    }
}

private struct AdvancedBottomPaywall: View {
    let priceText: String
    let canStartTrial: Bool
    let isLoading: Bool
    let errorMessage: String?
    let statusMessage: String?
    let onStartTrial: () -> Void
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
                    Image(systemName: canStartTrial ? "timer" : "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(canStartTrial ? L10n.string("免费体验进阶功能") : L10n.string("解锁全部进阶功能"))
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            if canStartTrial {
                Button(action: onStartTrial) {
                    Label(L10n.string("开始 3 天免费体验"), systemImage: "timer")
                        .labelStyle(.titleAndIcon)
                }
                .photoDeletePrimaryButton()
                .disabled(isLoading)

                Button(action: onPurchase) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                                .scaleEffect(0.78)
                        }
                        Text(isLoading ? L10n.string("处理中...") : String(format: L10n.string("一次性解锁 %@"), priceText))
                    }
                }
                .photoDeleteSecondaryButton()
                .disabled(isLoading)
            } else {
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
            }

            Button(action: onRestore) {
                Text(L10n.string("恢复购买"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            Text(L10n.string("体验到期不会自动扣费，基础整理始终免费。"))
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

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

    private var subtitle: String {
        if canStartTrial {
            return L10n.string("免费体验 3 天进阶功能，也可以直接一次性解锁。")
        }

        return L10n.string("一次性解锁完整时间列表、大文件清理、图片压缩、视频压缩、相似照片清理和主题切换。")
    }
}

private struct AdvancedTrialStatusBanner: View {
    let remainingDays: Int
    let isLoading: Bool
    let onPurchase: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(PhotoDeleteStyle.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("支持者版试用中"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(String(format: L10n.string("还剩 %lld 天"), Int64(remainingDays)))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            Spacer(minLength: 8)

            Button(action: onPurchase) {
                Text(isLoading ? L10n.string("处理中...") : L10n.string("解锁"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryButtonText)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(
                        Capsule(style: .continuous)
                            .fill(PhotoDeleteStyle.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(14)
        .photoDeleteCard()
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

                    Text(L10n.string("正在读取本机照片、截图和视频，完成后会显示可用入口。"))
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
    @State private var visibleLimit = 60

    private let limitStep = 60

    private var visibleSummaries: [PhotoPeriodSummary] {
        VisibleListPagination.visibleItems(summaries, limit: visibleLimit)
    }

    private var hasMore: Bool {
        VisibleListPagination.hasMore(totalCount: summaries.count, limit: visibleLimit)
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                LazyVStack(spacing: 16) {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleSummaries.enumerated()), id: \.element.id) { index, summary in
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

                            if index != visibleSummaries.count - 1 {
                                Divider()
                                    .background(PhotoDeleteStyle.hairline)
                                    .padding(.leading, 70)
                            }
                        }
                    }
                    .photoDeleteCard()

                    if hasMore {
                        Button(action: showMore) {
                            Text(L10n.string("显示更多"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .photoDeleteMinimumTapTarget()
                    }

                    Spacer()
                        .frame(height: 72)
                }
                .padding(PhotoDeleteStyle.screenHorizontalPadding)
            }
        }
        .advancedDetailNavigation(title: L10n.string("时间进度"))
    }

    private func showMore() {
        withAnimation(.easeInOut(duration: 0.18)) {
            visibleLimit = VisibleListPagination.advancedLimit(
                totalCount: summaries.count,
                currentLimit: visibleLimit,
                step: limitStep
            )
        }
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
    @State private var videoSizeEstimatesByAssetID: [String: VideoFileSizeEstimate] = [:]
    @State private var selectedAssetIDs: Set<String> = []
    @State private var selectedFilter: AdvancedCleanupFilter = .all
    @State private var showingICloudVideoInfo = false
    @State private var showBatchConfirm = false
    @State private var previewAsset: AdvancedPreviewAsset?
    @State private var sizeLoadingTask: Task<Void, Never>?

    private var selectedAssets: [PHAsset] {
        filteredAssets.filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var filteredAssets: [PHAsset] {
        assets.filter { matches(asset: $0, filter: selectedFilter) }
    }

    private var filteredVideoAssets: [PHAsset] {
        filteredAssets.filter { $0.mediaType == .video }
    }

    private var filteredTotalSizeMB: Double {
        filteredAssets.reduce(0) { partial, asset in
            if asset.mediaType == .video {
                return partial + (reliableVideoSizeMB(for: asset) ?? 0)
            }
            return partial + dataManager.estimatedSizeMB(for: asset)
        }
    }

    private var isAllFilteredSelected: Bool {
        !filteredAssets.isEmpty &&
            filteredAssets.allSatisfy { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var loadedReliableVideoSizeCount: Int {
        filteredVideoAssets.reduce(0) { partial, asset in
            reliableVideoSizeMB(for: asset) == nil ? partial : partial + 1
        }
    }

    private var loadedVideoSizeCount: Int {
        filteredVideoAssets.reduce(0) { partial, asset in
            videoSizeEstimatesByAssetID[asset.localIdentifier] == nil ? partial : partial + 1
        }
    }

    private var iCloudVideoCount: Int {
        filteredVideoAssets.reduce(0) { partial, asset in
            videoSizeEstimatesByAssetID[asset.localIdentifier]?.source == .iCloud ? partial + 1 : partial
        }
    }

    private var hasUnresolvedVideoSizes: Bool {
        !filteredVideoAssets.isEmpty && loadedReliableVideoSizeCount < filteredVideoAssets.count
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(spacing: 14) {
                    if case .cleanup(let kind) = mode {
                        AdvancedFilterPills(kind: kind, selection: $selectedFilter)
                    }

                    AdvancedAssetListSummaryCard(
                        title: summaryTitle,
                        subtitle: summarySubtitle,
                        buttonTitle: isAllFilteredSelected ? L10n.string("取消") : L10n.string("全选"),
                        action: toggleBulkSelection
                    )

                    if iCloudVideoCount > 0 {
                        AdvancedVideoCompressionICloudInfoCard(
                            count: iCloudVideoCount,
                            subtitle: L10n.string("预览或处理时会下载原片。"),
                            action: showICloudVideoInfo
                        )
                    }

                    if assets.isEmpty {
                        AdvancedEmptyState(
                            icon: mode.icon,
                            title: L10n.string("没有可整理的内容"),
                            subtitle: L10n.string("当前照片库里暂时没有符合这个入口的项目。")
                        )
                    } else if filteredAssets.isEmpty {
                        AdvancedEmptyState(
                            icon: mode.icon,
                            title: L10n.string("当前筛选没有内容"),
                            subtitle: L10n.string("可以切换到全部，或稍后再回来查看。")
                        )
                    } else {
                        LazyVStack(spacing: 9) {
                            ForEach(filteredAssets, id: \.localIdentifier) { asset in
                                AdvancedAssetRow(
                                    asset: asset,
                                    photoLibraryManager: dataManager.photoLibraryManager,
                                    estimatedSizeMB: displaySizeMB(for: asset),
                                    sizeText: displaySizeText(for: asset),
                                    sizeSystemImage: sizeStatusSystemImage(for: asset),
                                    sizeTint: sizeStatusTint(for: asset),
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
            syncSelectionWithPendingDeleteCandidates()
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
        .alert(L10n.string("iCloud 视频"), isPresented: $showingICloudVideoInfo) {
            Button(L10n.string("知道了"), role: .cancel) {}
        } message: {
            Text(L10n.string("带云朵的视频当前只保存在 iCloud。列表不会自动下载大视频，预览或处理时会下载原片。"))
        }
        .task(id: mode.id) {
            reloadAssets()
        }
        .onChange(of: selectedFilter) { _ in
            pruneSelectionToFilteredAssets()
        }
        .onDisappear {
            sizeLoadingTask?.cancel()
        }
    }

    private var summaryTitle: String {
        switch mode {
        case .cleanup(.largeFiles):
            return L10n.string("共 \(filteredAssets.count) 个大文件")
        case .cleanup(.imageCompression):
            return L10n.string("共 \(filteredAssets.count) 张可压缩图片")
        case .cleanup(.videoCompression):
            return L10n.string("共 \(filteredAssets.count) 个可压缩视频")
        case .cleanup(.videos):
            return L10n.string("共 \(filteredAssets.count) 个视频")
        case .cleanup(.similarPhotos):
            return L10n.string("共 \(filteredAssets.count) 张相似照片")
        }
    }

    private var summarySubtitle: String {
        switch mode {
        case .cleanup(.largeFiles):
            if hasUnresolvedVideoSizes {
                return String(format: L10n.string("部分视频大小会在处理时确认，已知约 %@。"), CleanupStatsFormatter.space(filteredTotalSizeMB))
            }
            return L10n.string("按占用空间从大到小排序，合计约 \(CleanupStatsFormatter.space(filteredTotalSizeMB))。")
        case .cleanup(.imageCompression):
            return L10n.string("选择要压缩的图片，合计约 \(CleanupStatsFormatter.space(filteredTotalSizeMB))。")
        case .cleanup(.videoCompression):
            return L10n.string("选择要压缩的视频，合计约 \(CleanupStatsFormatter.space(filteredTotalSizeMB))。")
        case .cleanup(.videos):
            if hasUnresolvedVideoSizes {
                return String(format: L10n.string("已读取 %lld/%lld 个视频大小，已知约 %@。"), Int64(loadedReliableVideoSizeCount), Int64(filteredVideoAssets.count), CleanupStatsFormatter.space(filteredTotalSizeMB))
            }
            return L10n.string("按视频占用优先处理，合计约 \(CleanupStatsFormatter.space(filteredTotalSizeMB))。")
        case .cleanup(.similarPhotos):
            return L10n.string("建议优先处理相似组，合计约 \(CleanupStatsFormatter.space(filteredTotalSizeMB))。")
        }
    }

    private func reloadAssets() {
        let loadedAssets: [PHAsset]
        switch mode {
        case .cleanup(let kind):
            loadedAssets = dataManager.getPhotosForAdvancedCleanup(kind)
        }

        assets = loadedAssets
        pruneVideoSizeEstimates(for: loadedAssets)
        pruneSelectionToFilteredAssets()
        loadVideoSizes(for: loadedAssets)
    }

    private func matches(asset: PHAsset, filter: AdvancedCleanupFilter) -> Bool {
        switch filter {
        case .all, .recommended, .burst:
            return true
        case .videos:
            return asset.mediaType == .video
        case .photos:
            return asset.mediaType == .image
        case .large:
            return sizeForFiltering(asset) >= (asset.mediaType == .video ? 80 : 18)
        case .long:
            return asset.mediaType == .video && asset.duration >= 60
        case .month:
            guard let creationDate = asset.creationDate else { return false }
            return Calendar.current.isDate(creationDate, equalTo: Date(), toGranularity: .month)
        }
    }

    private func sizeForFiltering(_ asset: PHAsset) -> Double {
        if asset.mediaType == .video {
            return reliableVideoSizeMB(for: asset) ?? dataManager.estimatedSizeMB(for: asset)
        }
        return dataManager.estimatedSizeMB(for: asset)
    }

    private func displaySizeMB(for asset: PHAsset) -> Double {
        if asset.mediaType == .video {
            return reliableVideoSizeMB(for: asset) ?? 0
        }
        return dataManager.estimatedSizeMB(for: asset)
    }

    private func displaySizeText(for asset: PHAsset) -> String? {
        guard asset.mediaType == .video else { return nil }
        guard let estimate = videoSizeEstimatesByAssetID[asset.localIdentifier] else {
            return L10n.string("计算中")
        }
        switch estimate.source {
        case .localFile, .bitrate:
            return CleanupStatsFormatter.space(estimate.sizeMB)
        case .iCloud:
            return L10n.string("待下载")
        case .unavailable:
            return L10n.string("待确认")
        }
    }

    private func sizeStatusSystemImage(for asset: PHAsset) -> String? {
        guard videoSizeEstimatesByAssetID[asset.localIdentifier]?.source == .iCloud else {
            return nil
        }
        return "icloud.and.arrow.down"
    }

    private func sizeStatusTint(for asset: PHAsset) -> Color {
        guard videoSizeEstimatesByAssetID[asset.localIdentifier]?.source == .iCloud else {
            return PhotoDeleteStyle.positive
        }
        return PhotoDeleteStyle.accent
    }

    private func reliableVideoSizeMB(for asset: PHAsset) -> Double? {
        guard let estimate = videoSizeEstimatesByAssetID[asset.localIdentifier],
              estimate.isReliable else {
            return nil
        }
        return estimate.sizeMB
    }

    private func pruneVideoSizeEstimates(for loadedAssets: [PHAsset]) {
        let loadedIDs = Set(loadedAssets.map(\.localIdentifier))
        videoSizeEstimatesByAssetID = videoSizeEstimatesByAssetID.filter { loadedIDs.contains($0.key) }
    }

    private func loadVideoSizes(for loadedAssets: [PHAsset]) {
        sizeLoadingTask?.cancel()
        let videos = loadedAssets.filter { $0.mediaType == .video }
        guard !videos.isEmpty else { return }

        sizeLoadingTask = Task {
            for asset in videos {
                if Task.isCancelled { break }
                let alreadyLoaded = await MainActor.run {
                    videoSizeEstimatesByAssetID[asset.localIdentifier]?.isReliable == true
                }
                if alreadyLoaded { continue }

                do {
                    let estimate = try await dataManager.photoLibraryManager.videoFileSizeEstimate(for: asset)
                    await MainActor.run {
                        videoSizeEstimatesByAssetID[asset.localIdentifier] = estimate
                    }
                } catch {
                    continue
                }
            }
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
        let visibleIDs = Set(filteredAssets.map(\.localIdentifier))
        if isAllFilteredSelected {
            selectedAssetIDs.subtract(visibleIDs)
        } else {
            selectedAssetIDs.formUnion(visibleIDs)
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

    private func syncSelectionWithPendingDeleteCandidates() {
        let pendingDeleteIDs = Set(dataManager.deleteCandidates.map(\.localIdentifier))
        selectedAssetIDs = selectedAssetIDs.filter { pendingDeleteIDs.contains($0) }
    }

    private func showICloudVideoInfo() {
        showingICloudVideoInfo = true
    }

    private func pruneSelectionToFilteredAssets() {
        let visibleIDs = Set(filteredAssets.map(\.localIdentifier))
        selectedAssetIDs = selectedAssetIDs.filter { visibleIDs.contains($0) }
    }
}

private struct AdvancedImageCompressionView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var assets: [PHAsset] = []
    @State private var selectedAssetIDs: Set<String> = []
    @State private var compressionPlan: ImageCompressionPlan = .default
    @State private var isCompressing = false
    @State private var processedImageCount = 0
    @State private var compressionTotalCount = 0
    @State private var currentCompressionProgress: Double = 0
    @State private var currentCompressionMessage: String?
    @State private var compressionErrorMessage: String?
    @State private var compressionResult: AdvancedImageCompressionResult?
    @State private var showingCompressionComparison = false
    @State private var dismissCompressionResultAfterBatch = false
    @State private var previewAsset: AdvancedPreviewAsset?
    @State private var showBatchConfirm = false
    @State private var compressionOptionsContext: AdvancedImageCompressionOptionsContext?
    @State private var compressionTask: Task<Void, Never>?

    private var selectedAssets: [PHAsset] {
        compressibleAssets.filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var compressibleAssets: [PHAsset] {
        assets.filter { !processedImageAssetIDs.contains($0.localIdentifier) }
    }

    private var isAllSelected: Bool {
        !compressibleAssets.isEmpty && compressibleAssets.allSatisfy { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var processedImageAssetIDs: Set<String> {
        compressedOriginalAssetIDs.union(compressedImageAssetIDs)
    }

    private var compressedOriginalAssetIDs: Set<String> {
        Set(dataManager.imageCompressionHistoryStore.sessions.flatMap { session in
            session.items.map(\.originalAssetIdentifier)
        })
    }

    private var compressedImageAssetIDs: Set<String> {
        Set(dataManager.imageCompressionHistoryStore.sessions.flatMap { session in
            session.items.compactMap(\.createdAssetIdentifier)
        })
    }

    private var imageListSizeSummary: String {
        guard !compressibleAssets.isEmpty else { return L10n.string("没有需要压缩的图片") }
        let totalSize = compressibleAssets.reduce(0) { $0 + dataManager.estimatedSizeMB(for: $1) }
        return String(format: L10n.string("%lld 张图片 · 合计约 %@"), Int64(compressibleAssets.count), CleanupStatsFormatter.space(totalSize))
    }

    private var selectedCompressionEstimate: ImageCompressionEstimate? {
        guard !selectedAssets.isEmpty else { return nil }
        return dataManager.estimatedImageCompressionEstimate(for: selectedAssets, plan: compressionPlan)
    }

    private var selectedCompressionEstimateText: String {
        guard let selectedCompressionEstimate else {
            return L10n.string("先选择图片")
        }
        return String(format: L10n.string("预计压缩后 %@"), selectedCompressionEstimate.formattedCompressedRange)
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(spacing: 14) {
                    if isCompressing {
                        AdvancedVideoCompressionProgressCard(
                            processedCount: processedImageCount,
                            totalCount: compressionTotalCount,
                            currentProgress: currentCompressionProgress,
                            message: currentCompressionMessage
                        )
                    }

                    if let compressionResult {
                        AdvancedImageCompressionResultCard(
                            result: compressionResult,
                            onCompare: showCompressionComparison,
                            onDeleteOriginals: queueOriginalImagesForDeletion,
                            onKeepOriginals: keepOriginalImages
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
                            icon: AdvancedCleanupKind.imageCompression.icon,
                            title: L10n.string("未找到可压缩的图片"),
                            subtitle: L10n.string("当前照片库里暂时没有适合压缩的普通图片。")
                        )
                    } else {
                        AdvancedImageCompressionListHeader(
                            sizeSummary: imageListSizeSummary,
                            isAllSelected: isAllSelected,
                            isDisabled: isCompressing || compressibleAssets.isEmpty,
                            action: toggleBulkSelection
                        )

                        if compressibleAssets.isEmpty {
                            AdvancedEmptyState(
                                icon: "checkmark.circle",
                                title: L10n.string("没有需要压缩的图片"),
                                subtitle: L10n.string("压缩完成的图片会留在最近压缩记录里。")
                            )
                        } else {
                            LazyVStack(spacing: 9) {
                                ForEach(compressibleAssets, id: \.localIdentifier) { asset in
                                    AdvancedAssetRow(
                                        asset: asset,
                                        photoLibraryManager: dataManager.photoLibraryManager,
                                        estimatedSizeMB: dataManager.estimatedSizeMB(for: asset),
                                        sizeText: CleanupStatsFormatter.space(dataManager.estimatedSizeMB(for: asset)),
                                        isSelected: selectedAssetIDs.contains(asset.localIdentifier),
                                        onToggleSelection: { toggleSelection(asset) },
                                        onPreview: { previewAsset = AdvancedPreviewAsset(asset: asset) }
                                    )
                                }
                            }
                        }
                    }

                    if !dataManager.imageCompressionHistoryStore.sessions.isEmpty {
                        AdvancedImageCompressionHistoryCard(
                            sessions: Array(dataManager.imageCompressionHistoryStore.sessions.prefix(4)),
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
                AdvancedImageCompressionActionBar(
                    count: selectedAssetIDs.count,
                    estimateText: selectedCompressionEstimateText,
                    processedCount: processedImageCount,
                    isCompressing: isCompressing,
                    onCompress: presentCompressionOptions,
                    onDelete: deleteSelectedImages
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .advancedDetailNavigation(title: AdvancedCleanupKind.imageCompression.title)
        .fullScreenCover(isPresented: $showBatchConfirm, onDismiss: {
            reloadAssets()
            if dismissCompressionResultAfterBatch {
                compressionResult = nil
                dismissCompressionResultAfterBatch = false
            }
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
        .sheet(isPresented: $showingCompressionComparison) {
            if let compressionResult {
                AdvancedImageCompressionComparisonSheet(
                    result: compressionResult,
                    photoLibraryManager: dataManager.photoLibraryManager
                )
            }
        }
        .sheet(item: $compressionOptionsContext) { context in
            AdvancedImageCompressionOptionsSheet(
                context: context,
                initialPlan: compressionPlan
            ) { plan, images in
                compressionPlan = plan
                compressSelectedImages(images: images, plan: plan)
            }
            .environmentObject(dataManager)
        }
        .task {
            reloadAssets()
        }
        .onDisappear {
            compressionTask?.cancel()
        }
    }

    private func reloadAssets() {
        let loadedAssets = dataManager.getPhotosForAdvancedCleanup(.imageCompression)
        assets = loadedAssets
        selectedAssetIDs = selectedAssetIDs.filter { selectedID in
            loadedAssets.contains { $0.localIdentifier == selectedID }
        }
        pruneSelectionToCompressibleAssets()
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
        compressionErrorMessage = nil
    }

    private func toggleBulkSelection() {
        guard !isCompressing else { return }
        HapticManager.impact(.light)
        let visibleIDs = Set(compressibleAssets.map(\.localIdentifier))
        if isAllSelected {
            selectedAssetIDs.subtract(visibleIDs)
        } else {
            selectedAssetIDs.formUnion(visibleIDs)
        }
        compressionErrorMessage = nil
    }

    private func pruneSelectionToCompressibleAssets() {
        let visibleIDs = Set(compressibleAssets.map(\.localIdentifier))
        selectedAssetIDs = selectedAssetIDs.filter { visibleIDs.contains($0) }
    }

    private func presentCompressionOptions() {
        let images = selectedAssets
        guard !images.isEmpty, !isCompressing else { return }
        compressionOptionsContext = AdvancedImageCompressionOptionsContext(assets: images)
    }

    private func deleteSelectedImages() {
        let images = selectedAssets
        guard !images.isEmpty, !isCompressing else { return }

        for asset in images {
            _ = dataManager.markReviewed(asset)
            dataManager.addToDeleteCandidates(asset)
        }
        HapticManager.notify(.warning)
        showBatchConfirm = true
    }

    private func compressSelectedImages(images: [PHAsset], plan: ImageCompressionPlan) {
        guard !images.isEmpty, !isCompressing else { return }
        isCompressing = true
        processedImageCount = 0
        compressionTotalCount = images.count
        currentCompressionProgress = 0
        currentCompressionMessage = L10n.string("正在准备压缩")
        compressionErrorMessage = nil
        compressionResult = nil
        compressionTask?.cancel()
        compressionTask = Task {
            let backgroundTaskID = await MainActor.run {
                beginCompressionBackgroundTask()
            }
            var resultItems: [AdvancedImageCompressionResultItem] = []
            var failedCount = 0
            var firstErrorMessage: String?

            for (index, asset) in images.enumerated() {
                if Task.isCancelled {
                    break
                }

                await MainActor.run {
                    processedImageCount = index
                    currentCompressionProgress = 0
                    currentCompressionMessage = String(format: L10n.string("正在处理第 %lld 张图片"), Int64(index + 1))
                }

                do {
                    let result = try await dataManager.photoLibraryManager.compressImage(
                        asset,
                        plan: plan
                    ) { progress, message in
                        currentCompressionProgress = progress
                        currentCompressionMessage = message
                    }
                    resultItems.append(AdvancedImageCompressionResultItem(result: result))
                } catch is CancellationError {
                    break
                } catch {
                    failedCount += 1
                    if firstErrorMessage == nil {
                        firstErrorMessage = error.localizedDescription
                    }
                }

                await MainActor.run {
                    processedImageCount = index + 1
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
                    let completedResult = AdvancedImageCompressionResult(
                        items: resultItems,
                        failedCount: failedCount,
                        completedAt: Date(),
                        plan: plan
                    )
                    compressionResult = completedResult
                    dataManager.recordImageCompressionSession(
                        imageCount: completedResult.successCount,
                        failedCount: failedCount,
                        originalSizeMB: completedResult.originalSizeMB,
                        compressedSizeMB: completedResult.compressedSizeMB,
                        date: completedResult.completedAt,
                        items: completedResult.historyItems
                    )
                    selectedAssetIDs.removeAll()
                    reloadAssets()
                    showingCompressionComparison = false
                    HapticManager.notify(.success)
                } else if !wasCancelled {
                    compressionErrorMessage = firstErrorMessage ?? L10n.string("图片压缩失败，请稍后再试。")
                    HapticManager.notify(.warning)
                }

                if failedCount > 0 && !resultItems.isEmpty {
                    compressionErrorMessage = String(format: L10n.string("有 %lld 张图片未完成"), Int64(failedCount))
                }

                endCompressionBackgroundTask(backgroundTaskID)
            }
        }
    }

    private func beginCompressionBackgroundTask() -> UIBackgroundTaskIdentifier {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "PhotoDelete.ImageCompression") {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }
        return taskID
    }

    private func endCompressionBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
    }

    private func showCompressionComparison() {
        guard compressionResult?.createdAssetIdentifiers.isEmpty == false else {
            compressionErrorMessage = L10n.string("暂时找不到压缩后图片。")
            return
        }
        showingCompressionComparison = true
    }

    private func queueOriginalImagesForDeletion() {
        guard let compressionResult else { return }
        guard compressionResult.hasMeaningfulSavings else {
            compressionErrorMessage = L10n.string("这次没有明显减少空间，建议先保留原图。")
            return
        }

        let originalIDs = Set(compressionResult.items.map(\.originalAssetIdentifier))
        let fetchedOriginals = PHAsset.fetchAssets(withLocalIdentifiers: Array(originalIDs), options: nil)
        var originalAssets: [PHAsset] = []
        fetchedOriginals.enumerateObjects { asset, _, _ in
            originalAssets.append(asset)
        }
        guard !originalAssets.isEmpty else {
            compressionErrorMessage = L10n.string("暂时找不到原图。")
            return
        }

        for asset in originalAssets {
            _ = dataManager.markReviewed(asset)
            dataManager.addToDeleteCandidates(asset)
        }
        HapticManager.notify(.warning)
        dismissCompressionResultAfterBatch = true
        showBatchConfirm = true
    }

    private func keepOriginalImages() {
        compressionResult = nil
        compressionErrorMessage = nil
        showingCompressionComparison = false
    }
}

private struct AdvancedImageCompressionResultItem: Identifiable, Equatable {
    let originalAssetIdentifier: String
    let createdAssetIdentifier: String?
    let originalSizeMB: Double
    let compressedSizeMB: Double
    let originalDimensions: CGSize
    let outputDimensions: CGSize

    var id: String { originalAssetIdentifier }

    init(result: ImageCompressionResult) {
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
        savedSizeMB >= max(0.5, originalSizeMB * 0.03)
    }
}

private struct AdvancedImageCompressionResult: Equatable {
    let items: [AdvancedImageCompressionResultItem]
    let failedCount: Int
    let completedAt: Date
    let plan: ImageCompressionPlan

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
        savedSizeMB >= max(0.5, originalSizeMB * 0.03)
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

    var savedRatioText: String {
        guard originalSizeMB > 0 else { return "0%" }
        return "\(max(Int((savedSizeMB / originalSizeMB * 100).rounded()), 0))%"
    }

    var createdCopiesText: String {
        String(format: L10n.string("%lld 张"), Int64(successCount))
    }

    var completionTitle: String {
        failedCount > 0 ? L10n.string("压缩部分完成") : L10n.string("压缩完成")
    }

    var completionSubtitle: String {
        if successCount == 1 {
            return L10n.string("已生成 1 张压缩后图片")
        }
        return String(format: L10n.string("已生成 %lld 张压缩后图片"), Int64(successCount))
    }

    var createdAssetIdentifiers: [String] {
        items.compactMap(\.createdAssetIdentifier)
    }

    var historyItems: [ImageCompressionSessionItem] {
        items.map { item in
            ImageCompressionSessionItem(
                originalAssetIdentifier: item.originalAssetIdentifier,
                createdAssetIdentifier: item.createdAssetIdentifier,
                originalSizeMB: item.originalSizeMB,
                compressedSizeMB: item.compressedSizeMB
            )
        }
    }

    var sizeSummaryText: String {
        guard let firstItem = items.first else { return L10n.string("保持原尺寸") }

        if items.count == 1 {
            let original = dimensionsText(firstItem.originalDimensions)
            let output = dimensionsText(firstItem.outputDimensions)
            if original == output {
                return String(format: L10n.string("保持 %@"), original)
            }
            return String(format: L10n.string("%@ → %@"), original, output)
        }

        let allKeptOriginalSize = items.allSatisfy { item in
            dimensionsText(item.originalDimensions) == dimensionsText(item.outputDimensions)
        }
        if allKeptOriginalSize {
            return L10n.string("全部保持原尺寸")
        }

        let outputDimensions = Set(items.map { dimensionsText($0.outputDimensions) })
        if outputDimensions.count == 1, let output = outputDimensions.first {
            return String(format: L10n.string("输出 %@"), output)
        }

        return L10n.string("多种尺寸")
    }

    private func dimensionsText(_ size: CGSize) -> String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return L10n.string("未知") }
        return "\(width)×\(height)"
    }
}

private struct AdvancedImageCompressionListHeader: View {
    let sizeSummary: String
    let isAllSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("可压缩图片"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(sizeSummary)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            AdvancedBulkSelectionButton(
                title: isAllSelected ? L10n.string("取消") : L10n.string("全选"),
                isDisabled: isDisabled,
                action: action
            )
        }
        .padding(.top, 2)
    }
}

private struct AdvancedImageCompressionOptionsContext: Identifiable {
    let id = UUID()
    let assets: [PHAsset]

    var count: Int { assets.count }
}

private struct AdvancedImageCompressionOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager

    let context: AdvancedImageCompressionOptionsContext
    let onStart: (ImageCompressionPlan, [PHAsset]) -> Void
    @State private var plan: ImageCompressionPlan

    init(
        context: AdvancedImageCompressionOptionsContext,
        initialPlan: ImageCompressionPlan,
        onStart: @escaping (ImageCompressionPlan, [PHAsset]) -> Void
    ) {
        self.context = context
        self.onStart = onStart
        _plan = State(initialValue: initialPlan)
    }

    private var visibleEstimate: ImageCompressionEstimate {
        dataManager.estimatedImageCompressionEstimate(for: context.assets, plan: plan)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AdvancedImageCompressionEstimateCard(
                        count: context.count,
                        estimate: visibleEstimate
                    )

                    AdvancedVideoCompressionOptionSection(
                        title: L10n.string("质量")
                    ) {
                        AdvancedImageCompressionQualityPicker(selection: $plan.quality)
                    }

                    AdvancedVideoCompressionOptionSection(
                        title: L10n.string("尺寸")
                    ) {
                        AdvancedImageCompressionSizePicker(selection: $plan.size)
                    }

                    Label(L10n.string("图片压缩会生成新的 JPEG 副本，原图不会自动删除。最终节省空间以完成报告为准。"), systemImage: "info.circle")
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
                        Text(String(format: L10n.string("开始压缩 %lld 张图片"), Int64(context.count)))
                            .font(.system(size: 15, weight: .semibold))
                        Text(String(format: L10n.string("预计压缩后 %@"), visibleEstimate.formattedCompressedRange))
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

private struct AdvancedImageCompressionEstimateCard: View {
    let count: Int
    let estimate: ImageCompressionEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: AdvancedCleanupKind.imageCompression.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: L10n.string("准备压缩 %lld 张图片"), Int64(count)))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(String(format: L10n.string("原文件合计约 %@"), estimate.formattedOriginalSize))
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

private struct AdvancedImageCompressionQualityPicker: View {
    @Binding var selection: ImageCompressionQuality

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ImageCompressionQuality.allCases) { quality in
                AdvancedVideoCompressionSegmentButton(
                    title: quality.compactTitle,
                    isSelected: selection == quality
                ) {
                    selection = quality
                }
            }
        }
    }
}

private struct AdvancedImageCompressionSizePicker: View {
    @Binding var selection: ImageCompressionSize

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ImageCompressionSize.allCases) { size in
                AdvancedVideoCompressionSegmentButton(
                    title: size.title,
                    isSelected: selection == size
                ) {
                    selection = size
                }
            }
        }
    }
}

private struct AdvancedImageCompressionResultCard: View {
    let result: AdvancedImageCompressionResult
    let onCompare: () -> Void
    let onDeleteOriginals: () -> Void
    let onKeepOriginals: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: result.hasMeaningfulSavings ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.positive)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.completionTitle)
                        .font(.headline)
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(result.completionSubtitle)
                        .font(.subheadline)
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(result.formattedSavedSize)
                        .font(.title3.weight(.bold))
                        .foregroundColor(result.hasMeaningfulSavings ? PhotoDeleteStyle.positive : PhotoDeleteStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(L10n.string("已节省"))
                        .font(.caption)
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                AdvancedVideoCompressionMetric(label: L10n.string("方案"), value: result.plan.title)
                AdvancedVideoCompressionMetric(label: L10n.string("原图"), value: result.formattedOriginalSize)
                AdvancedVideoCompressionMetric(label: L10n.string("压缩后"), value: result.formattedCompressedSize)
                AdvancedVideoCompressionMetric(label: L10n.string("节省比例"), value: result.savedRatioText)
            }

            VStack(spacing: 0) {
                AdvancedVideoCompressionResultInfoRow(
                    systemImage: "photo",
                    title: L10n.string("压缩后图片"),
                    value: result.createdCopiesText,
                    tint: PhotoDeleteStyle.positive
                )

                Divider()
                    .padding(.leading, 34)

                AdvancedVideoCompressionResultInfoRow(
                    systemImage: "arrow.down.right.and.arrow.up.left",
                    title: L10n.string("尺寸"),
                    value: result.sizeSummaryText,
                    tint: PhotoDeleteStyle.accent
                )
            }

            Text(result.hasMeaningfulSavings ? L10n.string("已生成压缩后图片，原图尚未删除。请先查看对比，再决定是否删除原图。") : L10n.string("已生成压缩后图片，但空间减少不明显。建议先保留原图。"))
                .font(.footnote)
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if result.failedCount > 0 {
                Label(String(format: L10n.string("%lld 张图片未完成"), Int64(result.failedCount)), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.warning)
            }

            VStack(spacing: 10) {
                Button(action: onCompare) {
                    Label(L10n.string("查看对比"), systemImage: "rectangle.split.2x1")
                        .frame(maxWidth: .infinity)
                }
                .photoDeletePrimaryButton()
                .disabled(result.createdAssetIdentifiers.isEmpty)

                HStack(spacing: 10) {
                    AdvancedVideoCompressionCompactActionButton(
                        title: L10n.string("删除原图"),
                        systemImage: "trash",
                        tint: PhotoDeleteStyle.destructive,
                        isEnabled: result.hasMeaningfulSavings,
                        action: onDeleteOriginals
                    )

                    AdvancedVideoCompressionCompactActionButton(
                        title: L10n.string("保留原图"),
                        systemImage: "checkmark",
                        tint: PhotoDeleteStyle.accent,
                        isEnabled: true,
                        action: onKeepOriginals
                    )
                }
            }
        }
        .padding(16)
        .photoDeleteCard()
    }
}

private struct AdvancedImageCompressionComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let result: AdvancedImageCompressionResult
    let photoLibraryManager: PhotoLibraryManager
    @State private var previewAsset: AdvancedPreviewAsset?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        AdvancedVideoCompressionMetric(label: L10n.string("原图"), value: result.formattedOriginalSize)
                        AdvancedVideoCompressionMetric(label: L10n.string("压缩后"), value: result.formattedCompressedSize)
                        AdvancedVideoCompressionMetric(label: L10n.string("已节省"), value: result.formattedSavedSize)
                    }

                    ForEach(result.items) { item in
                        AdvancedImageCompressionComparisonRow(
                            item: item,
                            photoLibraryManager: photoLibraryManager
                        ) { asset in
                            previewAsset = AdvancedPreviewAsset(asset: asset)
                        }
                    }
                }
                .padding(PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.vertical, 16)
            }
            .background(PhotoDeleteStyle.background.ignoresSafeArea())
            .navigationTitle(L10n.string("图片对比"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $previewAsset) { item in
            AdvancedAssetPreviewView(
                asset: item.asset,
                photoLibraryManager: photoLibraryManager
            )
        }
    }
}

private struct AdvancedImageCompressionComparisonRow: View {
    let item: AdvancedImageCompressionResultItem
    let photoLibraryManager: PhotoLibraryManager
    let onPreview: (PHAsset) -> Void

    private var originalAsset: PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [item.originalAssetIdentifier], options: nil).firstObject
    }

    private var compressedAsset: PHAsset? {
        guard let createdAssetIdentifier = item.createdAssetIdentifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [createdAssetIdentifier], options: nil).firstObject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                comparisonButton(
                    label: L10n.string("原图"),
                    size: CleanupStatsFormatter.space(item.originalSizeMB),
                    asset: originalAsset,
                    fallbackIcon: "photo"
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)

                comparisonButton(
                    label: L10n.string("压缩后"),
                    size: CleanupStatsFormatter.space(item.compressedSizeMB),
                    asset: compressedAsset,
                    fallbackIcon: "photo"
                )
            }

            Text(String(format: L10n.string("减少 %@"), CleanupStatsFormatter.space(item.savedSizeMB)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.positive)
        }
        .padding(12)
        .photoDeleteCard()
    }

    private func comparisonButton(
        label: String,
        size: String,
        asset: PHAsset?,
        fallbackIcon: String
    ) -> some View {
        Button {
            if let asset {
                onPreview(asset)
            }
        } label: {
            VStack(spacing: 8) {
                if let asset {
                    AdvancedAssetThumbnail(
                        asset: asset,
                        photoLibraryManager: photoLibraryManager,
                        size: 82
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PhotoDeleteStyle.elevatedSurface)
                        .frame(width: 82, height: 82)
                        .overlay(
                            Image(systemName: fallbackIcon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                        )
                }

                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                    Text(size)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PhotoDeleteStyle.elevatedSurface)
            )
        }
        .buttonStyle(.plain)
        .disabled(asset == nil)
    }
}

private struct AdvancedImageCompressionHistoryCard: View {
    let sessions: [ImageCompressionSession]
    let photoLibraryManager: PhotoLibraryManager
    @State private var isExpanded = false

    private var summaryText: String {
        let savedSizeMB = sessions.reduce(0) { $0 + $1.savedSizeMB }
        return String(
            format: L10n.string("最近压缩记录 · %lld 次 · 已减少 %@"),
            Int64(sessions.count),
            CleanupStatsFormatter.space(savedSizeMB)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.accent)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("最近压缩记录"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.primaryText)

                        Text(summaryText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? Text(L10n.string("已展开")) : Text(L10n.string("已折叠")))

            if isExpanded {
                Divider()
                    .background(PhotoDeleteStyle.hairline)

                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        HStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.positive)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.formattedDate)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(PhotoDeleteStyle.primaryText)

                                Text(String(format: L10n.string("%lld 张图片 · %@ → %@"), Int64(session.imageCount), session.formattedOriginalSize, session.formattedCompressedSize))
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
                                    AdvancedImageCompressionHistoryItemRow(
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct AdvancedImageCompressionHistoryItemRow: View {
    let item: ImageCompressionSessionItem
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
                    label: L10n.string("原图"),
                    title: title(for: originalAsset, fallback: L10n.string("原图可能已删除")),
                    size: item.formattedOriginalSize
                )

                historyLine(
                    label: L10n.string("压缩后"),
                    title: title(for: compressedAsset, fallback: L10n.string("压缩后图片可能已删除")),
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

private struct AdvancedImageCompressionActionBar: View {
    let count: Int
    let estimateText: String
    let processedCount: Int
    let isCompressing: Bool
    let onCompress: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !isCompressing {
                Text(String(format: L10n.string("已选择 %lld 张图片 · %@"), Int64(count), estimateText))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button(role: .destructive, action: onDelete) {
                    Label(L10n.string("删除选中"), systemImage: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(PhotoDeleteStyle.destructive.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(PhotoDeleteStyle.destructive.opacity(0.24), lineWidth: 1)
                                )
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

private struct AdvancedVideoCompressionView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var assets: [PHAsset] = []
    @State private var videoSizeEstimatesByAssetID: [String: VideoFileSizeEstimate] = [:]
    @State private var selectedAssetIDs: Set<String> = []
    @State private var compressionPlan: VideoCompressionPlan = .default
    @State private var isCompressing = false
    @State private var processedVideoCount = 0
    @State private var compressionTotalCount = 0
    @State private var currentCompressionProgress: Double = 0
    @State private var currentCompressionMessage: String?
    @State private var compressionErrorMessage: String?
    @State private var compressionResult: AdvancedVideoCompressionResult?
    @State private var showingCompressionComparison = false
    @State private var showingICloudVideoInfo = false
    @State private var dismissCompressionResultAfterBatch = false
    @State private var previewAsset: AdvancedPreviewAsset?
    @State private var showBatchConfirm = false
    @State private var compressionOptionsContext: AdvancedVideoCompressionOptionsContext?
    @State private var compressionTask: Task<Void, Never>?
    @State private var sizeLoadingTask: Task<Void, Never>?

    private var selectedAssets: [PHAsset] {
        compressibleAssets.filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var compressibleAssets: [PHAsset] {
        assets.filter { !processedVideoAssetIDs.contains($0.localIdentifier) }
    }

    private var isAllSelected: Bool {
        !compressibleAssets.isEmpty && compressibleAssets.allSatisfy { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var processedVideoAssetIDs: Set<String> {
        compressedOriginalAssetIDs.union(compressedVideoAssetIDs)
    }

    private var compressedOriginalAssetIDs: Set<String> {
        Set(dataManager.videoCompressionHistoryStore.sessions.flatMap { session in
            session.items.map(\.originalAssetIdentifier)
        })
    }

    private var compressedVideoAssetIDs: Set<String> {
        Set(dataManager.videoCompressionHistoryStore.sessions.flatMap { session in
            session.items.compactMap(\.createdAssetIdentifier)
        })
    }

    private var reliableVideoSizeMBByAssetID: [String: Double] {
        videoSizeEstimatesByAssetID.reduce(into: [String: Double]()) { result, pair in
            guard pair.value.isReliable else { return }
            result[pair.key] = pair.value.sizeMB
        }
    }

    private var loadedReliableVideoSizeCount: Int {
        loadedReliableVideoSizeCount(in: compressibleAssets)
    }

    private var loadedVideoSizeCount: Int {
        loadedVideoSizeCount(in: compressibleAssets)
    }

    private var iCloudVideoCount: Int {
        iCloudVideoCount(in: compressibleAssets)
    }

    private var compressibleTotalSizeMB: Double {
        compressibleAssets.reduce(0) { $0 + (reliableSizeMB(for: $1) ?? 0) }
    }

    private func loadedReliableVideoSizeCount(in assets: [PHAsset]) -> Int {
        assets.reduce(0) { partial, asset in
            reliableSizeMB(for: asset) == nil ? partial : partial + 1
        }
    }

    private func loadedVideoSizeCount(in assets: [PHAsset]) -> Int {
        assets.reduce(0) { partial, asset in
            videoSizeEstimatesByAssetID[asset.localIdentifier] == nil ? partial : partial + 1
        }
    }

    private func iCloudVideoCount(in assets: [PHAsset]) -> Int {
        assets.reduce(0) { partial, asset in
            videoSizeEstimatesByAssetID[asset.localIdentifier]?.source == .iCloud ? partial + 1 : partial
        }
    }

    private var videoListSizeSummary: String {
        guard !compressibleAssets.isEmpty else { return L10n.string("没有需要压缩的视频") }

        if loadedReliableVideoSizeCount == compressibleAssets.count {
            return String(format: L10n.string("%lld 个视频 · 合计约 %@"), Int64(compressibleAssets.count), CleanupStatsFormatter.space(compressibleTotalSizeMB))
        }

        if loadedReliableVideoSizeCount > 0 {
            return String(
                format: L10n.string("已读取 %lld/%lld · 已知约 %@"),
                Int64(loadedReliableVideoSizeCount),
                Int64(compressibleAssets.count),
                CleanupStatsFormatter.space(compressibleTotalSizeMB)
            )
        }

        if loadedVideoSizeCount == compressibleAssets.count {
            return String(format: L10n.string("%lld 个视频 · 压缩时确认大小"), Int64(compressibleAssets.count))
        }

        return String(format: L10n.string("%lld 个视频 · 正在计算大小"), Int64(compressibleAssets.count))
    }

    private var selectedCompressionEstimate: VideoCompressionEstimate? {
        guard hasReliableSizes(for: selectedAssets) else { return nil }
        return dataManager.estimatedVideoCompressionEstimate(
            for: selectedAssets,
            plan: compressionPlan,
            knownOriginalSizeMBByAssetID: reliableVideoSizeMBByAssetID
        )
    }

    private var selectedCompressionEstimateText: String {
        guard let selectedCompressionEstimate else {
            return hasPendingSizeLoads(for: selectedAssets)
                ? L10n.string("正在计算预计大小")
                : L10n.string("压缩时确认实际大小")
        }
        return String(format: L10n.string("预计压缩后 %@"), selectedCompressionEstimate.formattedCompressedRange)
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
                            onCompare: showCompressionComparison,
                            onDeleteOriginals: queueOriginalVideosForDeletion,
                            onKeepOriginals: keepOriginalVideos
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
                            sizeSummary: videoListSizeSummary,
                            isAllSelected: isAllSelected,
                            isDisabled: isCompressing || compressibleAssets.isEmpty,
                            action: toggleBulkSelection
                        )

                        if iCloudVideoCount > 0 {
                            AdvancedVideoCompressionICloudInfoCard(
                                count: iCloudVideoCount,
                                subtitle: L10n.string("压缩时会下载原片并确认大小。"),
                                action: showICloudVideoInfo
                            )
                        }

                        if compressibleAssets.isEmpty {
                            AdvancedEmptyState(
                                icon: "checkmark.circle",
                                title: L10n.string("没有需要压缩的视频"),
                                subtitle: L10n.string("压缩完成的视频会留在最近压缩记录里。")
                            )
                        } else {
                            LazyVStack(spacing: 9) {
                                ForEach(compressibleAssets, id: \.localIdentifier) { asset in
                                    AdvancedAssetRow(
                                        asset: asset,
                                        photoLibraryManager: dataManager.photoLibraryManager,
                                        estimatedSizeMB: displaySizeMB(for: asset),
                                        sizeText: displaySizeText(for: asset),
                                        sizeSystemImage: sizeStatusSystemImage(for: asset),
                                        sizeTint: sizeStatusTint(for: asset),
                                        isSelected: selectedAssetIDs.contains(asset.localIdentifier),
                                        onToggleSelection: { toggleSelection(asset) },
                                        onPreview: { previewAsset = AdvancedPreviewAsset(asset: asset) }
                                    )
                                }
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
                    estimateText: selectedCompressionEstimateText,
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
            if dismissCompressionResultAfterBatch {
                compressionResult = nil
                dismissCompressionResultAfterBatch = false
            }
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
        .sheet(isPresented: $showingCompressionComparison) {
            if let compressionResult {
                AdvancedVideoCompressionComparisonSheet(
                    result: compressionResult,
                    photoLibraryManager: dataManager.photoLibraryManager
                )
            }
        }
        .alert(L10n.string("iCloud 视频"), isPresented: $showingICloudVideoInfo) {
            Button(L10n.string("知道了"), role: .cancel) {}
        } message: {
            Text(L10n.string("带云朵的视频当前只保存在 iCloud。列表不会自动下载大视频，开始压缩后会下载原片并确认实际大小。"))
        }
        .sheet(item: $compressionOptionsContext) { context in
            AdvancedVideoCompressionOptionsSheet(
                context: context,
                initialPlan: compressionPlan,
                knownOriginalSizeMBByAssetID: reliableVideoSizeMBByAssetID
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
        selectedAssetIDs = selectedAssetIDs.filter { selectedID in
            loadedAssets.contains { $0.localIdentifier == selectedID }
        }
        pruneSelectionToCompressibleAssets()
        loadVideoSizes(for: loadedAssets)
    }

    private func displaySizeMB(for asset: PHAsset) -> Double {
        reliableSizeMB(for: asset) ?? 0
    }

    private func displaySizeText(for asset: PHAsset) -> String {
        guard let estimate = videoSizeEstimatesByAssetID[asset.localIdentifier] else {
            return L10n.string("计算中")
        }
        switch estimate.source {
        case .localFile, .bitrate:
            return CleanupStatsFormatter.space(estimate.sizeMB)
        case .iCloud:
            return L10n.string("待下载")
        case .unavailable:
            return L10n.string("压缩时确认")
        }
    }

    private func sizeStatusSystemImage(for asset: PHAsset) -> String? {
        guard videoSizeEstimatesByAssetID[asset.localIdentifier]?.source == .iCloud else {
            return nil
        }
        return "icloud.and.arrow.down"
    }

    private func sizeStatusTint(for asset: PHAsset) -> Color {
        guard videoSizeEstimatesByAssetID[asset.localIdentifier]?.source == .iCloud else {
            return PhotoDeleteStyle.positive
        }
        return PhotoDeleteStyle.accent
    }

    private func reliableSizeMB(for asset: PHAsset) -> Double? {
        guard let estimate = videoSizeEstimatesByAssetID[asset.localIdentifier],
              estimate.isReliable else {
            return nil
        }
        return estimate.sizeMB
    }

    private func hasReliableSizes(for selectedAssets: [PHAsset]) -> Bool {
        !selectedAssets.isEmpty && selectedAssets.allSatisfy { reliableSizeMB(for: $0) != nil }
    }

    private func hasPendingSizeLoads(for selectedAssets: [PHAsset]) -> Bool {
        selectedAssets.contains { videoSizeEstimatesByAssetID[$0.localIdentifier] == nil }
    }

    private func loadVideoSizes(for loadedAssets: [PHAsset]) {
        sizeLoadingTask?.cancel()
        sizeLoadingTask = Task {
            for asset in loadedAssets {
                if Task.isCancelled { break }
                let alreadyLoaded = await MainActor.run {
                    videoSizeEstimatesByAssetID[asset.localIdentifier]?.isReliable == true
                }
                if alreadyLoaded { continue }

                do {
                    let estimate = try await dataManager.photoLibraryManager.videoFileSizeEstimate(for: asset)
                    await MainActor.run {
                        videoSizeEstimatesByAssetID[asset.localIdentifier] = estimate
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
        compressionErrorMessage = nil
    }

    private func toggleBulkSelection() {
        guard !isCompressing else { return }
        HapticManager.impact(.light)
        let visibleIDs = Set(compressibleAssets.map(\.localIdentifier))
        if isAllSelected {
            selectedAssetIDs.subtract(visibleIDs)
        } else {
            selectedAssetIDs.formUnion(visibleIDs)
        }
        compressionErrorMessage = nil
    }

    private func pruneSelectionToCompressibleAssets() {
        let visibleIDs = Set(compressibleAssets.map(\.localIdentifier))
        selectedAssetIDs = selectedAssetIDs.filter { visibleIDs.contains($0) }
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
            let backgroundTaskID = await MainActor.run {
                beginCompressionBackgroundTask()
            }
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
                    for item in resultItems {
                        videoSizeEstimatesByAssetID[item.originalAssetIdentifier] = VideoFileSizeEstimate(
                            sizeMB: item.originalSizeMB,
                            source: .localFile
                        )
                        if let createdAssetIdentifier = item.createdAssetIdentifier {
                            videoSizeEstimatesByAssetID[createdAssetIdentifier] = VideoFileSizeEstimate(
                                sizeMB: item.compressedSizeMB,
                                source: .localFile
                            )
                        }
                    }
                    selectedAssetIDs.removeAll()
                    reloadAssets()
                    showingCompressionComparison = false
                    HapticManager.notify(.success)
                } else if !wasCancelled {
                    compressionErrorMessage = firstErrorMessage ?? L10n.string("视频压缩失败，请稍后再试。")
                    HapticManager.notify(.warning)
                }

                if failedCount > 0 && !resultItems.isEmpty {
                    compressionErrorMessage = String(format: L10n.string("有 %lld 个视频未完成"), Int64(failedCount))
                }

                endCompressionBackgroundTask(backgroundTaskID)
            }
        }
    }

    private func beginCompressionBackgroundTask() -> UIBackgroundTaskIdentifier {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "PhotoDelete.VideoCompression") {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }
        return taskID
    }

    private func endCompressionBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
    }

    private func showCompressionComparison() {
        guard compressionResult?.createdAssetIdentifiers.isEmpty == false else {
            compressionErrorMessage = L10n.string("暂时找不到压缩后视频。")
            return
        }
        showingCompressionComparison = true
    }

    private func showICloudVideoInfo() {
        showingICloudVideoInfo = true
    }

    private func queueOriginalVideosForDeletion() {
        guard let compressionResult else { return }
        guard compressionResult.hasMeaningfulSavings else {
            compressionErrorMessage = L10n.string("这次没有明显减少空间，建议先保留原视频。")
            return
        }

        let originalIDs = Set(compressionResult.items.map(\.originalAssetIdentifier))
        let fetchedOriginals = PHAsset.fetchAssets(withLocalIdentifiers: Array(originalIDs), options: nil)
        var originalAssets: [PHAsset] = []
        fetchedOriginals.enumerateObjects { asset, _, _ in
            originalAssets.append(asset)
        }
        guard !originalAssets.isEmpty else {
            compressionErrorMessage = L10n.string("暂时找不到原视频。")
            return
        }

        for asset in originalAssets {
            _ = dataManager.markReviewed(asset)
            dataManager.addToDeleteCandidates(asset)
        }
        HapticManager.notify(.warning)
        dismissCompressionResultAfterBatch = true
        showBatchConfirm = true
    }

    private func keepOriginalVideos() {
        compressionResult = nil
        compressionErrorMessage = nil
        showingCompressionComparison = false
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

    var savedRatioText: String {
        "\(savedRatioPercent)%"
    }

    var createdCopiesText: String {
        String(format: L10n.string("%lld 个"), Int64(successCount))
    }

    var completionTitle: String {
        failedCount > 0 ? L10n.string("压缩部分完成") : L10n.string("压缩完成")
    }

    var completionSubtitle: String {
        if successCount == 1 {
            return L10n.string("已生成 1 个压缩后视频")
        }
        return String(format: L10n.string("已生成 %lld 个压缩后视频"), Int64(successCount))
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

    var resolutionSummaryText: String {
        guard let firstItem = items.first else { return L10n.string("保持原分辨率") }

        if items.count == 1 {
            let original = dimensionsText(firstItem.originalDimensions)
            let output = dimensionsText(firstItem.outputDimensions)
            if original == output {
                return String(format: L10n.string("保持 %@"), original)
            }
            return String(format: L10n.string("%@ → %@"), original, output)
        }

        let allKeptOriginalResolution = items.allSatisfy { item in
            dimensionsText(item.originalDimensions) == dimensionsText(item.outputDimensions)
        }
        if allKeptOriginalResolution {
            return L10n.string("全部保持原分辨率")
        }

        let outputDimensions = Set(items.map { dimensionsText($0.outputDimensions) })
        if outputDimensions.count == 1, let output = outputDimensions.first {
            return String(format: L10n.string("输出 %@"), output)
        }

        return L10n.string("多种分辨率")
    }

    private func dimensionsText(_ size: CGSize) -> String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return L10n.string("未知") }
        return "\(width)×\(height)"
    }
}

private struct AdvancedVideoCompressionListHeader: View {
    let sizeSummary: String
    let isAllSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("可压缩视频"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(sizeSummary)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            AdvancedBulkSelectionButton(
                title: isAllSelected ? L10n.string("取消") : L10n.string("全选"),
                isDisabled: isDisabled,
                action: action
            )
        }
        .padding(.top, 2)
    }
}

private struct AdvancedVideoCompressionICloudInfoCard: View {
    let count: Int
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(PhotoDeleteStyle.accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: L10n.string("%lld 个视频在 iCloud"), Int64(count)))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }
            .padding(12)
            .photoDeleteCard()
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(L10n.string("查看 iCloud 视频说明")))
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

            Label(L10n.string("压缩后视频会保存到照片库，原视频不会自动删除。"), systemImage: "info.circle")
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

    private var hasCompleteSizeEstimate: Bool {
        context.assets.allSatisfy { knownOriginalSizeMBByAssetID[$0.localIdentifier] != nil }
    }

    private var visibleEstimate: VideoCompressionEstimate? {
        guard hasCompleteSizeEstimate else { return nil }
        return dataManager.estimatedVideoCompressionEstimate(
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
                        estimate: visibleEstimate
                    )

                    AdvancedVideoCompressionOptionSection(
                        title: L10n.string("质量")
                    ) {
                        AdvancedVideoCompressionQualityPicker(selection: $plan.quality)
                    }

                    AdvancedVideoCompressionOptionSection(
                        title: L10n.string("分辨率")
                    ) {
                        AdvancedVideoCompressionResolutionPicker(selection: $plan.resolution)
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
                        Text(buttonSubtitle)
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

    private var buttonSubtitle: String {
        guard let visibleEstimate else {
            return L10n.string("压缩时确认实际大小")
        }
        return String(format: L10n.string("预计压缩后 %@"), visibleEstimate.formattedCompressedRange)
    }
}

private struct AdvancedVideoCompressionEstimateCard: View {
    let count: Int
    let estimate: VideoCompressionEstimate?

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

                    Text(originalSizeText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                AdvancedVideoCompressionMetric(label: L10n.string("预计压缩后"), value: estimate?.formattedCompressedRange ?? L10n.string("计算中"))
                AdvancedVideoCompressionMetric(label: L10n.string("预计节省"), value: estimate?.formattedSavedRange ?? L10n.string("计算中"))
            }
        }
        .padding(14)
        .photoDeleteCard()
    }

    private var originalSizeText: String {
        guard let estimate else {
            return L10n.string("压缩时确认原文件大小")
        }
        return String(format: L10n.string("原文件合计 %@"), estimate.formattedOriginalSize)
    }
}

private struct AdvancedVideoCompressionOptionSection<Content: View>: View {
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            content
        }
    }
}

private struct AdvancedVideoCompressionQualityPicker: View {
    @Binding var selection: VideoCompressionQuality

    var body: some View {
        HStack(spacing: 8) {
            ForEach(VideoCompressionQuality.allCases) { quality in
                AdvancedVideoCompressionSegmentButton(
                    title: quality.compactTitle,
                    isSelected: selection == quality
                ) {
                    selection = quality
                }
            }
        }
    }
}

private struct AdvancedVideoCompressionResolutionPicker: View {
    @Binding var selection: VideoCompressionResolution

    var body: some View {
        HStack(spacing: 8) {
            ForEach(VideoCompressionResolution.allCases) { resolution in
                AdvancedVideoCompressionSegmentButton(
                    title: resolution.title,
                    isSelected: selection == resolution
                ) {
                    selection = resolution
                }
            }
        }
    }
}

private struct AdvancedVideoCompressionSegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isSelected ? PhotoDeleteStyle.positive : PhotoDeleteStyle.primaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? PhotoDeleteStyle.positive.opacity(0.13) : PhotoDeleteStyle.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? PhotoDeleteStyle.positive.opacity(0.42) : PhotoDeleteStyle.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(isSelected ? L10n.string("已选") : L10n.string("未选择")))
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

                Text(message ?? L10n.string("正在压缩视频"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Label(L10n.string("请保持 App 打开，离开 App 可能暂停压缩。"), systemImage: "exclamationmark.circle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.warning)
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
    let onCompare: () -> Void
    let onDeleteOriginals: () -> Void
    let onKeepOriginals: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: result.hasMeaningfulSavings ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.positive)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.completionTitle)
                        .font(.headline)
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(result.completionSubtitle)
                        .font(.subheadline)
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(result.formattedSavedSize)
                        .font(.title3.weight(.bold))
                        .foregroundColor(result.hasMeaningfulSavings ? PhotoDeleteStyle.positive : PhotoDeleteStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(L10n.string("已节省"))
                        .font(.caption)
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                AdvancedVideoCompressionMetric(label: L10n.string("方案"), value: result.plan.title)
                AdvancedVideoCompressionMetric(label: L10n.string("原视频"), value: result.formattedOriginalSize)
                AdvancedVideoCompressionMetric(label: L10n.string("压缩后"), value: result.formattedCompressedSize)
                AdvancedVideoCompressionMetric(label: L10n.string("节省比例"), value: result.savedRatioText)
            }

            VStack(spacing: 0) {
                AdvancedVideoCompressionResultInfoRow(
                    systemImage: "video.badge.checkmark",
                    title: L10n.string("压缩后视频"),
                    value: result.createdCopiesText,
                    tint: PhotoDeleteStyle.positive
                )

                Divider()
                    .padding(.leading, 34)

                AdvancedVideoCompressionResultInfoRow(
                    systemImage: "arrow.down.right.and.arrow.up.left",
                    title: L10n.string("分辨率"),
                    value: result.resolutionSummaryText,
                    tint: PhotoDeleteStyle.accent
                )
            }

            Text(result.hasMeaningfulSavings ? L10n.string("已生成压缩后视频，原视频尚未删除。请先查看对比，再决定是否删除原视频。") : L10n.string("已生成压缩后视频，但空间减少不明显。建议先保留原视频。"))
                .font(.footnote)
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if result.failedCount > 0 {
                Label(String(format: L10n.string("%lld 个视频未完成"), Int64(result.failedCount)), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.warning)
            }

            VStack(spacing: 10) {
                Button(action: onCompare) {
                    Label(L10n.string("查看对比"), systemImage: "rectangle.split.2x1")
                        .frame(maxWidth: .infinity)
                }
                .photoDeletePrimaryButton()
                .disabled(result.createdAssetIdentifiers.isEmpty)

                HStack(spacing: 10) {
                    AdvancedVideoCompressionCompactActionButton(
                        title: L10n.string("删除原视频"),
                        systemImage: "trash",
                        tint: PhotoDeleteStyle.destructive,
                        isEnabled: result.hasMeaningfulSavings,
                        action: onDeleteOriginals
                    )

                    AdvancedVideoCompressionCompactActionButton(
                        title: L10n.string("保留原视频"),
                        systemImage: "checkmark",
                        tint: PhotoDeleteStyle.accent,
                        isEnabled: true,
                        action: onKeepOriginals
                    )
                }
            }
        }
        .padding(16)
        .photoDeleteCard()
    }
}

private struct AdvancedVideoCompressionResultInfoRow: View {
    let systemImage: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(tint.opacity(0.12))
                )
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline)
                .foregroundColor(PhotoDeleteStyle.secondaryText)

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct AdvancedVideoCompressionCompactActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isEnabled ? tint : PhotoDeleteStyle.tertiaryText)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                        .fill(PhotoDeleteStyle.elevatedSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                                .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
    }
}

private struct AdvancedVideoCompressionComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let result: AdvancedVideoCompressionResult
    let photoLibraryManager: PhotoLibraryManager
    @State private var previewAsset: AdvancedPreviewAsset?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        AdvancedVideoCompressionMetric(label: L10n.string("原视频"), value: result.formattedOriginalSize)
                        AdvancedVideoCompressionMetric(label: L10n.string("压缩后"), value: result.formattedCompressedSize)
                        AdvancedVideoCompressionMetric(label: L10n.string("已节省"), value: result.formattedSavedSize)
                    }

                    ForEach(result.items) { item in
                        AdvancedVideoCompressionComparisonRow(
                            item: item,
                            photoLibraryManager: photoLibraryManager
                        ) { asset in
                            previewAsset = AdvancedPreviewAsset(asset: asset)
                        }
                    }
                }
                .padding(PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.vertical, 16)
            }
            .background(PhotoDeleteStyle.background.ignoresSafeArea())
            .navigationTitle(L10n.string("视频对比"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $previewAsset) { item in
            AdvancedAssetPreviewView(
                asset: item.asset,
                photoLibraryManager: photoLibraryManager
            )
        }
    }
}

private struct AdvancedVideoCompressionComparisonRow: View {
    let item: AdvancedVideoCompressionResultItem
    let photoLibraryManager: PhotoLibraryManager
    let onPreview: (PHAsset) -> Void

    private var originalAsset: PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [item.originalAssetIdentifier], options: nil).firstObject
    }

    private var compressedAsset: PHAsset? {
        guard let createdAssetIdentifier = item.createdAssetIdentifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [createdAssetIdentifier], options: nil).firstObject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                comparisonButton(
                    label: L10n.string("原视频"),
                    size: CleanupStatsFormatter.space(item.originalSizeMB),
                    asset: originalAsset,
                    fallbackIcon: "video"
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)

                comparisonButton(
                    label: L10n.string("压缩后"),
                    size: CleanupStatsFormatter.space(item.compressedSizeMB),
                    asset: compressedAsset,
                    fallbackIcon: "video.badge.checkmark"
                )
            }

            Text(String(format: L10n.string("减少 %@"), CleanupStatsFormatter.space(item.savedSizeMB)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.positive)
        }
        .padding(12)
        .photoDeleteCard()
    }

    private func comparisonButton(
        label: String,
        size: String,
        asset: PHAsset?,
        fallbackIcon: String
    ) -> some View {
        Button {
            if let asset {
                onPreview(asset)
            }
        } label: {
            VStack(spacing: 8) {
                if let asset {
                    AdvancedAssetThumbnail(
                        asset: asset,
                        photoLibraryManager: photoLibraryManager,
                        size: 82
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PhotoDeleteStyle.elevatedSurface)
                        .frame(width: 82, height: 82)
                        .overlay(
                            Image(systemName: fallbackIcon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                        )
                }

                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                    Text(size)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PhotoDeleteStyle.elevatedSurface)
            )
        }
        .buttonStyle(.plain)
        .disabled(asset == nil)
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
    @State private var isExpanded = false

    private var summaryText: String {
        let savedSizeMB = sessions.reduce(0) { $0 + $1.savedSizeMB }
        return String(
            format: L10n.string("最近压缩记录 · %lld 次 · 已减少 %@"),
            Int64(sessions.count),
            CleanupStatsFormatter.space(savedSizeMB)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.accent)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("最近压缩记录"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.primaryText)

                        Text(summaryText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? Text(L10n.string("已展开")) : Text(L10n.string("已折叠")))

            if isExpanded {
                Divider()
                    .background(PhotoDeleteStyle.hairline)

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
                .transition(.opacity.combined(with: .move(edge: .top)))
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
                    label: L10n.string("压缩后"),
                    title: title(for: compressedAsset, fallback: L10n.string("压缩后视频可能已删除")),
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
    let estimateText: String
    let processedCount: Int
    let isCompressing: Bool
    let onCompress: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !isCompressing {
                Text(String(format: L10n.string("已选择 %lld 个视频 · %@"), Int64(count), estimateText))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button(role: .destructive, action: onDelete) {
                    Label(L10n.string("删除选中"), systemImage: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(PhotoDeleteStyle.destructive.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(PhotoDeleteStyle.destructive.opacity(0.24), lineWidth: 1)
                                )
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
    @State private var selectedFilter: AdvancedCleanupFilter = .all
    @State private var showBatchConfirm = false
    @State private var previewAsset: AdvancedPreviewAsset?

    private var filteredGroups: [AdvancedSimilarPhotoGroup] {
        groups.filter { matches(group: $0, filter: selectedFilter) }
    }

    private var selectedAssets: [PHAsset] {
        filteredGroups.flatMap(\.assets).filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(spacing: 14) {
                    AdvancedFilterPills(kind: .similarPhotos, selection: $selectedFilter)

                    AdvancedAssetListSummaryCard(
                        title: L10n.string("发现 \(filteredGroups.count) 组相似照片"),
                        subtitle: L10n.string("预计可减少 \(filteredGroups.reduce(0) { $0 + $1.suggestedDeleteCount }) 张，逐组确认更稳妥。"),
                        buttonTitle: selectedAssetIDs.isEmpty ? L10n.string("建议选择") : L10n.string("取消"),
                        action: toggleRecommendedSelection
                    )

                    if groups.isEmpty {
                        AdvancedEmptyState(
                            icon: AdvancedCleanupKind.similarPhotos.icon,
                            title: L10n.string("暂未发现相似照片"),
                            subtitle: L10n.string("会把拍摄时间接近的照片放在一起，方便逐组确认。")
                        )
                    } else if filteredGroups.isEmpty {
                        AdvancedEmptyState(
                            icon: AdvancedCleanupKind.similarPhotos.icon,
                            title: L10n.string("当前筛选没有内容"),
                            subtitle: L10n.string("可以切换到全部，或稍后再回来查看。")
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredGroups) { group in
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
            syncSelectionWithPendingDeleteCandidates()
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
        .onChange(of: selectedFilter) { _ in
            pruneSelectionToFilteredGroups()
        }
    }

    private func toggleRecommendedSelection() {
        HapticManager.impact(.light)
        if selectedAssetIDs.isEmpty {
            selectedAssetIDs = Set(filteredGroups.flatMap { $0.assets.dropFirst().map(\.localIdentifier) })
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

    private func syncSelectionWithPendingDeleteCandidates() {
        let pendingDeleteIDs = Set(dataManager.deleteCandidates.map(\.localIdentifier))
        selectedAssetIDs = selectedAssetIDs.filter { pendingDeleteIDs.contains($0) }
    }

    private func reloadGroups() {
        groups = dataManager.makeSimilarPhotoGroups(maxGroups: 80)
        pruneSelectionToFilteredGroups()
    }

    private func matches(group: AdvancedSimilarPhotoGroup, filter: AdvancedCleanupFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .recommended:
            return group.suggestedDeleteCount > 0
        case .burst:
            return isLikelyBurst(group)
        case .month:
            guard let representativeDate = group.representativeDate else { return false }
            return Calendar.current.isDate(representativeDate, equalTo: Date(), toGranularity: .month)
        case .videos, .photos, .large, .long:
            return true
        }
    }

    private func isLikelyBurst(_ group: AdvancedSimilarPhotoGroup) -> Bool {
        guard group.assets.count >= 3 else { return false }
        let dates = group.assets.compactMap(\.creationDate).sorted()
        guard let first = dates.first, let last = dates.last else { return false }
        return last.timeIntervalSince(first) <= 20
    }

    private func pruneSelectionToFilteredGroups() {
        let visibleIDs = Set(filteredGroups.flatMap { $0.assets.map(\.localIdentifier) })
        selectedAssetIDs = selectedAssetIDs.filter { visibleIDs.contains($0) }
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

            AdvancedBulkSelectionButton(title: buttonTitle, action: action)
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct AdvancedBulkSelectionButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryButtonText)
                .lineLimit(1)
                .padding(.horizontal, 15)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(PhotoDeleteStyle.accent)
                )
                .opacity(isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct AdvancedAssetRow: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let estimatedSizeMB: Double
    var sizeText: String?
    var sizeSystemImage: String? = nil
    var sizeTint: Color = PhotoDeleteStyle.positive
    var statusText: String? = nil
    var statusSystemImage: String? = nil
    var statusTint: Color = PhotoDeleteStyle.secondaryText
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

                        if let statusText {
                            HStack(spacing: 6) {
                                AdvancedAssetStatusBadge(
                                    text: statusText,
                                    systemImage: statusSystemImage,
                                    tint: statusTint
                                )

                                Text(metadata)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                            }
                        } else {
                            Text(metadata)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 8) {
                        AdvancedAssetSizeBadge(
                            text: sizeText ?? CleanupStatsFormatter.space(estimatedSizeMB),
                            systemImage: sizeSystemImage,
                            tint: sizeTint
                        )

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

private struct AdvancedAssetStatusBadge: View {
    let text: String
    let systemImage: String?
    let tint: Color

    var body: some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}

private struct AdvancedAssetSizeBadge: View {
    let text: String
    let systemImage: String?
    let tint: Color

    var body: some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
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

private enum AdvancedCleanupFilter: String, Hashable, Identifiable {
    case all
    case recommended
    case burst
    case videos
    case photos
    case large
    case long
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return L10n.string("全部")
        case .recommended:
            return L10n.string("推荐")
        case .burst:
            return L10n.string("连拍")
        case .videos:
            return L10n.string("视频")
        case .photos:
            return L10n.string("图片")
        case .large:
            return L10n.string("大文件")
        case .long:
            return L10n.string("较长")
        case .month:
            return L10n.string("本月")
        }
    }

    static func options(for kind: AdvancedCleanupKind) -> [AdvancedCleanupFilter] {
        switch kind {
        case .similarPhotos:
            return [.all, .recommended, .burst, .month]
        case .largeFiles:
            return [.all, .videos, .photos, .month]
        case .imageCompression:
            return [.all, .large, .month]
        case .videoCompression:
            return [.all, .large, .long, .month]
        case .videos:
            return [.all, .large, .long, .month]
        }
    }
}

private struct AdvancedFilterPills: View {
    let kind: AdvancedCleanupKind
    @Binding var selection: AdvancedCleanupFilter

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(filters) { filter in
                    Button {
                        selection = filter
                        HapticManager.impact(.light)
                    } label: {
                        Text(filter.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selection == filter ? PhotoDeleteStyle.primaryButtonText : PhotoDeleteStyle.secondaryText)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selection == filter ? PhotoDeleteStyle.accent : PhotoDeleteStyle.surface)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(selection == filter ? PhotoDeleteStyle.accent.opacity(0.65) : PhotoDeleteStyle.hairline, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var filters: [AdvancedCleanupFilter] {
        AdvancedCleanupFilter.options(for: kind)
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
    @Environment(\.photoDeleteTheme) private var theme

    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    theme.primaryAccentSoftStroke.opacity(0.9),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    theme.progressTint,
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
            parts.append(AppDateFormatter.string(from: creationDate, template: "yMd"))
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
            return AppDateFormatter.string(from: summary.intervalStart, template: "yMMMd")
        case .week:
            return weekTitle(for: summary.intervalStart)
        case .month:
            return AppDateFormatter.string(from: summary.intervalStart, template: "yMMM")
        case .year:
            return AppDateFormatter.string(from: summary.intervalStart, template: "y")
        }
    }

    static func compactTitle(for summary: PhotoPeriodSummary) -> String {
        switch summary.scope {
        case .day:
            return AppDateFormatter.string(from: summary.intervalStart, template: "MMMd")
        case .week:
            return weekCompact(for: summary.intervalStart)
        case .month:
            return AppDateFormatter.string(from: summary.intervalStart, template: "MMM")
        case .year:
            return AppDateFormatter.string(from: summary.intervalStart, template: "y")
        }
    }

    static func chipTitle(for summary: PhotoPeriodSummary) -> String {
        switch summary.scope {
        case .day:
            return AppDateFormatter.string(from: summary.intervalStart, template: "Md")
        case .week:
            return weekChip(for: summary.intervalStart)
        case .month:
            return AppDateFormatter.string(from: summary.intervalStart, template: "MMM")
        case .year:
            return AppDateFormatter.string(from: summary.intervalStart, template: "y")
        }
    }

    static func subtitle(for summary: PhotoPeriodSummary) -> String {
        switch summary.scope {
        case .day:
            return L10n.string("当天")
        case .week:
            let start = AppDateFormatter.string(from: summary.intervalStart, template: "Md")
            let endDate = Calendar.current.date(byAdding: .day, value: -1, to: summary.intervalEnd) ?? summary.intervalEnd
            let end = AppDateFormatter.string(from: endDate, template: "Md")
            return "\(start) - \(end)"
        case .month:
            return L10n.string("本月照片清理进度")
        case .year:
            return L10n.string("全年照片清理进度")
        }
    }

    private static func weekTitle(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(
            format: L10n.string("%lld 年第 %lld 周"),
            Int64(components.yearForWeekOfYear ?? 0),
            Int64(components.weekOfYear ?? 0)
        )
    }

    private static func weekCompact(for date: Date) -> String {
        let week = Calendar.current.component(.weekOfYear, from: date)
        return String(format: L10n.string("第 %lld 周"), Int64(week))
    }

    private static func weekChip(for date: Date) -> String {
        let week = Calendar.current.component(.weekOfYear, from: date)
        return String(format: L10n.string("周 %lld"), Int64(week))
    }
}

#Preview {
    AdvancedView()
        .environmentObject(DataManager())
        .environmentObject(PurchaseManager())
}
