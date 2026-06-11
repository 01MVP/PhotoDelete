//
//  AdvancedView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 6/11/26.
//

import SwiftUI
import Photos

struct AdvancedView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @State private var selectedMonthID: String?

    private var isLocked: Bool {
        !purchaseManager.isSupporter
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                PhotoDelScreenBackground()

                ScrollView(showsIndicators: false) {
                    let snapshot = isLocked ?
                        AdvancedLibrarySnapshot.demo(referenceDate: Date()) :
                        dataManager.makeAdvancedLibrarySnapshot()
                    let selectedMonth = selectedMonthSummary(in: snapshot)

                    VStack(spacing: 18) {
                        header

                        if !isLocked && !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                            PhotoAuthorizationCard(
                                subtitle: L10n.string("进阶功能需要读取本机照片库，才能生成真实月份进度和清理队列。"),
                                onRequestAccess: { dataManager.requestPhotoLibraryAccess() }
                            )
                        }

                        AdvancedMonthProgressCard(summary: selectedMonth, isDemo: isLocked)

                        monthProgressSection(
                            summaries: snapshot.monthSummaries,
                            selectedMonth: selectedMonth,
                            isLocked: isLocked
                        )

                        monthActionCard(summary: selectedMonth, isLocked: isLocked)

                        cleanupEntrySection(
                            queues: snapshot.cleanupQueues,
                            isLocked: isLocked
                        )

                        Spacer()
                            .frame(height: isLocked ? 220 : 96)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .opacity(isLocked ? 0.42 : 1)
                    .allowsHitTesting(!isLocked)
                }

                if isLocked {
                    AdvancedBottomPaywall(
                        priceText: purchaseManager.supporterPriceText,
                        isLoading: purchaseManager.isLoading,
                        errorMessage: purchaseManager.errorMessage,
                        onPurchase: purchaseSupporter,
                        onRestore: restorePurchases
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await purchaseManager.loadProducts()
            await purchaseManager.refreshEntitlements()
            dataManager.syncPhotoLibraryAuthorization()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(L10n.string("进阶"))
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                    }
                }

                Text(isLocked ? L10n.string("示例展示，解锁后查看真实清理队列") : L10n.string("按月份进度和清理队列整理照片"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
            }

            Spacer()

            Button(action: isLocked ? purchaseSupporter : {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(PhotoDelStyle.elevatedSurface))
            }
            .buttonStyle(.plain)
        }
    }

    private func monthProgressSection(
        summaries: [PhotoMonthSummary],
        selectedMonth: PhotoMonthSummary,
        isLocked: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("月份进度"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Spacer()

                if !isLocked, !summaries.isEmpty {
                    NavigationLink {
                        AdvancedMonthListView(summaries: summaries)
                            .environmentObject(dataManager)
                    } label: {
                        Text(L10n.string("全部"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(L10n.string("示例"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.tertiaryText)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(summaries.prefix(18)) { summary in
                        Button {
                            selectedMonthID = summary.id
                        } label: {
                            AdvancedMonthChip(
                                summary: summary,
                                isSelected: summary.id == selectedMonth.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func monthActionCard(
        summary: PhotoMonthSummary,
        isLocked: Bool
    ) -> some View {
        Group {
            if isLocked {
                Button(action: purchaseSupporter) {
                    AdvancedMonthActionContent(summary: summary)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    AdvancedAssetListView(mode: .month(summary.monthStart))
                        .environmentObject(dataManager)
                } label: {
                    AdvancedMonthActionContent(summary: summary)
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Spacer()

                Text(isLocked ? L10n.string("示例") : L10n.string("专门列表"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
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
                            .background(PhotoDelStyle.hairline)
                            .padding(.leading, 62)
                    }
                }
            }
            .photoDelCard()
        }
    }

    @ViewBuilder
    private func cleanupDestination(for kind: AdvancedCleanupKind) -> some View {
        switch kind {
        case .similarPhotos:
            AdvancedSimilarPhotoGroupsView()
                .environmentObject(dataManager)
        case .largeFiles, .screenshots, .videos:
            AdvancedAssetListView(mode: .cleanup(kind))
                .environmentObject(dataManager)
        }
    }

    private func selectedMonthSummary(in snapshot: AdvancedLibrarySnapshot) -> PhotoMonthSummary {
        if let selectedMonthID,
           let selected = snapshot.monthSummaries.first(where: { $0.id == selectedMonthID }) {
            return selected
        }

        if let first = snapshot.monthSummaries.first {
            return first
        }

        let monthStart = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        return PhotoMonthSummary(
            monthStart: monthStart,
            assetCount: 0,
            screenshotCount: 0,
            videoCount: 0,
            reviewedCount: 0,
            estimatedSizeMB: 0
        )
    }

    private func purchaseSupporter() {
        Task { await purchaseManager.purchaseSupporter() }
    }

    private func restorePurchases() {
        Task { await purchaseManager.restorePurchases() }
    }
}

private struct AdvancedMonthProgressCard: View {
    let summary: PhotoMonthSummary
    let isDemo: Bool

    var body: some View {
        HStack(spacing: 16) {
            AdvancedProgressRing(progress: summary.progress, size: 78, lineWidth: 8) {
                Text("\(Int(summary.progress * 100))%")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(L10n.string("\(AdvancedMonthFormatter.monthTitle.string(from: summary.monthStart))清理进度"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        if isDemo {
                            AdvancedDemoTag()
                        }
                    }

                    Text(L10n.string("已整理 \(summary.reviewedCount)/\(summary.assetCount) 项，预计占用 \(summary.formattedEstimatedSize)。"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
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
        .photoDelCard()
    }
}

private struct AdvancedMiniMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(PhotoDelStyle.tertiaryText)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PhotoDelStyle.elevatedSurface)
        )
    }
}

private struct AdvancedMonthChip: View {
    let summary: PhotoMonthSummary
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdvancedProgressRing(progress: summary.progress, size: 34, lineWidth: 4) {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(AdvancedMonthFormatter.shortMonth.string(from: summary.monthStart))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                    .lineLimit(1)

                Text(L10n.string("\(summary.assetCount) 项 · \(Int(summary.progress * 100))%"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
        }
        .frame(width: 94, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? PhotoDelStyle.accent.opacity(0.16) : PhotoDelStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? PhotoDelStyle.accent.opacity(0.65) : PhotoDelStyle.hairline, lineWidth: 1)
                )
        )
    }
}

private struct AdvancedMonthActionContent: View {
    let summary: PhotoMonthSummary

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PhotoDelStyle.accent.opacity(0.16))
                    .frame(width: 42, height: 42)

                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("继续清理 \(AdvancedMonthFormatter.monthTitle.string(from: summary.monthStart))"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(L10n.string("剩余 \(summary.remainingCount) 项，按时间列表继续整理"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDelStyle.tertiaryText)
        }
        .padding(14)
        .photoDelCard(radius: 16)
    }
}

private struct AdvancedCleanupEntryRow: View {
    let queue: AdvancedCleanupQueue
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(queue.kind.tint.opacity(0.17))
                    .frame(width: 38, height: 38)

                Image(systemName: queue.kind.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(queue.kind.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(queue.kind.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    if isLocked {
                        AdvancedDemoTag()
                    }
                }

                Text(L10n.string("\(queue.assetCount) 项 · \(queue.formattedSpace) · \(queue.kind.subtitle)"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer()

            Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDelStyle.tertiaryText)
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

private struct AdvancedBottomPaywall: View {
    let priceText: String
    let isLoading: Bool
    let errorMessage: String?
    let onPurchase: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Capsule(style: .continuous)
                .fill(PhotoDelStyle.hairline)
                .frame(width: 38, height: 4)
                .padding(.bottom, 4)

            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(L10n.string("解锁全部进阶功能"))
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundColor(PhotoDelStyle.primaryText)

                Text(L10n.string("查看完整清理队列，按月份、大小和相似组释放更多空间。"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button(action: onPurchase) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.black.opacity(0.86)))
                            .scaleEffect(0.78)
                    }
                    Text(isLoading ? L10n.string("处理中...") : L10n.string("解锁进阶 \(priceText)"))
                }
            }
            .photoDelPrimaryButton()
            .disabled(isLoading)

            Button(action: onRestore) {
                Text(L10n.string("恢复购买"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.accent)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDelStyle.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PhotoDelStyle.background.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct AdvancedMonthListView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let summaries: [PhotoMonthSummary]

    var body: some View {
        ZStack {
            PhotoDelScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    AdvancedFeatureHeader(
                        title: L10n.string("月份进度"),
                        subtitle: L10n.string("按月份查看照片清理比例"),
                        showsBackButton: true,
                        onBack: { dismiss() }
                    )

                    VStack(spacing: 0) {
                        ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                            NavigationLink {
                                AdvancedAssetListView(mode: .month(summary.monthStart))
                                    .environmentObject(dataManager)
                            } label: {
                                AdvancedMonthListRow(summary: summary)
                            }
                            .buttonStyle(.plain)

                            if index != summaries.count - 1 {
                                Divider()
                                    .background(PhotoDelStyle.hairline)
                                    .padding(.leading, 70)
                            }
                        }
                    }
                    .photoDelCard()

                    Spacer()
                        .frame(height: 72)
                }
                .padding(24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct AdvancedMonthListRow: View {
    let summary: PhotoMonthSummary

    var body: some View {
        HStack(spacing: 13) {
            AdvancedProgressRing(progress: summary.progress, size: 40, lineWidth: 4) {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(AdvancedMonthFormatter.fullMonth.string(from: summary.monthStart))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(L10n.string("\(summary.assetCount) 项 · 已整理 \(Int(summary.progress * 100))% · \(summary.formattedEstimatedSize)"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDelStyle.tertiaryText)
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

private struct AdvancedAssetListView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let mode: AdvancedAssetListMode

    @State private var selectedAssetIDs: Set<String> = []
    @State private var showBatchConfirm = false
    @State private var previewAsset: AdvancedPreviewAsset?

    private var assets: [PHAsset] {
        switch mode {
        case .cleanup(let kind):
            return dataManager.getPhotosForAdvancedCleanup(kind)
        case .month(let monthStart):
            return dataManager.getPhotosForMonth(monthStart)
        }
    }

    private var selectedAssets: [PHAsset] {
        assets.filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PhotoDelScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    AdvancedFeatureHeader(
                        title: mode.title,
                        subtitle: mode.subtitle,
                        showsBackButton: true,
                        onBack: { dismiss() }
                    )

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
                        .frame(height: selectedAssetIDs.isEmpty ? 86 : 146)
                }
                .padding(24)
            }

            if !selectedAssetIDs.isEmpty {
                AdvancedSelectionActionBar(
                    count: selectedAssetIDs.count,
                    action: addSelectedAssetsToDeleteCandidates
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showBatchConfirm, onDismiss: {
            selectedAssetIDs.removeAll()
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
    }

    private var summaryTitle: String {
        switch mode {
        case .cleanup(.largeFiles):
            return L10n.string("共 \(assets.count) 个大文件")
        case .cleanup(.screenshots):
            return L10n.string("共 \(assets.count) 张截图")
        case .cleanup(.videos):
            return L10n.string("共 \(assets.count) 个视频")
        case .cleanup(.similarPhotos):
            return L10n.string("共 \(assets.count) 张相似照片")
        case .month:
            return L10n.string("共 \(assets.count) 项")
        }
    }

    private var summarySubtitle: String {
        let totalSize = assets.reduce(0) { $0 + dataManager.estimatedSizeMB(for: $1) }
        switch mode {
        case .cleanup(.largeFiles):
            return L10n.string("按占用空间从大到小排序，合计约 \(CleanupStatsFormatter.space(totalSize))。")
        case .cleanup(.screenshots):
            return L10n.string("像相册一样浏览截图，合计约 \(CleanupStatsFormatter.space(totalSize))。")
        case .cleanup(.videos):
            return L10n.string("按视频占用优先处理，合计约 \(CleanupStatsFormatter.space(totalSize))。")
        case .cleanup(.similarPhotos):
            return L10n.string("建议优先处理相似组，合计约 \(CleanupStatsFormatter.space(totalSize))。")
        case .month:
            return L10n.string("按时间浏览这个月份，合计约 \(CleanupStatsFormatter.space(totalSize))。")
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

private struct AdvancedSimilarPhotoGroupsView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAssetIDs: Set<String> = []
    @State private var showBatchConfirm = false
    @State private var previewAsset: AdvancedPreviewAsset?

    private var groups: [AdvancedSimilarPhotoGroup] {
        dataManager.makeSimilarPhotoGroups(maxGroups: 80)
    }

    private var selectedAssets: [PHAsset] {
        groups.flatMap(\.assets).filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PhotoDelScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    AdvancedFeatureHeader(
                        title: L10n.string("相似照片"),
                        subtitle: L10n.string("按相似组整理，保留最好的一张"),
                        showsBackButton: true,
                        onBack: { dismiss() }
                    )

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
                        .frame(height: selectedAssetIDs.isEmpty ? 86 : 146)
                }
                .padding(24)
            }

            if !selectedAssetIDs.isEmpty {
                AdvancedSelectionActionBar(
                    count: selectedAssetIDs.count,
                    action: addSelectedAssetsToDeleteCandidates
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showBatchConfirm, onDismiss: {
            selectedAssetIDs.removeAll()
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
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text(L10n.string("\(group.assets.count) 张相似 · 可节省 \(group.formattedEstimatedSpace)"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                }

                Spacer()

                Button(action: onSelectRecommended) {
                    Text(L10n.string("建议保留 1 张"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.positive)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(PhotoDelStyle.positive.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
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
        }
        .padding(14)
        .photoDelCard(radius: 16)
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
                    .foregroundColor(PhotoDelStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.86))
                    .padding(.horizontal, 15)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(PhotoDelStyle.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .photoDelCard(radius: 16)
    }
}

private struct AdvancedAssetRow: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let estimatedSizeMB: Double
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onPreview: () -> Void

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

            VStack(alignment: .leading, spacing: 4) {
                Text(AdvancedAssetFormatter.title(for: asset, photoLibraryManager: photoLibraryManager))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                    .lineLimit(1)

                Text(AdvancedAssetFormatter.metadata(for: asset, photoLibraryManager: photoLibraryManager))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Text(CleanupStatsFormatter.space(estimatedSizeMB))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.positive)
                    .lineLimit(1)

                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isSelected ? PhotoDelStyle.accent : PhotoDelStyle.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? L10n.string("取消选择") : L10n.string("选择"))
            }
        }
        .padding(10)
        .photoDelCard(radius: 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleSelection)
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

            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? PhotoDelStyle.accent : Color.white.opacity(0.84))
                    .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 2)
                    .padding(4)
            }
            .buttonStyle(.plain)

            if showsRecommendedBadge {
                Text(L10n.string("保留"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.black.opacity(0.82))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(PhotoDelStyle.positive))
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
                        .fill(PhotoDelStyle.elevatedSurface)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(PhotoDelStyle.secondaryText)
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
                    .background(Circle().fill(PhotoDelStyle.background.opacity(0.72)))
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
                    PhotoDelStyle.background.ignoresSafeArea()

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDelStyle.accent))
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 36, weight: .medium))
                                    .foregroundColor(PhotoDelStyle.secondaryText)
                            }

                            Text(isLoading ? L10n.string("正在读取照片") : L10n.string("无法读取这张照片"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                        }
                    }
                }
                .onAppear {
                    loadImage(in: geometry.size)
                }
            }
            .navigationTitle(L10n.string("照片预览"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("关闭")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDelStyle.accent)
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
            .foregroundColor(Color.black.opacity(0.86))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PhotoDelStyle.accent)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(
            PhotoDelStyle.background.opacity(0.92)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct AdvancedFilterPills: View {
    let kind: AdvancedCleanupKind

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    Text(filter)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(filter == filters.first ? PhotoDelStyle.accent : PhotoDelStyle.secondaryText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(filter == filters.first ? PhotoDelStyle.accent.opacity(0.15) : PhotoDelStyle.surface)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(filter == filters.first ? PhotoDelStyle.accent.opacity(0.38) : PhotoDelStyle.hairline, lineWidth: 1)
                                )
                        )
                }
            }
        }
    }

    private var filters: [String] {
        switch kind {
        case .similarPhotos:
            return [L10n.string("推荐"), L10n.string("连拍"), L10n.string("截图"), L10n.string("本月")]
        case .largeFiles:
            return [L10n.string("全部"), L10n.string("视频"), L10n.string("图片"), L10n.string("本月")]
        case .screenshots:
            return [L10n.string("全部"), L10n.string("本月"), L10n.string("较旧"), L10n.string("已选")]
        case .videos:
            return [L10n.string("全部"), L10n.string("大文件"), L10n.string("较长"), L10n.string("本月")]
        }
    }
}

private struct AdvancedFeatureHeader: View {
    let title: String
    let subtitle: String
    var showsBackButton = false
    var onBack: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsBackButton {
                Button(action: { onBack?() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(PhotoDelStyle.elevatedSurface))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer()
        }
    }
}

private struct AdvancedProgressRing<Content: View>: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(PhotoDelStyle.elevatedSurface, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    PhotoDelStyle.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            content()
        }
        .frame(width: size, height: size)
    }
}

private struct AdvancedDemoTag: View {
    var body: some View {
        Text(L10n.string("示例"))
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(PhotoDelStyle.warning)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(PhotoDelStyle.warning.opacity(0.14))
            )
    }
}

private struct AdvancedEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(PhotoDelStyle.secondaryText)

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .photoDelCard(radius: 16)
    }
}

private enum AdvancedAssetListMode {
    case cleanup(AdvancedCleanupKind)
    case month(Date)

    var title: String {
        switch self {
        case .cleanup(let kind):
            return kind.title
        case .month(let monthStart):
            return AdvancedMonthFormatter.fullMonth.string(from: monthStart)
        }
    }

    var subtitle: String {
        switch self {
        case .cleanup(.largeFiles):
            return L10n.string("按占用空间从大到小排序")
        case .cleanup(.screenshots):
            return L10n.string("像相册一样浏览并批量选择")
        case .cleanup(.videos):
            return L10n.string("按视频占用和时间整理")
        case .cleanup(.similarPhotos):
            return L10n.string("按相似组整理，保留最好的一张")
        case .month:
            return L10n.string("按时间浏览这个月份的照片")
        }
    }

    var icon: String {
        switch self {
        case .cleanup(let kind):
            return kind.icon
        case .month:
            return "calendar"
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

private enum AdvancedMonthFormatter {
    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M月")
        return formatter
    }()

    static let shortMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M月")
        return formatter
    }()

    static let fullMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("y年M月")
        return formatter
    }()
}

#Preview {
    AdvancedView()
        .environmentObject(DataManager())
        .environmentObject(PurchaseManager())
}
