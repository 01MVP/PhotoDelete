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
    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()

    private var isLocked: Bool {
        !purchaseManager.isSupporter
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDelScreenBackground()

                ScrollView(showsIndicators: false) {
                    let snapshot = isLocked ?
                        AdvancedLibrarySnapshot.demo(referenceDate: displayedMonth) :
                        dataManager.makeAdvancedLibrarySnapshot(referenceDate: displayedMonth)

                    VStack(spacing: 20) {
                        header

                        if isLocked {
                            AdvancedPaywallCard(
                                priceText: purchaseManager.supporterPriceText,
                                isLoading: purchaseManager.isLoading,
                                errorMessage: purchaseManager.errorMessage,
                                onPurchase: purchaseSupporter,
                                onRestore: restorePurchases
                            )
                        } else if !dataManager.photoLibraryManager.hasPhotoLibraryAccess {
                            PhotoAuthorizationCard(
                                subtitle: L10n.string("进阶功能需要读取本机照片库，才能生成真实日历和清理队列。"),
                                onRequestAccess: { dataManager.requestPhotoLibraryAccess() }
                            )
                        }

                        AdvancedStatsStrip(stats: snapshot.stats, isDemo: isLocked)

                        AdvancedStorageCard(
                            storage: snapshot.stats.storageSnapshot,
                            isDemo: isLocked
                        )

                        AdvancedCalendarCard(
                            summaries: snapshot.daySummaries,
                            displayedMonth: $displayedMonth,
                            selectedDate: $selectedDate,
                            isDemo: isLocked,
                            onMoveMonth: moveDisplayedMonth
                        )

                        selectedDayCard(
                            snapshot: snapshot,
                            isDemo: isLocked
                        )

                        cleanupSection(
                            queues: snapshot.cleanupQueues,
                            isDemo: isLocked
                        )

                        AdvancedAchievementSection(
                            stats: snapshot.stats,
                            activeDays: snapshot.daySummaries.count,
                            isDemo: isLocked
                        )

                        Spacer()
                            .frame(height: 96)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
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
                Text(L10n.string("进阶"))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(isLocked ? L10n.string("先用示例数据看看解锁后的效果") : L10n.string("用日期和空间视角整理照片"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
            }

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: isLocked ? "lock.fill" : "seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(isLocked ? L10n.string("示例") : L10n.string("已解锁"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isLocked ? PhotoDelStyle.warning : PhotoDelStyle.positive)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(PhotoDelStyle.surface)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke((isLocked ? PhotoDelStyle.warning : PhotoDelStyle.positive).opacity(0.32), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func selectedDayCard(
        snapshot: AdvancedLibrarySnapshot,
        isDemo: Bool
    ) -> some View {
        let summary = selectedSummary(in: snapshot.daySummaries)
        let photoCount = summary?.photoCount ?? 0

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AdvancedDateFormatters.dayTitle.string(from: selectedDate))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text(isDemo ? L10n.string("示例日期详情") : L10n.string("点击整理会直接进入这一天的照片"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(PhotoDelStyle.tertiaryText)
                }

                Spacer()

                Text(L10n.shortPhotoCount(photoCount))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.accent)
            }

            HStack(spacing: 10) {
                AdvancedDayMetric(icon: "photo", title: L10n.string("照片"), value: "\(summary?.photoCount ?? 0)", tint: PhotoDelStyle.accent)
                AdvancedDayMetric(icon: "iphone", title: L10n.string("截图"), value: "\(summary?.screenshotCount ?? 0)", tint: PhotoDelStyle.positive)
                AdvancedDayMetric(icon: "video", title: L10n.string("视频"), value: "\(summary?.videoCount ?? 0)", tint: PhotoDelStyle.iconTint(for: "video"))
                AdvancedDayMetric(icon: "internaldrive", title: L10n.string("占用"), value: summary?.formattedEstimatedSize ?? "0 MB", tint: PhotoDelStyle.warning)
            }

            if isDemo {
                Button(action: purchaseSupporter) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open")
                        Text(L10n.string("解锁后整理这一天"))
                    }
                }
                .photoDelPrimaryButton()
            } else {
                NavigationLink {
                    SwipePhotoView(
                        selectedCategory: nil,
                        selectedTimeGroup: nil,
                        selectedAlbumInfo: nil,
                        selectedDate: selectedDate,
                        selectedAdvancedCleanup: nil
                    )
                    .environmentObject(dataManager)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.checkmark")
                        Text(L10n.string("整理这一天"))
                    }
                }
                .photoDelPrimaryButton()
                .disabled(photoCount == 0)
            }
        }
        .padding(18)
        .photoDelCard()
    }

    private func cleanupSection(
        queues: [AdvancedCleanupQueue],
        isDemo: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.string("智能清理"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                Spacer()
                Text(isDemo ? L10n.string("示例") : L10n.string("按优先级"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(queues, id: \.id) { queue in
                    if isDemo {
                        Button(action: purchaseSupporter) {
                            AdvancedCleanupTile(queue: queue, isDemo: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            SwipePhotoView(
                                selectedCategory: nil,
                                selectedTimeGroup: nil,
                                selectedAlbumInfo: nil,
                                selectedDate: nil,
                                selectedAdvancedCleanup: queue.kind
                            )
                            .environmentObject(dataManager)
                        } label: {
                            AdvancedCleanupTile(queue: queue, isDemo: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func selectedSummary(in summaries: [PhotoDaySummary]) -> PhotoDaySummary? {
        summaries.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private func moveDisplayedMonth(by value: Int) {
        guard let nextMonth = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = nextMonth
        selectedDate = Calendar.current.dateInterval(of: .month, for: nextMonth)?.start ?? nextMonth
    }

    private func purchaseSupporter() {
        Task { await purchaseManager.purchaseSupporter() }
    }

    private func restorePurchases() {
        Task { await purchaseManager.restorePurchases() }
    }
}

private struct AdvancedPaywallCard: View {
    let priceText: String
    let isLoading: Bool
    let errorMessage: String?
    let onPurchase: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PhotoDelStyle.accent.opacity(0.16))
                        .frame(width: 52, height: 52)

                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("进阶功能预览"))
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text(L10n.string("当前显示示例数据。解锁后会切换为你的真实照片活动、清理队列和长期统计。"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 10) {
                Button(action: onPurchase) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color.black.opacity(0.86)))
                                .scaleEffect(0.78)
                        }
                        Text(isLoading ? L10n.string("处理中...") : L10n.string("解锁进阶功能 \(priceText)"))
                    }
                }
                .photoDelPrimaryButton()
                .disabled(isLoading)

                Button(action: onRestore) {
                    Text(L10n.string("恢复购买"))
                }
                .photoDelSecondaryButton()
                .disabled(isLoading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDelStyle.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .photoDelCard()
    }
}

private struct AdvancedStatsStrip: View {
    let stats: AdvancedLibraryStats
    let isDemo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.string("统计概览"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                Spacer()
                if isDemo {
                    Text(L10n.string("示例"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.warning)
                }
            }

            HStack(spacing: 8) {
                AdvancedMiniStat(value: "\(stats.totalAssets)", label: L10n.string("图片"), tint: PhotoDelStyle.accent)
                AdvancedMiniStat(value: "\(stats.organizedAssets)", label: L10n.string("已整理"), tint: PhotoDelStyle.positive)
                AdvancedMiniStat(value: "\(stats.deletedAssets)", label: L10n.string("已删除"), tint: PhotoDelStyle.destructive)
                AdvancedMiniStat(value: stats.formattedSpaceSaved, label: L10n.string("节省"), tint: PhotoDelStyle.warning)
            }
        }
        .padding(18)
        .photoDelCard()
    }
}

private struct AdvancedMiniStat: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PhotoDelStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PhotoDelStyle.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.22), lineWidth: 1)
                )
        )
    }
}

