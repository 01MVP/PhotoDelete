//
//  AdvancedView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/11/26.
//

import SwiftUI
import Photos
import Combine
import StoreKit
import UIKit

struct AdvancedView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppConstants.appLanguageKey) private var appLanguageValue = AppLanguage.system.rawValue
    @State private var selectedScope: AdvancedTimeScope = .month
    @State private var selectedPeriodDate = Date()
    @State private var dashboardSnapshot = AdvancedLibrarySnapshot.demo(referenceDate: Date())
    @State private var activePeriodRoute: AdvancedPeriodRoute?
    @State private var advancedRefreshWorkItem: DispatchWorkItem?
    @State private var lastDashboardRefreshKey: AdvancedDashboardRefreshKey?
    @State private var showingSupporterBenefits = false
    @State private var showingOfferCodeRedemption = false
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
        case .verifying:
            return L10n.string("正在检查购买状态...")
        case .unknown, .verified, .cachedOffline, .locked:
            return nil
        }
    }

    var body: some View {
        let _ = appLanguageValue

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
                    onRedeemCode: { showingOfferCodeRedemption = true },
                    onShowBenefits: { showingSupporterBenefits = true }
                )
            }
        }
        .sheet(isPresented: $showingSupporterBenefits) {
            SupporterBenefitsSheet()
        }
        .offerCodeRedemption(isPresented: $showingOfferCodeRedemption) { result in
            purchaseManager.handleOfferCodeRedemptionCompletion(result)
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
                dataManager.isRestoringLibrarySnapshot ||
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
                    Text(L10n.string("按时间整理"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(L10n.string("按日、周、月、年继续整理。"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }

                Spacer()
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

                if summaries.count > displayedAdvancedPeriodSummaries.count {
                    Button(action: showMoreAdvancedPeriods) {
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

                if isLocked {
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

            if dataManager.imageCompressionJob.isCompressing {
                AdvancedVideoCompressionProgressCard(
                    processedCount: dataManager.imageCompressionJob.processedCount,
                    totalCount: dataManager.imageCompressionJob.totalCount,
                    currentProgress: dataManager.imageCompressionJob.currentProgress,
                    message: dataManager.imageCompressionJob.message
                )
            }

            if dataManager.videoCompressionJob.isCompressing {
                AdvancedVideoCompressionProgressCard(
                    processedCount: dataManager.videoCompressionJob.processedCount,
                    totalCount: dataManager.videoCompressionJob.totalCount,
                    currentProgress: dataManager.videoCompressionJob.currentProgress,
                    message: dataManager.videoCompressionJob.message
                )
            }

            let visibleQueues = queues.filter { AdvancedCleanupKind.visibleCases.contains($0.kind) }

            if visibleQueues.isEmpty && dataManager.isLoadingAdvancedCleanupQueues {
                AdvancedEmptyState(
                    icon: "sparkles",
                    title: L10n.string("正在准备清理入口"),
                    subtitle: L10n.string("稍后会显示可处理的照片和视频。")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleQueues.enumerated()), id: \.element.id) { index, queue in
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

                        if index != visibleQueues.count - 1 {
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
            if AppConstants.isImageCompressionVisible {
                AdvancedImageCompressionView()
                    .environmentObject(dataManager)
            } else {
                EmptyView()
            }
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

    private func showMoreAdvancedPeriods() {
        withAnimation(.easeInOut(duration: 0.18)) {
            visibleAdvancedPeriodLimit = VisibleListPagination.advancedLimit(
                totalCount: visiblePeriodSummaries.count,
                currentLimit: visibleAdvancedPeriodLimit,
                step: 20
            )
        }
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
                        Text(String(format: L10n.string("%@清理进度"), AdvancedPeriodFormatter.compactTitle(for: summary)))
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

                    Text(String(
                        format: L10n.string("%lld 项 · %lld%%"),
                        Int64(summary.assetCount),
                        Int64(summary.progress * 100)
                    ))
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
            return String(
                format: L10n.string("%lld 项 · %@"),
                Int64(queue.assetCount),
                queue.formattedSpace
            )
        case .imageCompression, .videoCompression, .videos:
            return String(format: L10n.string("%lld 项"), Int64(queue.assetCount))
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
    let onRedeemCode: () -> Void
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

            SupporterPurchaseAuxiliaryActionsRow(
                isLoading: isLoading,
                onRestore: onRestore,
                onRedeemCode: onRedeemCode
            )

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

        return L10n.string("一次性解锁完整时间列表、大文件清理、视频压缩、相似照片清理和主题切换。")
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

                Text(String(
                    format: L10n.string("%lld 项 · 已整理 %lld%% · %@"),
                    Int64(summary.assetCount),
                    Int64(summary.progress * 100),
                    summary.formattedEstimatedSize
                ))
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

private struct AdvancedFilteredAssetSnapshot {
    let assets: [PHAsset]
    let visibleAssets: [PHAsset]
    let videoAssets: [PHAsset]
    let totalSizeMB: Double
    let loadedReliableVideoSizeCount: Int
    let iCloudVideoCount: Int
    let hasMoreAssets: Bool

    var hasUnresolvedVideoSizes: Bool {
        !videoAssets.isEmpty && loadedReliableVideoSizeCount < videoAssets.count
    }
}

private struct AdvancedAssetListView: View {
    @EnvironmentObject var dataManager: DataManager
    let mode: AdvancedAssetListMode

    @State private var assets: [PHAsset] = []
    @State private var orderedAssets: [PHAsset] = []
    @State private var videoSizeEstimatesByAssetID: [String: VideoFileSizeEstimate] = [:]
    @State private var photoSizeEstimatesByAssetID: [String: AssetFileSizeEstimate] = [:]
    @State private var selectedAssetIDs: Set<String> = []
    @State private var selectedFilter: AdvancedCleanupFilter = .all
    @State private var showingICloudVideoInfo = false
    @State private var showBatchConfirm = false
    @State private var previewAsset: AdvancedPreviewAsset?
    @State private var sizeLoadingTask: Task<Void, Never>?
    @State private var visibleAssetLimit = 40
    @State private var isLoadingAssets = false
    @State private var isLoadingFileSizes = false
    @State private var assetLoadGeneration = 0
    @State private var sizeLoadGeneration = 0

    private let assetLimitStep = 40
    private let fileSizeUpdateBatchSize = 8

    private var selectedAssets: [PHAsset] {
        makeFilteredAssetSnapshot().assets.filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var prefersSizeFirstOrder: Bool {
        switch mode {
        case .cleanup(.largeFiles), .cleanup(.videos), .cleanup(.videoCompression):
            return true
        case .cleanup(.similarPhotos), .cleanup(.imageCompression):
            return false
        }
    }

    private var shouldLoadPhotoFileSizes: Bool {
        if case .cleanup(.largeFiles) = mode { return true }
        return false
    }

    private var fileSizeLoadTargets: [PHAsset] {
        makeFilteredAssetSnapshot().visibleAssets.filter { asset in
            asset.mediaType == .video || (shouldLoadPhotoFileSizes && asset.mediaType == .image)
        }
    }

    private func makeFilteredAssetSnapshot() -> AdvancedFilteredAssetSnapshot {
        let filteredAssets = filteredAssetCandidates()
        let visibleAssets = VisibleListPagination.visibleItems(filteredAssets, limit: visibleAssetLimit)
        let videoAssets = filteredAssets.filter { $0.mediaType == .video }
        let totalSizeMB = filteredAssets.reduce(0) { partial, asset in
            partial + displaySizeMB(for: asset)
        }
        let loadedReliableVideoSizeCount = videoAssets.reduce(0) { partial, asset in
            reliableVideoSizeMB(for: asset) == nil ? partial : partial + 1
        }
        let iCloudVideoCount = videoAssets.reduce(0) { partial, asset in
            videoSizeEstimatesByAssetID[asset.localIdentifier]?.source == .iCloud ? partial + 1 : partial
        }

        return AdvancedFilteredAssetSnapshot(
            assets: filteredAssets,
            visibleAssets: visibleAssets,
            videoAssets: videoAssets,
            totalSizeMB: totalSizeMB,
            loadedReliableVideoSizeCount: loadedReliableVideoSizeCount,
            iCloudVideoCount: iCloudVideoCount,
            hasMoreAssets: VisibleListPagination.hasMore(totalCount: filteredAssets.count, limit: visibleAssetLimit)
        )
    }

    private func filteredAssetCandidates() -> [PHAsset] {
        guard selectedFilter != .all else { return orderedAssets }
        return orderedAssets.filter { matches(asset: $0, filter: selectedFilter) }
    }

    var body: some View {
        let snapshot = makeFilteredAssetSnapshot()

        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(spacing: 14) {
                    if case .cleanup(let kind) = mode,
                       AdvancedCleanupFilter.options(for: kind).count > 1 {
                        AdvancedFilterPills(kind: kind, selection: $selectedFilter)
                    }

                    AdvancedAssetListSummaryCard(
                        title: summaryTitle(for: snapshot),
                        subtitle: summarySubtitle(for: snapshot),
                        buttonTitle: isAllFilteredSelected(in: snapshot) ? L10n.string("取消") : L10n.string("全选"),
                        action: toggleBulkSelection
                    )

                    if !isLoadingAssets, !isLoadingFileSizes, snapshot.iCloudVideoCount > 0 {
                        AdvancedVideoCompressionICloudInfoCard(
                            count: snapshot.iCloudVideoCount,
                            subtitle: L10n.string("预览或处理时会下载原片。"),
                            action: showICloudVideoInfo
                        )
                    }

                    if isLoadingAssets && assets.isEmpty {
                        AdvancedLoadingState(
                            title: L10n.string("正在准备清理入口"),
                            subtitle: L10n.string("稍后会显示可处理的照片和视频。")
                        )
                    } else if assets.isEmpty {
                        AdvancedEmptyState(
                            icon: mode.icon,
                            title: L10n.string("没有可整理的内容"),
                            subtitle: L10n.string("当前照片库里暂时没有符合这个入口的项目。")
                        )
                    } else if snapshot.assets.isEmpty {
                        AdvancedEmptyState(
                            icon: mode.icon,
                            title: L10n.string("当前筛选没有内容"),
                            subtitle: L10n.string("可以切换到全部，或稍后再回来查看。")
                        )
                    } else {
                        LazyVStack(spacing: 9) {
                            ForEach(snapshot.visibleAssets, id: \.localIdentifier) { asset in
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
                                .onAppear {
                                    showMoreAssetsIfNeeded(currentAsset: asset)
                                }
                            }
                        }

                        if snapshot.hasMoreAssets {
                            Text(L10n.string("继续向下滚动加载更多"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
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
                photoLibraryManager: dataManager.photoLibraryManager,
                assets: item.assets,
                selectedAssetIDs: $selectedAssetIDs
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
            visibleAssetLimit = 40
            pruneSelectionToFilteredAssets()
            loadFileSizesForCurrentScope()
        }
        .onDisappear {
            sizeLoadingTask?.cancel()
        }
    }

    private func summaryTitle(for snapshot: AdvancedFilteredAssetSnapshot) -> String {
        switch mode {
        case .cleanup(.largeFiles):
            return String(format: L10n.string("共 %lld 个大文件"), Int64(snapshot.assets.count))
        case .cleanup(.imageCompression):
            return String(format: L10n.string("共 %lld 张可压缩图片"), Int64(snapshot.assets.count))
        case .cleanup(.videoCompression):
            return String(format: L10n.string("共 %lld 个可压缩视频"), Int64(snapshot.assets.count))
        case .cleanup(.videos):
            return String(format: L10n.string("共 %lld 个视频"), Int64(snapshot.assets.count))
        case .cleanup(.similarPhotos):
            return String(format: L10n.string("共 %lld 张相似照片"), Int64(snapshot.assets.count))
        }
    }

    private func summarySubtitle(for snapshot: AdvancedFilteredAssetSnapshot) -> String {
        switch mode {
        case .cleanup(.largeFiles):
            if snapshot.hasUnresolvedVideoSizes {
                return String(format: L10n.string("部分视频大小会在处理时确认，已知约 %@。"), CleanupStatsFormatter.space(snapshot.totalSizeMB))
            }
            return String(format: L10n.string("按占用空间从大到小排序，合计约 %@。"), CleanupStatsFormatter.space(snapshot.totalSizeMB))
        case .cleanup(.imageCompression):
            return String(format: L10n.string("选择要压缩的图片，合计约 %@。"), CleanupStatsFormatter.space(snapshot.totalSizeMB))
        case .cleanup(.videoCompression):
            return String(format: L10n.string("选择要压缩的视频，合计约 %@。"), CleanupStatsFormatter.space(snapshot.totalSizeMB))
        case .cleanup(.videos):
            if snapshot.hasUnresolvedVideoSizes {
                return String(
                    format: L10n.string("已读取 %lld/%lld 个视频大小，已知约 %@。"),
                    Int64(snapshot.loadedReliableVideoSizeCount),
                    Int64(snapshot.videoAssets.count),
                    CleanupStatsFormatter.space(snapshot.totalSizeMB)
                )
            }
            return String(format: L10n.string("按视频占用优先处理，合计约 %@。"), CleanupStatsFormatter.space(snapshot.totalSizeMB))
        case .cleanup(.similarPhotos):
            return String(format: L10n.string("建议优先处理相似组，合计约 %@。"), CleanupStatsFormatter.space(snapshot.totalSizeMB))
        }
    }

    private func reloadAssets() {
        assetLoadGeneration += 1
        let generation = assetLoadGeneration
        isLoadingAssets = true
        switch mode {
        case .cleanup(let kind):
            dataManager.loadPhotosForAdvancedCleanup(kind) { loadedAssets in
                guard generation == assetLoadGeneration else { return }
                applyLoadedAssets(loadedAssets)
            }
        }
    }

    private func applyLoadedAssets(_ loadedAssets: [PHAsset]) {
        assets = loadedAssets
        visibleAssetLimit = 40
        pruneVideoSizeEstimates(for: loadedAssets)
        prunePhotoSizeEstimates(for: loadedAssets)
        seedCachedVideoSizeEstimates(for: loadedAssets)
        refreshOrderedAssets()
        pruneSelectionToFilteredAssets()
        isLoadingAssets = false
        loadFileSizesForCurrentScope()
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
            if asset.mediaType == .video {
                guard let estimate = videoSizeEstimatesByAssetID[asset.localIdentifier] else { return true }
                guard estimate.isReliable else { return true }
                return estimate.sizeMB >= 80
            }
            return (reliablePhotoSizeMB(for: asset) ?? dataManager.estimatedSizeMB(for: asset)) >= 18
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
        return reliablePhotoSizeMB(for: asset) ?? dataManager.estimatedSizeMB(for: asset)
    }

    private func displaySizeMB(for asset: PHAsset) -> Double {
        if asset.mediaType == .video {
            return reliableVideoSizeMB(for: asset) ?? dataManager.estimatedSizeMB(for: asset)
        }
        return reliablePhotoSizeMB(for: asset) ?? dataManager.estimatedSizeMB(for: asset)
    }

    private func displaySizeText(for asset: PHAsset) -> String? {
        let estimate: AssetFileSizeEstimate?
        if asset.mediaType == .video {
            estimate = videoSizeEstimatesByAssetID[asset.localIdentifier]
        } else if shouldLoadPhotoFileSizes {
            estimate = photoSizeEstimatesByAssetID[asset.localIdentifier]
        } else {
            return nil
        }
        guard let estimate else {
            return L10n.string("计算中")
        }
        switch estimate.source {
        case .assetResource:
            return CleanupStatsFormatter.fileSize(estimate.sizeMB)
        case .iCloud:
            return L10n.string("待下载")
        case .unavailable:
            return L10n.string("待确认")
        }
    }

    private func sizeFirstOrder(_ lhs: PHAsset, _ rhs: PHAsset) -> Bool {
        let lhsRank = sizeSortRank(for: lhs)
        let rhsRank = sizeSortRank(for: rhs)

        if lhsRank.priority != rhsRank.priority {
            return lhsRank.priority < rhsRank.priority
        }

        if lhsRank.sizeMB != rhsRank.sizeMB {
            return lhsRank.sizeMB > rhsRank.sizeMB
        }

        let lhsDate = lhs.creationDate ?? .distantPast
        let rhsDate = rhs.creationDate ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return lhs.localIdentifier < rhs.localIdentifier
    }

    private func sizeSortRank(for asset: PHAsset) -> (priority: Int, sizeMB: Double) {
        if asset.mediaType == .video {
            guard let estimate = videoSizeEstimatesByAssetID[asset.localIdentifier] else {
                return (priority: 1, sizeMB: dataManager.estimatedSizeMB(for: asset))
            }
            guard estimate.isReliable else {
                return (priority: 1, sizeMB: dataManager.estimatedSizeMB(for: asset))
            }
            return (priority: 0, sizeMB: estimate.sizeMB)
        }

        if let reliableSize = reliablePhotoSizeMB(for: asset) {
            return (priority: 0, sizeMB: reliableSize)
        }
        return (priority: 1, sizeMB: dataManager.estimatedSizeMB(for: asset))
    }

    private func sizeStatusSystemImage(for asset: PHAsset) -> String? {
        guard fileSizeEstimate(for: asset)?.source == .iCloud else {
            return nil
        }
        return "icloud.and.arrow.down"
    }

    private func sizeStatusTint(for asset: PHAsset) -> Color {
        guard fileSizeEstimate(for: asset)?.source == .iCloud else {
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

    private func reliablePhotoSizeMB(for asset: PHAsset) -> Double? {
        guard let estimate = photoSizeEstimatesByAssetID[asset.localIdentifier],
              estimate.isReliable else {
            return nil
        }
        return estimate.sizeMB
    }

    private func fileSizeEstimate(for asset: PHAsset) -> AssetFileSizeEstimate? {
        if asset.mediaType == .video {
            return videoSizeEstimatesByAssetID[asset.localIdentifier]
        }
        return photoSizeEstimatesByAssetID[asset.localIdentifier]
    }

    private func pruneVideoSizeEstimates(for loadedAssets: [PHAsset]) {
        let loadedIDs = Set(loadedAssets.map(\.localIdentifier))
        videoSizeEstimatesByAssetID = videoSizeEstimatesByAssetID.filter { loadedIDs.contains($0.key) }
    }

    private func prunePhotoSizeEstimates(for loadedAssets: [PHAsset]) {
        let loadedIDs = Set(loadedAssets.map(\.localIdentifier))
        photoSizeEstimatesByAssetID = photoSizeEstimatesByAssetID.filter { loadedIDs.contains($0.key) }
    }

    private func seedCachedVideoSizeEstimates(for loadedAssets: [PHAsset]) {
        for asset in loadedAssets where asset.mediaType == .video {
            guard let cached = dataManager.cachedVideoFileSizeEstimate(for: asset) else { continue }
            videoSizeEstimatesByAssetID[asset.localIdentifier] = cached
        }
    }

    private func applyVideoSizeEstimates(
        _ estimatesByAssetID: [String: VideoFileSizeEstimate],
        generation: Int
    ) {
        guard generation == sizeLoadGeneration, !estimatesByAssetID.isEmpty else { return }
        for (assetID, estimate) in estimatesByAssetID {
            dataManager.cacheVideoFileSizeEstimate(estimate, forAssetIdentifier: assetID)
            videoSizeEstimatesByAssetID[assetID] = estimate
        }
        refreshOrderedAssets()
    }

    private func applyPhotoSizeEstimates(
        _ estimatesByAssetID: [String: AssetFileSizeEstimate],
        generation: Int
    ) {
        guard generation == sizeLoadGeneration, !estimatesByAssetID.isEmpty else { return }
        for (assetID, estimate) in estimatesByAssetID {
            photoSizeEstimatesByAssetID[assetID] = estimate
        }
        refreshOrderedAssets()
    }

    private func refreshOrderedAssets() {
        guard prefersSizeFirstOrder else {
            orderedAssets = assets
            return
        }
        orderedAssets = assets.sorted(by: sizeFirstOrder)
    }

    private func loadFileSizes(for loadedAssets: [PHAsset]) {
        sizeLoadingTask?.cancel()
        sizeLoadGeneration += 1
        let generation = sizeLoadGeneration
        let videos = loadedAssets.filter { $0.mediaType == .video }
        let photos = loadedAssets.filter { $0.mediaType == .image }
        guard !videos.isEmpty || !photos.isEmpty else {
            isLoadingFileSizes = false
            return
        }

        isLoadingFileSizes = true
        sizeLoadingTask = Task {
            var pendingVideoEstimates: [String: VideoFileSizeEstimate] = [:]
            for asset in videos {
                if Task.isCancelled { break }
                let alreadyLoaded = await MainActor.run {
                    guard generation == sizeLoadGeneration else { return true }
                    if let cached = dataManager.cachedVideoFileSizeEstimate(for: asset) {
                        videoSizeEstimatesByAssetID[asset.localIdentifier] = cached
                        return true
                    }
                    return videoSizeEstimatesByAssetID[asset.localIdentifier] != nil
                }
                if alreadyLoaded { continue }

                do {
                    let estimate = try await dataManager.photoLibraryManager.videoFileSizeEstimate(for: asset)
                    pendingVideoEstimates[asset.localIdentifier] = estimate
                    if pendingVideoEstimates.count >= fileSizeUpdateBatchSize {
                        let estimatesToApply = pendingVideoEstimates
                        pendingVideoEstimates.removeAll()
                        await MainActor.run {
                            applyVideoSizeEstimates(estimatesToApply, generation: generation)
                        }
                    }
                } catch {
                    continue
                }
            }
            if !pendingVideoEstimates.isEmpty {
                let estimatesToApply = pendingVideoEstimates
                await MainActor.run {
                    applyVideoSizeEstimates(estimatesToApply, generation: generation)
                }
            }

            var pendingPhotoEstimates: [String: AssetFileSizeEstimate] = [:]
            for asset in photos {
                if Task.isCancelled { break }
                let alreadyLoaded = await MainActor.run {
                    guard generation == sizeLoadGeneration else { return true }
                    return photoSizeEstimatesByAssetID[asset.localIdentifier] != nil
                }
                if alreadyLoaded { continue }

                do {
                    let estimate = try await dataManager.photoLibraryManager.photoFileSizeEstimate(for: asset)
                    pendingPhotoEstimates[asset.localIdentifier] = estimate
                    if pendingPhotoEstimates.count >= fileSizeUpdateBatchSize {
                        let estimatesToApply = pendingPhotoEstimates
                        pendingPhotoEstimates.removeAll()
                        await MainActor.run {
                            applyPhotoSizeEstimates(estimatesToApply, generation: generation)
                        }
                    }
                } catch {
                    continue
                }
            }
            if !pendingPhotoEstimates.isEmpty {
                let estimatesToApply = pendingPhotoEstimates
                await MainActor.run {
                    applyPhotoSizeEstimates(estimatesToApply, generation: generation)
                }
            }
            await MainActor.run {
                guard generation == sizeLoadGeneration else { return }
                isLoadingFileSizes = false
            }
        }
    }

    private func showMoreAssets() {
        let snapshot = makeFilteredAssetSnapshot()
        withAnimation(.easeInOut(duration: 0.18)) {
            visibleAssetLimit = VisibleListPagination.advancedLimit(
                totalCount: snapshot.assets.count,
                currentLimit: visibleAssetLimit,
                step: assetLimitStep
            )
        }
        loadFileSizesForCurrentScope()
    }

    private func showMoreAssetsIfNeeded(currentAsset asset: PHAsset) {
        let snapshot = makeFilteredAssetSnapshot()
        guard snapshot.hasMoreAssets,
              let index = snapshot.visibleAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }),
              index >= max(snapshot.visibleAssets.count - 6, 0) else {
            return
        }
        showMoreAssets()
    }

    private func loadFileSizesForCurrentScope() {
        loadFileSizes(for: fileSizeLoadTargets)
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
        let snapshot = makeFilteredAssetSnapshot()
        let visibleIDs = Set(snapshot.assets.map(\.localIdentifier))
        if isAllFilteredSelected(in: snapshot) {
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
        let visibleIDs = Set(makeFilteredAssetSnapshot().assets.map(\.localIdentifier))
        selectedAssetIDs = selectedAssetIDs.filter { visibleIDs.contains($0) }
    }

    private func isAllFilteredSelected(in snapshot: AdvancedFilteredAssetSnapshot) -> Bool {
        !snapshot.assets.isEmpty &&
            snapshot.assets.allSatisfy { selectedAssetIDs.contains($0.localIdentifier) }
    }
}

private enum AdvancedImageCompressionTab: String, CaseIterable, Identifiable {
    case pending
    case processed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return L10n.string("未压缩")
        case .processed: return L10n.string("已压缩")
        }
    }
}

private struct AdvancedImageCompressionView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var assets: [PHAsset] = []
    @State private var selectedAssetIDs: Set<String> = []
    @State private var compressionPlan: ImageCompressionPlan = .default
    @State private var showingCompressionComparison = false
    @State private var dismissCompressionResultAfterBatch = false
    @State private var previewAsset: AdvancedPreviewAsset?
    @State private var showBatchConfirm = false
    @State private var compressionOptionsContext: AdvancedImageCompressionOptionsContext?
    @State private var visibleImageLimit = 24
    @State private var selectedTab: AdvancedImageCompressionTab = .pending
    @State private var isLoadingAssets = false
    @State private var assetLoadGeneration = 0

    private let imageLimitStep = 24

    private var compressionJob: AdvancedImageCompressionJobState {
        dataManager.imageCompressionJob
    }

    private var isCompressing: Bool {
        compressionJob.isCompressing
    }

    private var selectedAssets: [PHAsset] {
        compressibleAssets.filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var compressibleAssets: [PHAsset] {
        assets
    }

    private var visibleCompressibleAssets: [PHAsset] {
        VisibleListPagination.visibleItems(compressibleAssets, limit: visibleImageLimit)
    }

    private var hasMoreCompressibleAssets: Bool {
        VisibleListPagination.hasMore(totalCount: compressibleAssets.count, limit: visibleImageLimit)
    }

    private var isAllSelected: Bool {
        !visibleCompressibleAssets.isEmpty && visibleCompressibleAssets.allSatisfy { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var imageListSizeSummary: String {
        guard !compressibleAssets.isEmpty else { return L10n.string("没有需要压缩的图片") }
        let visibleSize = visibleCompressibleAssets.reduce(0) { $0 + dataManager.estimatedSizeMB(for: $1) }
        return String(
            format: L10n.string("已显示 %lld/%lld 张图片 · 当前约 %@"),
            Int64(visibleCompressibleAssets.count),
            Int64(compressibleAssets.count),
            CleanupStatsFormatter.space(visibleSize)
        )
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
                    imageCompressionTabPicker

                    if isCompressing {
                        AdvancedVideoCompressionProgressCard(
                            processedCount: compressionJob.processedCount,
                            totalCount: compressionJob.totalCount,
                            currentProgress: compressionJob.currentProgress,
                            message: compressionJob.message
                        )
                    }

                    if let compressionResult = compressionJob.result {
                        AdvancedImageCompressionResultCard(
                            result: compressionResult,
                            onCompare: showCompressionComparison,
                            onDeleteOriginals: queueOriginalImagesForDeletion,
                            onKeepOriginals: keepOriginalImages
                        )
                    }

                    if let compressionErrorMessage = compressionJob.errorMessage {
                        AdvancedVideoCompressionMessageCard(
                            icon: "exclamationmark.triangle.fill",
                            message: compressionErrorMessage,
                            tint: PhotoDeleteStyle.warning
                        )
                    }

                    switch selectedTab {
                    case .pending:
                        pendingImageCompressionContent
                    case .processed:
                        processedImageCompressionContent
                    }

                    Spacer()
                        .frame(height: 24)
                }
                .padding(PhotoDeleteStyle.screenHorizontalPadding)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedTab == .pending, !selectedAssetIDs.isEmpty {
                AdvancedImageCompressionActionBar(
                    count: selectedAssetIDs.count,
                    estimateText: selectedCompressionEstimateText,
                    processedCount: compressionJob.processedCount,
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
                dataManager.clearImageCompressionResult()
                dismissCompressionResultAfterBatch = false
            }
        }) {
            BatchConfirmView { deletedAssetIDs in
                dataManager.markImageCompressionOriginalsDeleted(assetIdentifiers: deletedAssetIDs)
            }
                .environmentObject(dataManager)
        }
        .sheet(item: $previewAsset) { item in
            AdvancedAssetPreviewView(
                asset: item.asset,
                photoLibraryManager: dataManager.photoLibraryManager,
                assets: item.assets,
                selectedAssetIDs: $selectedAssetIDs
            )
        }
        .sheet(isPresented: $showingCompressionComparison) {
            if let compressionResult = compressionJob.result {
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
        .onChange(of: dataManager.imageCompressionHistoryRevision) { _ in
            selectedAssetIDs.removeAll()
            reloadAssets()
            showingCompressionComparison = false
        }
    }

    private var imageCompressionTabPicker: some View {
        Picker(L10n.string("图片压缩"), selection: $selectedTab) {
            ForEach(AdvancedImageCompressionTab.allCases) { tab in
                Text(tab.title)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(L10n.string("图片压缩"))
    }

    @ViewBuilder
    private var pendingImageCompressionContent: some View {
        if isLoadingAssets && assets.isEmpty {
            AdvancedLoadingState(
                title: L10n.string("正在准备清理入口"),
                subtitle: L10n.string("稍后会显示可处理的照片和视频。")
            )
        } else if assets.isEmpty {
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
                    ForEach(visibleCompressibleAssets, id: \.localIdentifier) { asset in
                        AdvancedAssetRow(
                            asset: asset,
                            photoLibraryManager: dataManager.photoLibraryManager,
                            estimatedSizeMB: dataManager.estimatedSizeMB(for: asset),
                            sizeText: CleanupStatsFormatter.space(dataManager.estimatedSizeMB(for: asset)),
                            isSelected: selectedAssetIDs.contains(asset.localIdentifier),
                            onToggleSelection: { toggleSelection(asset) },
                            onPreview: { previewAsset = AdvancedPreviewAsset(asset: asset) }
                        )
                        .onAppear {
                            showMoreCompressibleImagesIfNeeded(currentAsset: asset)
                        }
                    }
                }

                if hasMoreCompressibleAssets {
                    Text(L10n.string("继续向下滚动加载更多"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    @ViewBuilder
    private var processedImageCompressionContent: some View {
        if dataManager.imageCompressionHistoryStore.sessions.isEmpty {
            AdvancedEmptyState(
                icon: "checkmark.circle",
                title: L10n.string("还没有压缩记录"),
                subtitle: L10n.string("压缩完成的图片会留在最近压缩记录里。")
            )
        } else {
            AdvancedImageCompressionHistoryCard(
                sessions: dataManager.imageCompressionHistoryStore.sessions,
                photoLibraryManager: dataManager.photoLibraryManager,
                startsExpanded: true,
                onDeleteOriginals: queueCompressedHistoryOriginalImagesForDeletion,
                onPreview: { asset in
                    previewAsset = AdvancedPreviewAsset(asset: asset)
                }
            )
        }
    }

    private func reloadAssets() {
        assetLoadGeneration += 1
        let generation = assetLoadGeneration
        isLoadingAssets = true
        dataManager.loadPhotosForAdvancedCleanup(.imageCompression) { loadedAssets in
            guard generation == assetLoadGeneration else { return }
            applyLoadedAssets(loadedAssets)
        }
    }

    private func applyLoadedAssets(_ loadedAssets: [PHAsset]) {
        assets = loadedAssets
        visibleImageLimit = 24
        let loadedIDs = Set(loadedAssets.map(\.localIdentifier))
        selectedAssetIDs = selectedAssetIDs.filter { selectedID in
            loadedIDs.contains(selectedID)
        }
        pruneSelectionToCompressibleAssets()
        isLoadingAssets = false
    }

    private func showMoreCompressibleImages() {
        withAnimation(.easeInOut(duration: 0.18)) {
            visibleImageLimit = VisibleListPagination.advancedLimit(
                totalCount: compressibleAssets.count,
                currentLimit: visibleImageLimit,
                step: imageLimitStep
            )
        }
    }

    private func showMoreCompressibleImagesIfNeeded(currentAsset asset: PHAsset) {
        guard hasMoreCompressibleAssets,
              let index = visibleCompressibleAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }),
              index >= max(visibleCompressibleAssets.count - 6, 0) else {
            return
        }
        showMoreCompressibleImages()
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
        dataManager.setImageCompressionError(nil)
    }

    private func toggleBulkSelection() {
        guard !isCompressing else { return }
        HapticManager.impact(.light)
        let visibleIDs = Set(visibleCompressibleAssets.map(\.localIdentifier))
        if isAllSelected {
            selectedAssetIDs.subtract(visibleIDs)
        } else {
            selectedAssetIDs.formUnion(visibleIDs)
        }
        dataManager.setImageCompressionError(nil)
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
        dataManager.clearImageCompressionResult()
        dataManager.startImageCompression(images: images, plan: plan)
    }

    private func showCompressionComparison() {
        guard compressionJob.result?.createdAssetIdentifiers.isEmpty == false else {
            dataManager.setImageCompressionError(L10n.string("暂时找不到压缩后图片。"))
            return
        }
        showingCompressionComparison = true
    }

    private func queueOriginalImagesForDeletion() {
        guard let compressionResult = compressionJob.result else { return }
        guard compressionResult.hasMeaningfulSavings else {
            dataManager.setImageCompressionError(L10n.string("这次没有明显减少空间，建议先保留原图。"))
            return
        }

        let originalIDs = Set(compressionResult.items.map(\.originalAssetIdentifier))
        let fetchedOriginals = PHAsset.fetchAssets(withLocalIdentifiers: Array(originalIDs), options: nil)
        var originalAssets: [PHAsset] = []
        fetchedOriginals.enumerateObjects { asset, _, _ in
            originalAssets.append(asset)
        }
        guard !originalAssets.isEmpty else {
            dataManager.setImageCompressionError(L10n.string("暂时找不到原图。"))
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

    private func queueCompressedHistoryOriginalImagesForDeletion() {
        let originalIDs = Set(dataManager.imageCompressionHistoryStore.sessions.flatMap { session in
            session.items.map(\.originalAssetIdentifier)
        })
        let fetchedOriginals = PHAsset.fetchAssets(withLocalIdentifiers: Array(originalIDs), options: nil)
        var originalAssets: [PHAsset] = []
        fetchedOriginals.enumerateObjects { asset, _, _ in
            originalAssets.append(asset)
        }
        guard !originalAssets.isEmpty else {
            dataManager.setImageCompressionError(L10n.string("暂时找不到原图。"))
            return
        }

        for asset in originalAssets {
            _ = dataManager.markReviewed(asset)
            dataManager.addToDeleteCandidates(asset)
        }
        HapticManager.notify(.warning)
        dismissCompressionResultAfterBatch = false
        showBatchConfirm = true
    }

    private func keepOriginalImages() {
        dataManager.clearImageCompressionResult()
        showingCompressionComparison = false
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
                title: isAllSelected ? L10n.string("取消选择已显示") : L10n.string("选择已显示"),
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

                    Text(L10n.string("可减少"))
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
                        AdvancedVideoCompressionMetric(label: L10n.string("可减少"), value: result.formattedSavedSize)
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
    let onDeleteOriginals: (() -> Void)?
    let onPreview: ((PHAsset) -> Void)?
    @State private var isExpanded = false

    init(
        sessions: [ImageCompressionSession],
        photoLibraryManager: PhotoLibraryManager,
        startsExpanded: Bool = false,
        onDeleteOriginals: (() -> Void)? = nil,
        onPreview: ((PHAsset) -> Void)? = nil
    ) {
        self.sessions = sessions
        self.photoLibraryManager = photoLibraryManager
        self.onDeleteOriginals = onDeleteOriginals
        self.onPreview = onPreview
        _isExpanded = State(initialValue: startsExpanded)
    }

    private var summaryText: String {
        let savedSizeMB = sessions.reduce(0) { $0 + $1.savedSizeMB }
        return String(
            format: L10n.string("最近压缩记录 · %lld 次 · 可减少 %@"),
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

            if let onDeleteOriginals {
                Button(action: onDeleteOriginals) {
                    Label(L10n.string("删除原文件释放空间"), systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(PhotoDeleteStyle.destructive.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }

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
                                        photoLibraryManager: photoLibraryManager,
                                        onPreview: onPreview
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
    let onPreview: ((PHAsset) -> Void)?

    private var originalAsset: PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [item.originalAssetIdentifier], options: nil).firstObject
    }

    private var compressedAsset: PHAsset? {
        guard let createdAssetIdentifier = item.createdAssetIdentifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [createdAssetIdentifier], options: nil).firstObject
    }

    private var canPreviewCompressedAsset: Bool {
        compressedAsset != nil && onPreview != nil
    }

    private var isOriginalDeleted: Bool {
        item.isOriginalDeleted || originalAsset == nil
    }

    @ViewBuilder
    var body: some View {
        if let compressedAsset, let onPreview {
            Button {
                onPreview(compressedAsset)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            thumbnail(for: compressedAsset)

            VStack(alignment: .leading, spacing: 5) {
                Text(title(for: compressedAsset, fallback: L10n.string("压缩后图片已删除")))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)

                Text("\(item.formattedOriginalSize) → \(item.formattedCompressedSize)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)

                Label(originalStatusText, systemImage: originalStatusIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isOriginalDeleted ? PhotoDeleteStyle.positive : PhotoDeleteStyle.warning)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(item.formattedSavedSize)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(item.savedSizeMB > 0 ? PhotoDeleteStyle.positive : PhotoDeleteStyle.warning)

            if canPreviewCompressedAsset {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }
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
                size: 44
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "questionmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                )
        }
    }

    private var originalStatusText: String {
        isOriginalDeleted ? L10n.string("原图已删除") : L10n.string("原图仍保留")
    }

    private var originalStatusIcon: String {
        isOriginalDeleted ? "checkmark.circle.fill" : "exclamationmark.circle"
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

private enum AdvancedVideoCompressionTab: String, CaseIterable, Identifiable {
    case pending
    case processed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return L10n.string("未压缩")
        case .processed: return L10n.string("已压缩")
        }
    }
}

private struct AdvancedVideoCompressionView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var assets: [PHAsset] = []
    @State private var orderedAssets: [PHAsset] = []
    @State private var videoSizeEstimatesByAssetID: [String: VideoFileSizeEstimate] = [:]
    @State private var selectedAssetIDs: Set<String> = []
    @State private var compressionPlan: VideoCompressionPlan = .default
    @State private var showingCompressionComparison = false
    @State private var showingICloudVideoInfo = false
    @State private var dismissCompressionResultAfterBatch = false
    @State private var previewAsset: AdvancedPreviewAsset?
    @State private var showBatchConfirm = false
    @State private var compressionOptionsContext: AdvancedVideoCompressionOptionsContext?
    @State private var sizeLoadingTask: Task<Void, Never>?
    @State private var selectedTab: AdvancedVideoCompressionTab = .pending
    @State private var visibleVideoLimit = 40
    @State private var isLoadingAssets = false
    @State private var isLoadingVideoSizes = false
    @State private var assetLoadGeneration = 0
    @State private var sizeLoadGeneration = 0
    @State private var processedVideoAssetIDs: Set<String> = []

    private let videoLimitStep = 40
    private let videoSizeUpdateBatchSize = 8

    private var compressionJob: AdvancedVideoCompressionJobState {
        dataManager.videoCompressionJob
    }

    private var isCompressing: Bool {
        compressionJob.isCompressing
    }

    private var selectedAssets: [PHAsset] {
        compressibleAssets.filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var compressibleAssets: [PHAsset] {
        orderedAssets.filter { !processedVideoAssetIDs.contains($0.localIdentifier) }
    }

    private var visibleCompressibleAssets: [PHAsset] {
        VisibleListPagination.visibleItems(compressibleAssets, limit: visibleVideoLimit)
    }

    private var hasMoreCompressibleAssets: Bool {
        VisibleListPagination.hasMore(totalCount: compressibleAssets.count, limit: visibleVideoLimit)
    }

    private var isAllSelected: Bool {
        !visibleCompressibleAssets.isEmpty && visibleCompressibleAssets.allSatisfy { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var reliableVideoSizeMBByAssetID: [String: Double] {
        videoSizeEstimatesByAssetID.reduce(into: [String: Double]()) { result, pair in
            guard pair.value.isReliable else { return }
            result[pair.key] = pair.value.sizeMB
        }
    }

    private var iCloudVideoCount: Int {
        iCloudVideoCount(in: compressibleAssets)
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

        let visibleReliableSizeCount = loadedReliableVideoSizeCount(in: visibleCompressibleAssets)
        let visibleLoadedSizeCount = loadedVideoSizeCount(in: visibleCompressibleAssets)
        let visibleTotalSizeMB = visibleCompressibleAssets.reduce(0) { $0 + (reliableSizeMB(for: $1) ?? dataManager.estimatedSizeMB(for: $1)) }

        if visibleReliableSizeCount == visibleCompressibleAssets.count {
            return String(
                format: L10n.string("已显示 %lld/%lld 个视频 · 合计约 %@"),
                Int64(visibleCompressibleAssets.count),
                Int64(compressibleAssets.count),
                CleanupStatsFormatter.space(visibleTotalSizeMB)
            )
        }

        if visibleReliableSizeCount > 0 {
            return String(
                format: L10n.string("已显示 %lld/%lld 个视频 · 已知约 %@"),
                Int64(visibleCompressibleAssets.count),
                Int64(compressibleAssets.count),
                CleanupStatsFormatter.space(visibleTotalSizeMB)
            )
        }

        if visibleLoadedSizeCount == visibleCompressibleAssets.count {
            return String(
                format: L10n.string("已显示 %lld/%lld 个视频 · 压缩时确认大小"),
                Int64(visibleCompressibleAssets.count),
                Int64(compressibleAssets.count)
            )
        }

        return String(
            format: L10n.string("已显示 %lld/%lld 个视频 · 正在计算大小"),
            Int64(visibleCompressibleAssets.count),
            Int64(compressibleAssets.count)
        )
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
                    videoCompressionTabPicker

                    if isCompressing {
                        AdvancedVideoCompressionProgressCard(
                            processedCount: compressionJob.processedCount,
                            totalCount: compressionJob.totalCount,
                            currentProgress: compressionJob.currentProgress,
                            message: compressionJob.message
                        )
                    }

                    if let compressionResult = compressionJob.result {
                        AdvancedVideoCompressionResultCard(
                            result: compressionResult,
                            onCompare: showCompressionComparison,
                            onDeleteOriginals: queueOriginalVideosForDeletion,
                            onKeepOriginals: keepOriginalVideos
                        )
                    }

                    if let compressionErrorMessage = compressionJob.errorMessage {
                        AdvancedVideoCompressionMessageCard(
                            icon: "exclamationmark.triangle.fill",
                            message: compressionErrorMessage,
                            tint: PhotoDeleteStyle.warning
                        )
                    }

                    switch selectedTab {
                    case .pending:
                        pendingVideoCompressionContent
                    case .processed:
                        processedVideoCompressionContent
                    }

                    Spacer()
                        .frame(height: 24)
                }
                .padding(PhotoDeleteStyle.screenHorizontalPadding)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedTab == .pending, !selectedAssetIDs.isEmpty {
                AdvancedVideoCompressionActionBar(
                    count: selectedAssetIDs.count,
                    estimateText: selectedCompressionEstimateText,
                    processedCount: compressionJob.processedCount,
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
                dataManager.clearVideoCompressionResult()
                dismissCompressionResultAfterBatch = false
            }
        }) {
            BatchConfirmView { deletedAssetIDs in
                dataManager.markVideoCompressionOriginalsDeleted(assetIdentifiers: deletedAssetIDs)
            }
                .environmentObject(dataManager)
        }
        .sheet(item: $previewAsset) { item in
            AdvancedAssetPreviewView(
                asset: item.asset,
                photoLibraryManager: dataManager.photoLibraryManager
            )
        }
        .sheet(isPresented: $showingCompressionComparison) {
            if let compressionResult = compressionJob.result {
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
        .onChange(of: dataManager.videoCompressionHistoryRevision) { _ in
            selectedAssetIDs.removeAll()
            refreshProcessedVideoAssetIDs()
            reloadAssets()
            showingCompressionComparison = false
        }
        .onDisappear {
            sizeLoadingTask?.cancel()
        }
    }

    private var videoCompressionTabPicker: some View {
        Picker(L10n.string("视频压缩"), selection: $selectedTab) {
            ForEach(AdvancedVideoCompressionTab.allCases) { tab in
                Text(tab.title)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(L10n.string("视频压缩"))
    }

    @ViewBuilder
    private var pendingVideoCompressionContent: some View {
        if isLoadingAssets && assets.isEmpty {
            AdvancedLoadingState(
                title: L10n.string("正在准备清理入口"),
                subtitle: L10n.string("稍后会显示可处理的照片和视频。")
            )
        } else if assets.isEmpty {
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

            if !isLoadingAssets, !isLoadingVideoSizes, iCloudVideoCount > 0 {
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
                    ForEach(visibleCompressibleAssets, id: \.localIdentifier) { asset in
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
                        .onAppear {
                            showMoreCompressibleVideosIfNeeded(currentAsset: asset)
                        }
                    }
                }

                if hasMoreCompressibleAssets {
                    Text(L10n.string("继续向下滚动加载更多"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    @ViewBuilder
    private var processedVideoCompressionContent: some View {
        if dataManager.videoCompressionHistoryStore.sessions.isEmpty {
            AdvancedEmptyState(
                icon: "video.badge.checkmark",
                title: L10n.string("还没有压缩记录"),
                subtitle: L10n.string("压缩完成的视频会留在最近压缩记录里。")
            )
        } else {
            AdvancedVideoCompressionHistoryCard(
                sessions: dataManager.videoCompressionHistoryStore.sessions,
                photoLibraryManager: dataManager.photoLibraryManager,
                startsExpanded: true,
                onDeleteOriginals: queueCompressedHistoryOriginalVideosForDeletion,
                onPreview: { asset in
                    previewAsset = AdvancedPreviewAsset(asset: asset)
                }
            )
        }
    }

    private func reloadAssets() {
        assetLoadGeneration += 1
        let generation = assetLoadGeneration
        isLoadingAssets = true
        refreshProcessedVideoAssetIDs()
        dataManager.loadPhotosForAdvancedCleanup(.videoCompression) { loadedAssets in
            guard generation == assetLoadGeneration else { return }
            applyLoadedAssets(loadedAssets)
        }
    }

    private func applyLoadedAssets(_ loadedAssets: [PHAsset]) {
        assets = loadedAssets
        visibleVideoLimit = 40
        let loadedIDs = Set(loadedAssets.map(\.localIdentifier))
        selectedAssetIDs = selectedAssetIDs.filter { selectedID in
            loadedIDs.contains(selectedID)
        }
        pruneSelectionToCompressibleAssets()
        seedCachedVideoSizeEstimates(for: loadedAssets)
        refreshOrderedAssets()
        isLoadingAssets = false
        loadVideoSizesForVisiblePendingVideos()
    }

    private func refreshProcessedVideoAssetIDs() {
        processedVideoAssetIDs = Self.makeProcessedVideoAssetIDs(
            from: dataManager.videoCompressionHistoryStore.sessions
        )
    }

    private static func makeProcessedVideoAssetIDs(
        from sessions: [VideoCompressionSession]
    ) -> Set<String> {
        var ids: Set<String> = []
        for session in sessions {
            for item in session.items {
                ids.insert(item.originalAssetIdentifier)
                if let createdAssetIdentifier = item.createdAssetIdentifier {
                    ids.insert(createdAssetIdentifier)
                }
            }
        }
        return ids
    }

    private func displaySizeMB(for asset: PHAsset) -> Double {
        reliableSizeMB(for: asset) ?? dataManager.estimatedSizeMB(for: asset)
    }

    private func displaySizeText(for asset: PHAsset) -> String {
        guard let estimate = videoSizeEstimatesByAssetID[asset.localIdentifier] else {
            return L10n.string("计算中")
        }
        switch estimate.source {
        case .assetResource:
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

    private func videoSizeFirstOrder(_ lhs: PHAsset, _ rhs: PHAsset) -> Bool {
        let lhsRank = videoSizeSortRank(for: lhs)
        let rhsRank = videoSizeSortRank(for: rhs)

        if lhsRank.priority != rhsRank.priority {
            return lhsRank.priority < rhsRank.priority
        }

        if lhsRank.sizeMB != rhsRank.sizeMB {
            return lhsRank.sizeMB > rhsRank.sizeMB
        }

        let lhsDate = lhs.creationDate ?? .distantPast
        let rhsDate = rhs.creationDate ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return lhs.localIdentifier < rhs.localIdentifier
    }

    private func videoSizeSortRank(for asset: PHAsset) -> (priority: Int, sizeMB: Double) {
        guard let estimate = videoSizeEstimatesByAssetID[asset.localIdentifier] else {
            return (priority: 1, sizeMB: dataManager.estimatedSizeMB(for: asset))
        }
        guard estimate.isReliable else {
            return (priority: 1, sizeMB: dataManager.estimatedSizeMB(for: asset))
        }
        return (priority: 0, sizeMB: estimate.sizeMB)
    }

    private func hasReliableSizes(for selectedAssets: [PHAsset]) -> Bool {
        !selectedAssets.isEmpty && selectedAssets.allSatisfy { reliableSizeMB(for: $0) != nil }
    }

    private func hasPendingSizeLoads(for selectedAssets: [PHAsset]) -> Bool {
        selectedAssets.contains { videoSizeEstimatesByAssetID[$0.localIdentifier] == nil }
    }

    private func seedCachedVideoSizeEstimates(for loadedAssets: [PHAsset]) {
        for asset in loadedAssets {
            guard let cached = dataManager.cachedVideoFileSizeEstimate(for: asset) else { continue }
            videoSizeEstimatesByAssetID[asset.localIdentifier] = cached
        }
    }

    private func applyVideoSizeEstimates(
        _ estimatesByAssetID: [String: VideoFileSizeEstimate],
        generation: Int
    ) {
        guard generation == sizeLoadGeneration, !estimatesByAssetID.isEmpty else { return }
        for (assetID, estimate) in estimatesByAssetID {
            dataManager.cacheVideoFileSizeEstimate(estimate, forAssetIdentifier: assetID)
            videoSizeEstimatesByAssetID[assetID] = estimate
        }
        refreshOrderedAssets()
    }

    private func refreshOrderedAssets() {
        orderedAssets = assets.sorted(by: videoSizeFirstOrder)
    }

    private func loadVideoSizes(for loadedAssets: [PHAsset]) {
        sizeLoadingTask?.cancel()
        sizeLoadGeneration += 1
        let generation = sizeLoadGeneration
        guard !loadedAssets.isEmpty else {
            isLoadingVideoSizes = false
            return
        }
        isLoadingVideoSizes = true
        sizeLoadingTask = Task {
            var pendingEstimates: [String: VideoFileSizeEstimate] = [:]
            for asset in loadedAssets {
                if Task.isCancelled { break }
                let alreadyLoaded = await MainActor.run {
                    guard generation == sizeLoadGeneration else { return true }
                    if let cached = dataManager.cachedVideoFileSizeEstimate(for: asset) {
                        videoSizeEstimatesByAssetID[asset.localIdentifier] = cached
                        return true
                    }
                    return videoSizeEstimatesByAssetID[asset.localIdentifier] != nil
                }
                if alreadyLoaded { continue }

                do {
                    let estimate = try await dataManager.photoLibraryManager.videoFileSizeEstimate(for: asset)
                    pendingEstimates[asset.localIdentifier] = estimate
                    if pendingEstimates.count >= videoSizeUpdateBatchSize {
                        let estimatesToApply = pendingEstimates
                        pendingEstimates.removeAll()
                        await MainActor.run {
                            applyVideoSizeEstimates(estimatesToApply, generation: generation)
                        }
                    }
                } catch {
                    continue
                }
            }
            if !pendingEstimates.isEmpty {
                let estimatesToApply = pendingEstimates
                await MainActor.run {
                    applyVideoSizeEstimates(estimatesToApply, generation: generation)
                }
            }
            await MainActor.run {
                guard generation == sizeLoadGeneration else { return }
                isLoadingVideoSizes = false
            }
        }
    }

    private func showMoreCompressibleVideos() {
        withAnimation(.easeInOut(duration: 0.18)) {
            visibleVideoLimit = VisibleListPagination.advancedLimit(
                totalCount: compressibleAssets.count,
                currentLimit: visibleVideoLimit,
                step: videoLimitStep
            )
        }
        loadVideoSizesForVisiblePendingVideos()
    }

    private func loadVideoSizesForVisiblePendingVideos() {
        loadVideoSizes(for: visibleCompressibleAssets)
    }

    private func showMoreCompressibleVideosIfNeeded(currentAsset asset: PHAsset) {
        guard hasMoreCompressibleAssets,
              let index = visibleCompressibleAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }),
              index >= max(visibleCompressibleAssets.count - 6, 0) else {
            return
        }
        showMoreCompressibleVideos()
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
        dataManager.setVideoCompressionError(nil)
    }

    private func toggleBulkSelection() {
        guard !isCompressing else { return }
        HapticManager.impact(.light)
        let visibleIDs = Set(visibleCompressibleAssets.map(\.localIdentifier))
        if isAllSelected {
            selectedAssetIDs.subtract(visibleIDs)
        } else {
            selectedAssetIDs.formUnion(visibleIDs)
        }
        dataManager.setVideoCompressionError(nil)
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
        dataManager.clearVideoCompressionResult()
        dataManager.startVideoCompression(videos: videos, plan: plan)
    }

    private func showCompressionComparison() {
        guard compressionJob.result?.createdAssetIdentifiers.isEmpty == false else {
            dataManager.setVideoCompressionError(L10n.string("暂时找不到压缩后视频。"))
            return
        }
        showingCompressionComparison = true
    }

    private func showICloudVideoInfo() {
        showingICloudVideoInfo = true
    }

    private func queueOriginalVideosForDeletion() {
        guard let compressionResult = compressionJob.result else { return }
        guard compressionResult.hasMeaningfulSavings else {
            dataManager.setVideoCompressionError(L10n.string("这次没有明显减少空间，建议先保留原视频。"))
            return
        }

        let originalIDs = Set(compressionResult.items.map(\.originalAssetIdentifier))
        let fetchedOriginals = PHAsset.fetchAssets(withLocalIdentifiers: Array(originalIDs), options: nil)
        var originalAssets: [PHAsset] = []
        fetchedOriginals.enumerateObjects { asset, _, _ in
            originalAssets.append(asset)
        }
        guard !originalAssets.isEmpty else {
            dataManager.setVideoCompressionError(L10n.string("暂时找不到原视频。"))
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

    private func queueCompressedHistoryOriginalVideosForDeletion() {
        let originalIDs = Set(dataManager.videoCompressionHistoryStore.sessions.flatMap { session in
            session.items.map(\.originalAssetIdentifier)
        })
        let fetchedOriginals = PHAsset.fetchAssets(withLocalIdentifiers: Array(originalIDs), options: nil)
        var originalAssets: [PHAsset] = []
        fetchedOriginals.enumerateObjects { asset, _, _ in
            originalAssets.append(asset)
        }
        guard !originalAssets.isEmpty else {
            dataManager.setVideoCompressionError(L10n.string("暂时找不到原视频。"))
            return
        }

        for asset in originalAssets {
            _ = dataManager.markReviewed(asset)
            dataManager.addToDeleteCandidates(asset)
        }
        HapticManager.notify(.warning)
        dismissCompressionResultAfterBatch = false
        showBatchConfirm = true
    }

    private func keepOriginalVideos() {
        dataManager.clearVideoCompressionResult()
        showingCompressionComparison = false
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
                title: isAllSelected ? L10n.string("取消") : L10n.string("全选全部"),
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

                    Text(L10n.string("可减少"))
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
                        AdvancedVideoCompressionMetric(label: L10n.string("可减少"), value: result.formattedSavedSize)
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
    let onDeleteOriginals: (() -> Void)?
    let onPreview: ((PHAsset) -> Void)?
    @State private var isExpanded = false

    init(
        sessions: [VideoCompressionSession],
        photoLibraryManager: PhotoLibraryManager,
        startsExpanded: Bool = false,
        onDeleteOriginals: (() -> Void)? = nil,
        onPreview: ((PHAsset) -> Void)? = nil
    ) {
        self.sessions = sessions
        self.photoLibraryManager = photoLibraryManager
        self.onDeleteOriginals = onDeleteOriginals
        self.onPreview = onPreview
        _isExpanded = State(initialValue: startsExpanded)
    }

    private var summaryText: String {
        let savedSizeMB = sessions.reduce(0) { $0 + $1.savedSizeMB }
        return String(
            format: L10n.string("最近压缩记录 · %lld 次 · 可减少 %@"),
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

            if let onDeleteOriginals {
                Button(action: onDeleteOriginals) {
                    Label(L10n.string("删除原文件释放空间"), systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(PhotoDeleteStyle.destructive.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }

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
                                        photoLibraryManager: photoLibraryManager,
                                        onPreview: onPreview
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
    let onPreview: ((PHAsset) -> Void)?

    private var originalAsset: PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [item.originalAssetIdentifier], options: nil).firstObject
    }

    private var compressedAsset: PHAsset? {
        guard let createdAssetIdentifier = item.createdAssetIdentifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [createdAssetIdentifier], options: nil).firstObject
    }

    private var isOriginalDeleted: Bool {
        item.isOriginalDeleted || originalAsset == nil
    }

    private var canPreviewCompressedAsset: Bool {
        compressedAsset != nil && onPreview != nil
    }

    @ViewBuilder
    var body: some View {
        if let compressedAsset, let onPreview {
            Button {
                onPreview(compressedAsset)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            thumbnail(for: compressedAsset)

            VStack(alignment: .leading, spacing: 5) {
                Text(title(for: compressedAsset, fallback: L10n.string("压缩后视频已删除")))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)

                Text("\(item.formattedOriginalSize) → \(item.formattedCompressedSize)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)

                Label(originalStatusText, systemImage: originalStatusIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isOriginalDeleted ? PhotoDeleteStyle.positive : PhotoDeleteStyle.warning)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(item.formattedSavedSize)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(item.savedSizeMB > 0 ? PhotoDeleteStyle.positive : PhotoDeleteStyle.warning)

            if canPreviewCompressedAsset {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }
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
                size: 44
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "questionmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                )
        }
    }

    private var originalStatusText: String {
        isOriginalDeleted ? L10n.string("原视频已删除") : L10n.string("原视频仍保留")
    }

    private var originalStatusIcon: String {
        isOriginalDeleted ? "checkmark.circle.fill" : "exclamationmark.circle"
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

private struct AdvancedSimilarGroupSnapshot {
    let groups: [AdvancedSimilarPhotoGroup]
    let visibleGroups: [AdvancedSimilarPhotoGroup]
    let suggestedDeleteCount: Int
    let hasMoreGroups: Bool
}

private struct AdvancedSimilarPhotoGroupsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var groups: [AdvancedSimilarPhotoGroup] = []
    @State private var selectedAssetIDs: Set<String> = []
    @State private var selectedFilter: AdvancedCleanupFilter = .all
    @State private var showBatchConfirm = false
    @State private var previewAsset: AdvancedPreviewAsset?
    @State private var visibleGroupLimit = 24

    private let groupLimitStep = 24

    private var selectedAssets: [PHAsset] {
        makeGroupSnapshot().groups.flatMap(\.assets).filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private func makeGroupSnapshot() -> AdvancedSimilarGroupSnapshot {
        let filteredGroups = groups.filter { matches(group: $0, filter: selectedFilter) }
        return AdvancedSimilarGroupSnapshot(
            groups: filteredGroups,
            visibleGroups: VisibleListPagination.visibleItems(filteredGroups, limit: visibleGroupLimit),
            suggestedDeleteCount: filteredGroups.reduce(0) { $0 + $1.suggestedDeleteCount },
            hasMoreGroups: VisibleListPagination.hasMore(totalCount: filteredGroups.count, limit: visibleGroupLimit)
        )
    }

    var body: some View {
        let snapshot = makeGroupSnapshot()

        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(spacing: 14) {
                    AdvancedFilterPills(kind: .similarPhotos, selection: $selectedFilter)

                    AdvancedAssetListSummaryCard(
                        title: String(format: L10n.string("发现 %lld 组相似照片"), Int64(snapshot.groups.count)),
                        subtitle: String(
                            format: L10n.string("预计可减少 %lld 张，逐组确认更稳妥。"),
                            Int64(snapshot.suggestedDeleteCount)
                        ),
                        buttonTitle: selectedAssetIDs.isEmpty ? L10n.string("建议选择") : L10n.string("取消"),
                        action: toggleRecommendedSelection
                    )

                    if groups.isEmpty {
                        AdvancedEmptyState(
                            icon: AdvancedCleanupKind.similarPhotos.icon,
                            title: L10n.string("暂未发现相似照片"),
                            subtitle: L10n.string("会把拍摄时间接近的照片放在一起，方便逐组确认。")
                        )
                    } else if snapshot.groups.isEmpty {
                        AdvancedEmptyState(
                            icon: AdvancedCleanupKind.similarPhotos.icon,
                            title: L10n.string("当前筛选没有内容"),
                            subtitle: L10n.string("可以切换到全部，或稍后再回来查看。")
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(snapshot.visibleGroups) { group in
                                AdvancedSimilarPhotoGroupCard(
                                    group: group,
                                    photoLibraryManager: dataManager.photoLibraryManager,
                                    selectedAssetIDs: selectedAssetIDs,
                                    onSelectRecommended: { selectRecommended(in: group) },
                                    onPreviewGroup: {
                                        guard let firstAsset = group.assets.first else { return }
                                        previewAsset = AdvancedPreviewAsset(asset: firstAsset, assets: group.assets)
                                    },
                                    onToggleAsset: toggleSelection,
                                    onPreview: { previewAsset = AdvancedPreviewAsset(asset: $0, assets: group.assets) }
                                )
                                .onAppear {
                                    showMoreGroupsIfNeeded(currentGroup: group)
                                }
                            }
                        }

                        if snapshot.hasMoreGroups {
                            Text(L10n.string("继续向下滚动加载更多"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
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
                photoLibraryManager: dataManager.photoLibraryManager,
                assets: item.assets,
                selectedAssetIDs: $selectedAssetIDs
            )
        }
        .task {
            reloadGroups()
        }
        .onChange(of: selectedFilter) { _ in
            visibleGroupLimit = groupLimitStep
            pruneSelectionToFilteredGroups()
        }
    }

    private func toggleRecommendedSelection() {
        HapticManager.impact(.light)
        if selectedAssetIDs.isEmpty {
            selectedAssetIDs = Set(makeGroupSnapshot().visibleGroups.flatMap { $0.assets.dropFirst().map(\.localIdentifier) })
        } else {
            selectedAssetIDs.removeAll()
        }
    }

    private func selectRecommended(in group: AdvancedSimilarPhotoGroup) {
        let updatedSelection = AdvancedSimilarPhotoRecommendedSelection.toggledSelection(
            current: selectedAssetIDs,
            groupAssetIDs: group.assets.map(\.localIdentifier)
        )
        guard updatedSelection != selectedAssetIDs else { return }
        HapticManager.impact(.light)
        selectedAssetIDs = updatedSelection
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
        groups = dataManager.makeSimilarPhotoGroups()
        visibleGroupLimit = groupLimitStep
        pruneSelectionToFilteredGroups()
    }

    private func showMoreGroups() {
        let snapshot = makeGroupSnapshot()
        withAnimation(.easeInOut(duration: 0.18)) {
            visibleGroupLimit = VisibleListPagination.advancedLimit(
                totalCount: snapshot.groups.count,
                currentLimit: visibleGroupLimit,
                step: groupLimitStep
            )
        }
    }

    private func showMoreGroupsIfNeeded(currentGroup group: AdvancedSimilarPhotoGroup) {
        let snapshot = makeGroupSnapshot()
        guard snapshot.hasMoreGroups,
              let index = snapshot.visibleGroups.firstIndex(where: { $0.id == group.id }),
              index >= max(snapshot.visibleGroups.count - 4, 0) else {
            return
        }
        showMoreGroups()
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
        guard group.assets.count >= 2 else { return false }
        let burstIDs = Set(group.assets.compactMap(\.burstIdentifier).filter { !$0.isEmpty })
        if burstIDs.count == 1, burstIDs.first != nil {
            return true
        }

        guard group.assets.count >= 3 else { return false }
        let dates = group.assets.compactMap(\.creationDate).sorted()
        guard let first = dates.first, let last = dates.last else { return false }
        return last.timeIntervalSince(first) <= 20
    }

    private func pruneSelectionToFilteredGroups() {
        let visibleIDs = Set(makeGroupSnapshot().groups.flatMap { $0.assets.map(\.localIdentifier) })
        selectedAssetIDs = selectedAssetIDs.filter { visibleIDs.contains($0) }
    }
}

enum AdvancedSimilarPhotoRecommendedSelection {
    static func toggledSelection(current selectedAssetIDs: Set<String>, groupAssetIDs: [String]) -> Set<String> {
        let recommendedAssetIDs = Set(groupAssetIDs.dropFirst())
        guard !recommendedAssetIDs.isEmpty else { return selectedAssetIDs }

        var updatedSelection = selectedAssetIDs
        if recommendedAssetIDs.isSubset(of: selectedAssetIDs) {
            updatedSelection.subtract(recommendedAssetIDs)
        } else {
            updatedSelection.formUnion(recommendedAssetIDs)
        }
        return updatedSelection
    }
}

private struct AdvancedSimilarPhotoGroupCard: View {
    let group: AdvancedSimilarPhotoGroup
    let photoLibraryManager: PhotoLibraryManager
    let selectedAssetIDs: Set<String>
    let onSelectRecommended: () -> Void
    let onPreviewGroup: () -> Void
    let onToggleAsset: (PHAsset) -> Void
    let onPreview: (PHAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(String(format: L10n.string("%lld 张相近候选"), Int64(group.assets.count)))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }

                Spacer()

                HStack(spacing: 8) {
                    AdvancedSimilarPhotoGroupActionButton(
                        title: L10n.string("预览"),
                        systemImage: "rectangle.stack",
                        tint: PhotoDeleteStyle.accent,
                        action: onPreviewGroup
                    )

                    AdvancedSimilarPhotoGroupActionButton(
                        title: L10n.string("保留首张"),
                        systemImage: "checkmark.circle.fill",
                        tint: PhotoDeleteStyle.positive,
                        action: onSelectRecommended
                    )
                    .accessibilityHint(Text(L10n.string("选择除首张外的相似照片；再次点击可取消选择。")))
                }
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

private struct AdvancedSimilarPhotoGroupActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
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

            AdvancedSelectableThumbnailSelectionButton(
                isSelected: isSelected,
                action: onToggleSelection
            )

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

private struct AdvancedSelectableThumbnailSelectionButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .frame(width: 44, height: 44)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: AdvancedSelectableThumbnailSelectionButtonStyle.iconSize, weight: .semibold))
                    .foregroundColor(
                        isSelected
                            ? PhotoDeleteStyle.accent.opacity(AdvancedSelectableThumbnailSelectionButtonStyle.selectedIconOpacity)
                            : Color.white.opacity(AdvancedSelectableThumbnailSelectionButtonStyle.unselectedIconOpacity)
                    )
                    .frame(
                        width: AdvancedSelectableThumbnailSelectionButtonStyle.visualSize,
                        height: AdvancedSelectableThumbnailSelectionButtonStyle.visualSize
                    )
                    .background(
                        Circle()
                            .fill(PhotoDeleteStyle.background.opacity(AdvancedSelectableThumbnailSelectionButtonStyle.backgroundOpacity(isSelected: isSelected)))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(AdvancedSelectableThumbnailSelectionButtonStyle.strokeOpacity(isSelected: isSelected)), lineWidth: 1)
                    )
                    .shadow(
                        color: .black.opacity(AdvancedSelectableThumbnailSelectionButtonStyle.shadowOpacity),
                        radius: AdvancedSelectableThumbnailSelectionButtonStyle.shadowRadius,
                        x: 0,
                        y: 1
                    )
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44, alignment: .topTrailing)
        .contentShape(Rectangle())
        .accessibilityLabel(isSelected ? L10n.string("取消选择") : L10n.string("选择"))
        .accessibilityValue(Text(isSelected ? L10n.string("已选") : L10n.string("未选择")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum AdvancedSelectableThumbnailSelectionButtonStyle {
    static let iconSize: CGFloat = 20
    static let visualSize: CGFloat = 28
    static let selectedIconOpacity = 0.78
    static let unselectedIconOpacity = 0.62
    static let selectedBackgroundOpacity = 0.48
    static let unselectedBackgroundOpacity = 0.24
    static let selectedStrokeOpacity = 0.16
    static let unselectedStrokeOpacity = 0.18
    static let shadowOpacity = 0.14
    static let shadowRadius: CGFloat = 3

    static func backgroundOpacity(isSelected: Bool) -> Double {
        isSelected ? selectedBackgroundOpacity : unselectedBackgroundOpacity
    }

    static func strokeOpacity(isSelected: Bool) -> Double {
        isSelected ? selectedStrokeOpacity : unselectedStrokeOpacity
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
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let assets: [PHAsset]
    let selectedAssetIDs: Binding<Set<String>>?

    @State private var selectedAssetID: String

    init(
        asset: PHAsset,
        photoLibraryManager: PhotoLibraryManager,
        assets: [PHAsset] = [],
        selectedAssetIDs: Binding<Set<String>>? = nil
    ) {
        self.asset = asset
        self.photoLibraryManager = photoLibraryManager
        let uniqueAssets = Self.previewAssets(selectedAsset: asset, assets: assets)
        self.assets = uniqueAssets
        self.selectedAssetIDs = selectedAssetIDs
        _selectedAssetID = State(initialValue: asset.localIdentifier)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    PhotoDeleteStyle.background.ignoresSafeArea()

                    if assets.count > 1 {
                        TabView(selection: $selectedAssetID) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                AdvancedAssetPreviewPage(
                                    asset: asset,
                                    photoLibraryManager: photoLibraryManager,
                                    viewportSize: geometry.size
                                )
                                .tag(asset.localIdentifier)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    } else {
                        AdvancedAssetPreviewPage(
                            asset: selectedAsset,
                            photoLibraryManager: photoLibraryManager,
                            viewportSize: geometry.size
                        )
                    }

                    if assets.count > 1 {
                        previewPagingOverlay
                    }

                    if selectedAssetIDs != nil {
                        previewSelectionOverlay
                    }
                }
            }
            .navigationTitle(selectedAsset.mediaType == .video ? L10n.string("视频预览") : L10n.string("照片预览"))
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
    }

    private var selectedAsset: PHAsset {
        assets.first { $0.localIdentifier == selectedAssetID } ?? asset
    }

    private var assetIdentifiers: [String] {
        assets.map(\.localIdentifier)
    }

    private var previewPositionText: String? {
        AdvancedPreviewPaging.positionText(
            selectedIdentifier: selectedAssetID,
            identifiers: assetIdentifiers
        )
    }

    private var canSelectPreviousPreviewAsset: Bool {
        AdvancedPreviewPaging.adjacentIdentifier(
            selectedIdentifier: selectedAssetID,
            identifiers: assetIdentifiers,
            direction: .previous
        ) != nil
    }

    private var canSelectNextPreviewAsset: Bool {
        AdvancedPreviewPaging.adjacentIdentifier(
            selectedIdentifier: selectedAssetID,
            identifiers: assetIdentifiers,
            direction: .next
        ) != nil
    }

    private var isSelectedForDeletion: Bool {
        selectedAssetIDs?.wrappedValue.contains(selectedAssetID) ?? false
    }

    private var previewSelectionOverlay: some View {
        HStack {
            Spacer()

            Button(action: toggleSelectedPreviewAsset) {
                Label(
                    isSelectedForDeletion ? L10n.string("已加入待删除") : L10n.string("加入待删除"),
                    systemImage: isSelectedForDeletion ? "checkmark.circle.fill" : "square"
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.66))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(isSelectedForDeletion ? L10n.string("已加入待删除") : L10n.string("加入待删除")))
            .accessibilityIdentifier("advanced-preview-delete-selection-toggle")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .zIndex(3)
    }

    private var previewPagingOverlay: some View {
        ZStack {
            VStack {
                if let previewPositionText {
                    HStack {
                        Spacer()

                        Text(previewPositionText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule(style: .continuous).fill(Color.black.opacity(0.54)))
                            .accessibilityLabel(Text("\(L10n.string("位置")) \(previewPositionText)"))
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }

                Spacer()
            }
            .allowsHitTesting(false)

            HStack {
                AdvancedPreviewPagingButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: L10n.string("上一张"),
                    isDisabled: !canSelectPreviousPreviewAsset
                ) {
                    selectPreviewAsset(.previous)
                }

                Spacer()

                AdvancedPreviewPagingButton(
                    systemImage: "chevron.right",
                    accessibilityLabel: L10n.string("下一张"),
                    isDisabled: !canSelectNextPreviewAsset
                ) {
                    selectPreviewAsset(.next)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func selectPreviewAsset(_ direction: AdvancedPreviewPagingDirection) {
        guard let nextIdentifier = AdvancedPreviewPaging.adjacentIdentifier(
            selectedIdentifier: selectedAssetID,
            identifiers: assetIdentifiers,
            direction: direction
        ) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            selectedAssetID = nextIdentifier
        }
    }

    private func toggleSelectedPreviewAsset() {
        guard let selectedAssetIDs else { return }

        HapticManager.impact(.light)
        var ids = selectedAssetIDs.wrappedValue
        if ids.contains(selectedAssetID) {
            ids.remove(selectedAssetID)
        } else {
            ids.insert(selectedAssetID)
        }
        selectedAssetIDs.wrappedValue = ids
    }

    private static func previewAssets(selectedAsset: PHAsset, assets: [PHAsset]) -> [PHAsset] {
        var seenIDs: Set<String> = []
        let source = assets.isEmpty ? [selectedAsset] : assets
        var ordered = source.filter { asset in
            seenIDs.insert(asset.localIdentifier).inserted
        }
        if !seenIDs.contains(selectedAsset.localIdentifier) {
            ordered.insert(selectedAsset, at: 0)
        }
        return ordered
    }
}

enum AdvancedPreviewPagingDirection {
    case previous
    case next
}

enum AdvancedPreviewPaging {
    static func selectedIndex(selectedIdentifier: String, identifiers: [String]) -> Int {
        identifiers.firstIndex(of: selectedIdentifier) ?? 0
    }

    static func positionText(selectedIdentifier: String, identifiers: [String]) -> String? {
        guard identifiers.count > 1 else { return nil }
        let index = selectedIndex(selectedIdentifier: selectedIdentifier, identifiers: identifiers)
        return "\(index + 1) / \(identifiers.count)"
    }

    static func adjacentIdentifier(
        selectedIdentifier: String,
        identifiers: [String],
        direction: AdvancedPreviewPagingDirection
    ) -> String? {
        guard identifiers.count > 1 else { return nil }
        let index = selectedIndex(selectedIdentifier: selectedIdentifier, identifiers: identifiers)

        switch direction {
        case .previous:
            guard index > 0 else { return nil }
            return identifiers[index - 1]
        case .next:
            guard index < identifiers.count - 1 else { return nil }
            return identifiers[index + 1]
        }
    }
}

private struct AdvancedPreviewPagingButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 46, height: 58)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.42))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.25 : 1)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct AdvancedAssetPreviewPage: View {
    @Environment(\.displayScale) private var displayScale
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let viewportSize: CGSize

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            if asset.mediaType == .video {
                PhotoAssetVideoPlayerView(
                    asset: asset,
                    photoLibraryManager: photoLibraryManager
                )
            } else if let image {
                ZoomablePhotoPreview(image: image)
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
                loadImage()
            }
        }
        .onDisappear {
            photoLibraryManager.cancelImageRequest(requestID)
            requestID = nil
        }
    }

    private func loadImage() {
        guard requestID == nil, image == nil else { return }
        let targetSize = photoPreviewTargetSize(for: asset, viewport: viewportSize, displayScale: displayScale)
        requestID = photoLibraryManager.loadHighQualityPreview(
            for: asset,
            size: targetSize,
            networkAccessAllowed: true
        ) { loadedImage in
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
                Text(String(format: L10n.string("加入待删除 %lld 项"), Int64(count)))
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
            return [.all, .burst]
        case .largeFiles:
            return [.all]
        case .imageCompression:
            return [.all, .large]
        case .videoCompression:
            return [.all, .large, .long]
        case .videos:
            return [.all, .large, .long]
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

private struct AdvancedLoadingState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))

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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .photoDeleteCard()
        .accessibilityElement(children: .combine)
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
    let assets: [PHAsset]

    init(asset: PHAsset, assets: [PHAsset] = []) {
        self.asset = asset
        self.assets = assets
    }

    var id: String {
        ([asset.localIdentifier] + assets.map(\.localIdentifier)).joined(separator: "|")
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
            parts.append(String(format: L10n.string("视频 %@"), formattedDuration(asset.duration)))
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
