//
//  SupporterView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI

struct SupporterView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppConstants.supporterThemeKey) private var selectedThemeID = SupporterTheme.sky.rawValue

    private var selectedTheme: SupporterTheme {
        SupporterTheme(rawValue: selectedThemeID) ?? .sky
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDelScreenBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        if purchaseManager.isSupporter {
                            SupporterUnlockedContent(
                                statsStore: dataManager.cleanupStatsStore,
                                selectedThemeID: $selectedThemeID,
                                theme: selectedTheme
                            )
                        } else {
                            SupporterPaywallContent(
                                priceText: purchaseManager.supporterPriceText,
                                isLoading: purchaseManager.isLoading,
                                errorMessage: purchaseManager.errorMessage,
                                onPurchase: {
                                    Task { await purchaseManager.purchaseSupporter() }
                                },
                                onRestore: {
                                    Task { await purchaseManager.restorePurchases() }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(L10n.string("支持者版"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDelStyle.secondaryText)
                }
            }
        }
        .task {
            await purchaseManager.loadProducts()
            await purchaseManager.refreshEntitlements()
        }
    }
}

private struct SupporterPaywallContent: View {
    let priceText: String
    let isLoading: Bool
    let errorMessage: String?
    let onPurchase: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(PhotoDelStyle.elevatedSurface)
                        .frame(width: 70, height: 70)

                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.accent)
                }

                VStack(spacing: 8) {
                    Text(L10n.string("PhotoDel 支持者版"))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text(L10n.string("基础清理功能始终免费。支持者版解锁长期统计，并支持 PhotoDel 继续维护。"))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .padding(24)
            .photoDelCard()

            VStack(spacing: 0) {
                SupporterBenefitRow(icon: "chart.bar.xaxis", title: L10n.string("长期清理统计"), detail: L10n.string("累计整理、删除和节省空间"))
                SupporterDivider()
                SupporterBenefitRow(icon: "calendar", title: L10n.string("月度统计"), detail: L10n.string("按月份查看清理成果"))
                SupporterDivider()
                SupporterBenefitRow(icon: "clock.arrow.circlepath", title: L10n.string("清理历史"), detail: L10n.string("每次确认后的本机记录"))
                SupporterDivider()
                SupporterBenefitRow(icon: "seal.fill", title: L10n.string("支持者徽章与主题色"), detail: L10n.string("给自己的整理报告一点个人标记"))
            }
            .photoDelCard()

            VStack(spacing: 12) {
                Button(action: onPurchase) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color.black.opacity(0.86)))
                                .scaleEffect(0.82)
                        }
                        Text(isLoading ? L10n.string("处理中...") : L10n.string("永久解锁 \(priceText)"))
                    }
                }
                .photoDelPrimaryButton()
                .disabled(isLoading)

                Button(action: onRestore) {
                    Text(L10n.string("恢复购买"))
                }
                .photoDelSecondaryButton()
                .disabled(isLoading)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(PhotoDelStyle.warning)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

private struct SupporterUnlockedContent: View {
    @ObservedObject var statsStore: CleanupStatsStore
    @Binding var selectedThemeID: String
    let theme: SupporterTheme
    @State private var showingClearConfirmation = false

    private var summary: CleanupStatsSummary {
        statsStore.summary
    }

    var body: some View {
        VStack(spacing: 20) {
            SupporterBadgeCard(theme: theme)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SupporterMetricCard(value: "\(summary.organizedPhotos)", label: L10n.string("累计整理"), tint: theme.color)
                SupporterMetricCard(value: "\(summary.deletedPhotos)", label: L10n.string("累计删除"), tint: PhotoDelStyle.destructive)
                SupporterMetricCard(value: summary.formattedSpaceSaved, label: L10n.string("估算节省"), tint: PhotoDelStyle.positive)
                SupporterMetricCard(value: "\(summary.sessions)", label: L10n.string("清理次数"), tint: PhotoDelStyle.accent)
            }

            SupporterThemeSection(selectedThemeID: $selectedThemeID)

            SupporterMonthlySection(summaries: statsStore.monthlySummaries)

            SupporterHistorySection(sessions: Array(statsStore.sessions.prefix(20)))

            Button(role: .destructive) {
                showingClearConfirmation = true
            } label: {
                Text(L10n.string("清空统计记录"))
                    .frame(maxWidth: .infinity)
            }
            .photoDelSecondaryButton()
        }
        .confirmationDialog(L10n.string("清空本机统计记录？"), isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button(L10n.string("清空统计记录"), role: .destructive) {
                statsStore.clearAll()
            }
            Button(L10n.string("取消"), role: .cancel) {}
        } message: {
            Text(L10n.string("只会清空 PhotoDel 的本机统计，不会影响照片。"))
        }
    }
}