private struct AdvancedStorageCard: View {
    let storage: DeviceStorageSnapshot
    let isDemo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.string("手机存储空间"), systemImage: "internaldrive")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Spacer()

                Text("\(Int(storage.usedFraction * 100))%")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.accent)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(PhotoDelStyle.elevatedSurface)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [PhotoDelStyle.accent, PhotoDelStyle.positive, PhotoDelStyle.warning],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geometry.size.width * storage.usedFraction, 8))
                }
            }
            .frame(height: 10)

            HStack {
                Text(L10n.string("已用 \(storage.formattedUsed) / \(storage.formattedTotal)"))
                Spacer()
                Text(L10n.string("可用 \(storage.formattedFree)"))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(PhotoDelStyle.secondaryText)
        }
        .padding(18)
        .photoDelCard()
    }
}

private struct AdvancedCalendarCard: View {
    let summaries: [PhotoDaySummary]
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date
    let isDemo: Bool
    let onMoveMonth: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("照片活动"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text(AdvancedDateFormatters.monthTitle.string(from: displayedMonth))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: { onMoveMonth(-1) }) {
                        Image(systemName: "chevron.left")
                    }
                    Button(action: { onMoveMonth(1) }) {
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                AdvancedScopePill(title: L10n.string("月视图"), isSelected: true)
                Spacer()
                if isDemo {
                    Text(L10n.string("示例"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.warning)
                }
            }

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PhotoDelStyle.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(calendarDays) { day in
                    AdvancedCalendarDayCell(
                        day: day,
                        summary: summary(for: day.date),
                        maxPhotoCount: maxPhotoCount,
                        isSelected: isSelected(day.date)
                    ) {
                        if let date = day.date {
                            selectedDate = date
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text(L10n.string("少"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(AdvancedHeatColor.color(for: Double(index) / 4))
                        .frame(width: 14, height: 8)
                }
                Text(L10n.string("多"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .photoDelCard()
    }

    private var maxPhotoCount: Int {
        max(summaries.map(\.photoCount).max() ?? 0, 1)
    }

    private var summaryMap: [Date: PhotoDaySummary] {
        Dictionary(uniqueKeysWithValues: summaries.map {
            (Calendar.current.startOfDay(for: $0.date), $0)
        })
    }

    private func summary(for date: Date?) -> PhotoDaySummary? {
        guard let date else { return nil }
        return summaryMap[Calendar.current.startOfDay(for: date)]
    }

    private func isSelected(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var calendarDays: [AdvancedCalendarDay] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingBlankCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days = (0..<leadingBlankCount).map { AdvancedCalendarDay.placeholder(index: $0) }

        for day in dayRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) else { continue }
            days.append(AdvancedCalendarDay(date: date))
        }

        while days.count % 7 != 0 {
            days.append(.placeholder(index: days.count))
        }

        return days
    }
}

private struct AdvancedCalendarDay: Identifiable {
    let id: String
    let date: Date?

    init(date: Date) {
        self.date = date
        self.id = "day-\(date.timeIntervalSinceReferenceDate)"
    }

    private init(id: String) {
        self.id = id
        self.date = nil
    }

    static func placeholder(index: Int) -> AdvancedCalendarDay {
        AdvancedCalendarDay(id: "blank-\(index)")
    }
}

private struct AdvancedCalendarDayCell: View {
    let day: AdvancedCalendarDay
    let summary: PhotoDaySummary?
    let maxPhotoCount: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isSelected ? PhotoDelStyle.accent : PhotoDelStyle.hairline, lineWidth: isSelected ? 1.5 : 1)
                    )

                if let date = day.date {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(day.date == nil)
        .accessibilityLabel(accessibilityLabel)
    }

    private var fillColor: Color {
        guard let summary, summary.photoCount > 0 else {
            return day.date == nil ? Color.clear : PhotoDelStyle.elevatedSurface.opacity(0.82)
        }
        let intensity = min(Double(summary.photoCount) / Double(maxPhotoCount), 1)
        return AdvancedHeatColor.color(for: intensity)
    }

    private var textColor: Color {
        guard let summary, summary.photoCount > 0 else {
            return PhotoDelStyle.secondaryText
        }
        return summary.photoCount > maxPhotoCount / 2 ? Color.black.opacity(0.78) : PhotoDelStyle.primaryText
    }

    private var accessibilityLabel: Text {
        guard let date = day.date else { return Text("") }
        if let summary {
            return Text(L10n.string("\(AdvancedDateFormatters.dayTitle.string(from: date))，\(summary.photoCount) 张照片"))
        }
        return Text(AdvancedDateFormatters.dayTitle.string(from: date))
    }
}

private enum AdvancedHeatColor {
    static func color(for intensity: Double) -> Color {
        switch intensity {
        case 0:
            return PhotoDelStyle.elevatedSurface
        case 0..<0.26:
            return PhotoDelStyle.accent.opacity(0.42)
        case 0.26..<0.5:
            return PhotoDelStyle.positive.opacity(0.62)
        case 0.5..<0.75:
            return PhotoDelStyle.warning.opacity(0.74)
        default:
            return Color(red: 1.0, green: 0.58, blue: 0.68).opacity(0.86)
        }
    }
}

private struct AdvancedScopePill: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isSelected ? Color.black.opacity(0.82) : PhotoDelStyle.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? PhotoDelStyle.accent : PhotoDelStyle.elevatedSurface)
            )
    }
}

private struct AdvancedDayMetric: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PhotoDelStyle.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PhotoDelStyle.elevatedSurface)
        )
    }
}

private struct AdvancedCleanupTile: View {
    let queue: AdvancedCleanupQueue
    let isDemo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(queue.kind.tint.opacity(0.17))
                        .frame(width: 38, height: 38)

                    Image(systemName: queue.kind.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(queue.kind.tint)
                }

                Spacer()

                Image(systemName: isDemo ? "lock.fill" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(queue.kind.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(queue.kind.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }

            HStack(alignment: .lastTextBaseline) {
                Text("\(queue.assetCount)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(queue.kind.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(L10n.string("项"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDelStyle.tertiaryText)

                Spacer()
            }

            Text(queue.formattedSpace)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDelStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
        .padding(14)
        .photoDelCard(radius: 16)
    }
}

private struct AdvancedAchievementSection: View {
    let stats: AdvancedLibraryStats
    let activeDays: Int
    let isDemo: Bool

    private var progress: Double {
        guard stats.totalAssets > 0 else { return 0 }
        return min(Double(stats.organizedAssets) / Double(stats.totalAssets), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.string("整理进度"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                Spacer()
                if isDemo {
                    Text(L10n.string("示例"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.warning)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(L10n.string("照片库进度"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.positive)
                }

                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDelStyle.positive))
                    .clipShape(Capsule(style: .continuous))
            }

            HStack(spacing: 10) {
                AdvancedAchievementChip(icon: "calendar", title: L10n.string("本月活跃"), value: L10n.string("\(activeDays) 天"), tint: PhotoDelStyle.accent)
                AdvancedAchievementChip(icon: "checkmark.seal", title: L10n.string("已整理"), value: "\(stats.organizedAssets)", tint: PhotoDelStyle.positive)
                AdvancedAchievementChip(icon: "trash", title: L10n.string("已清理"), value: "\(stats.deletedAssets)", tint: PhotoDelStyle.destructive)
            }
        }
        .padding(18)
        .photoDelCard()
    }
}

private struct AdvancedAchievementChip: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PhotoDelStyle.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PhotoDelStyle.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private enum AdvancedDateFormatters {
    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter
    }()

    static let dayTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMEd")
        return formatter
    }()
}

#Preview {
    AdvancedView()
        .environmentObject(DataManager())
        .environmentObject(PurchaseManager())
}