private struct SupporterBadgeCard: View {
    let theme: SupporterTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(theme.color.opacity(0.18))
                        .frame(width: 54, height: 54)

                    Image(systemName: "seal.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(theme.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("支持者版已解锁"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text(L10n.string("谢谢你支持这个免费的小工具继续维护。"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .photoDelCard()
    }
}

private struct SupporterMetricCard: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(PhotoDelStyle.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .photoDelCard(radius: 16)
    }
}

private struct SupporterThemeSection: View {
    @Binding var selectedThemeID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("主题色"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)

            HStack(spacing: 12) {
                ForEach(SupporterTheme.allCases) { theme in
                    Button {
                        selectedThemeID = theme.rawValue
                        HapticManager.impact(.light)
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(PhotoDelStyle.primaryText.opacity(selectedThemeID == theme.rawValue ? 0.9 : 0), lineWidth: 2)
                                )

                            Text(theme.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .photoDelCard()
    }
}

private struct SupporterMonthlySection: View {
    let summaries: [CleanupMonthlySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("月度统计"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)

            if summaries.isEmpty {
                SupporterEmptyText(L10n.string("完成一次整理后，这里会出现月度记录。"))
            } else {
                VStack(spacing: 0) {
                    ForEach(summaries.prefix(6)) { summary in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(summary.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(PhotoDelStyle.primaryText)

                                Text(L10n.string("\(summary.sessions) 次 · 整理 \(summary.organizedPhotos) 张"))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(PhotoDelStyle.secondaryText)
                            }

                            Spacer()

                            Text(summary.formattedSpaceSaved)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.positive)
                        }
                        .padding(.vertical, 12)

                        if summary.id != summaries.prefix(6).last?.id {
                            SupporterDivider()
                        }
                    }
                }
            }
        }
        .padding(18)
        .photoDelCard()
    }
}

private struct SupporterHistorySection: View {
    let sessions: [CleanupSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("清理历史"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)

            if sessions.isEmpty {
                SupporterEmptyText(L10n.string("确认删除或收藏后，会在本机留下清理记录。"))
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.positive)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.formattedDate)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(PhotoDelStyle.primaryText)

                                Text(L10n.string("删除 \(session.deletedPhotos) 张 · 收藏 \(session.favoritedPhotos) 张"))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(PhotoDelStyle.secondaryText)
                            }

                            Spacer()

                            Text(session.formattedSpaceSaved)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.positive)
                        }
                        .padding(.vertical, 12)

                        if session.id != sessions.last?.id {
                            SupporterDivider()
                        }
                    }
                }
            }
        }
        .padding(18)
        .photoDelCard()
    }
}

private struct SupporterBenefitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PhotoDelStyle.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(detail)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
            }

            Spacer()
        }
        .padding(16)
    }
}

private struct SupporterDivider: View {
    var body: some View {
        Divider()
            .background(PhotoDelStyle.hairline)
            .padding(.leading, 16)
    }
}

private struct SupporterEmptyText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(PhotoDelStyle.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

enum SupporterTheme: String, CaseIterable, Identifiable {
    case sky
    case mint
    case rose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sky: return L10n.string("天蓝")
        case .mint: return L10n.string("薄荷")
        case .rose: return L10n.string("玫瑰")
        }
    }

    var color: Color {
        switch self {
        case .sky: return PhotoDelStyle.accent
        case .mint: return PhotoDelStyle.positive
        case .rose: return PhotoDelStyle.iconTint(for: "favorite")
        }
    }
}

#Preview {
    SupporterView()
        .environmentObject(DataManager())
        .environmentObject(PurchaseManager())
}
