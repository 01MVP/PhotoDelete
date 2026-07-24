//
//  SupporterView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import StoreKit
import SwiftUI

struct SupporterView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingOfferCodeRedemption = false
    @State private var selectedPlan: SupporterPurchasePlan = .annual

    private var entitlementStatusMessage: String? {
        switch purchaseManager.entitlementState {
        case .verifying:
            L10n.string("正在检查购买状态...")
        case .cachedOffline:
            L10n.string("离线时仍可使用已解锁的支持者版，联网后会自动确认状态。")
        case .unknown, .verified, .locked:
            nil
        }
    }

    private var showsBottomActionBar: Bool {
        !purchaseManager.hasPaidSupporterAccess
    }

    private var contentBottomPadding: CGFloat {
        showsBottomActionBar ? 300 : 40
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        if purchaseManager.hasPaidSupporterAccess {
                            SupporterUnlockedContent(
                                purchaseDate: purchaseManager.supporterPurchaseDate,
                                expirationDate: purchaseManager.supporterExpirationDate,
                                accessKind: purchaseManager.supporterAccessKind,
                                accessNotice: purchaseManager.isUsingCachedSupporterAccess ? entitlementStatusMessage : nil
                            )
                        } else if purchaseManager.isUsingTrialSupporterAccess {
                            SupporterTrialContent(
                                remainingDays: purchaseManager.supporterTrialDaysRemaining
                            )
                        } else {
                            SupporterPaywallContent(
                                canStartTrial: purchaseManager.canStartSupporterTrial
                            )
                        }
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, contentBottomPadding)
                    .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                    .frame(maxWidth: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsBottomActionBar {
                    SupporterBottomActionBar(
                        isTrialActive: purchaseManager.isUsingTrialSupporterAccess,
                        canStartTrial: purchaseManager.canStartSupporterTrial,
                        selectedPlan: $selectedPlan,
                        annualPriceText: purchaseManager.supporterAnnualPriceText,
                        lifetimePriceText: purchaseManager.supporterLifetimePriceText,
                        isLoading: purchaseManager.isLoading,
                        statusMessage: purchaseManager.supporterTrialStatusText ?? entitlementStatusMessage,
                        errorMessage: purchaseManager.errorMessage,
                        onStartTrial: {
                            purchaseManager.startSupporterTrial()
                        },
                        onPurchase: {
                            Task { await purchaseManager.purchaseSupporter(plan: selectedPlan) }
                        },
                        onRestore: {
                            Task { await purchaseManager.restorePurchases() }
                        },
                        onRedeemCode: {
                            showingOfferCodeRedemption = true
                        }
                    )
                }
            }
            .navigationTitle(L10n.string("OnePhoto Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                }
            }
        }
        .task {
            await purchaseManager.activateStoreKit()
        }
        .offerCodeRedemption(isPresented: $showingOfferCodeRedemption) { result in
            purchaseManager.handleOfferCodeRedemptionCompletion(result)
        }
    }
}

private struct SupporterTrialContent: View {
    let remainingDays: Int

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(PhotoDeleteStyle.elevatedSurface)
                        .frame(width: 70, height: 70)

                    Image(systemName: "timer")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.accent)
                }

                VStack(spacing: 8) {
                    Text(L10n.string("3 天免费体验中"))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(String(format: L10n.string("还剩 %lld 天。试用期间可使用进阶清理、长期统计和主题切换。"), remainingDays))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .padding(24)
            .photoDeleteCard()

            SupporterPlanComparisonCard()
        }
    }
}

private struct SupporterPaywallContent: View {
    let canStartTrial: Bool

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(PhotoDeleteStyle.elevatedSurface)
                        .frame(width: 70, height: 70)

                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.accent)
                }

                VStack(spacing: 8) {
                    Text(L10n.string("OnePhoto Pro"))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(heroSubtitle)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .padding(24)
            .photoDeleteCard()

            SupporterPlanComparisonCard()
        }
    }

    private var heroSubtitle: String {
        if canStartTrial {
            return L10n.string("免费体验 3 天进阶功能，之后可选择年度 Pro 或永久 Pro。")
        }

        return L10n.string("年度 Pro 和永久 Pro 均可解锁完整时间列表、压缩、相似照片清理和主题切换。")
    }
}

private struct SupporterBottomActionBar: View {
    let isTrialActive: Bool
    let canStartTrial: Bool
    @Binding var selectedPlan: SupporterPurchasePlan
    let annualPriceText: String
    let lifetimePriceText: String
    let isLoading: Bool
    let statusMessage: String?
    let errorMessage: String?
    let onStartTrial: () -> Void
    let onPurchase: () -> Void
    let onRestore: () -> Void
    let onRedeemCode: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            Capsule(style: .continuous)
                .fill(PhotoDeleteStyle.hairline)
                .frame(width: 38, height: 4)
                .padding(.bottom, 2)

            HStack(spacing: 10) {
                planButton(
                    plan: .annual,
                    title: L10n.string("年度 Pro"),
                    price: annualPriceText,
                    detail: L10n.string("每年 · 自动续订")
                )
                planButton(
                    plan: .lifetime,
                    title: L10n.string("永久 Pro"),
                    price: lifetimePriceText,
                    detail: L10n.string("一次购买 · 永久使用")
                )
            }

            if isTrialActive {
                purchaseButton(style: .primary)
            } else if canStartTrial {
                Button(action: onStartTrial) {
                    Label(L10n.string("开始 3 天免费体验"), systemImage: "timer")
                        .labelStyle(.titleAndIcon)
                }
                .photoDeletePrimaryButton()
                .disabled(isLoading)

                purchaseButton(style: .secondary)
            } else {
                purchaseButton(style: .primary)
            }

            SupporterPurchaseAuxiliaryActionsRow(
                isLoading: isLoading,
                onRestore: onRestore,
                onRedeemCode: onRedeemCode
            )

            Text(billingDisclosure)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            SupporterLegalLinksRow()

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
        .padding(.top, 14)
        .padding(.bottom, 18)
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

    @ViewBuilder
    private func purchaseButton(style: PurchaseButtonStyle) -> some View {
        let loadingTint: Color = style == .primary ? PhotoDeleteStyle.primaryButtonText : PhotoDeleteStyle.accent

        Button(action: onPurchase) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: loadingTint))
                        .scaleEffect(0.78)
                }
                Text(isLoading ? L10n.string("处理中...") : purchaseButtonTitle)
            }
        }
        .modifier(PurchaseButtonModifier(style: style))
        .disabled(isLoading)
    }

    private var purchaseButtonTitle: String {
        switch selectedPlan {
        case .annual:
            String(format: L10n.string("开通年度 Pro %@/年"), annualPriceText)
        case .lifetime:
            String(format: L10n.string("解锁永久 Pro %@"), lifetimePriceText)
        }
    }

    private var billingDisclosure: String {
        if isTrialActive || canStartTrial {
            return L10n.string("3 天体验到期不会扣费；年度 Pro 会自动续订，可随时在 Apple ID 设置中取消。基础整理始终免费。")
        }

        return String(
            format: L10n.string("年度 Pro 为 %@/年；确认购买后开始计费并自动续订，可随时在 Apple ID 设置中取消。永久 Pro 为一次购买。基础整理始终免费。"),
            annualPriceText
        )
    }

    private func planButton(
        plan: SupporterPurchasePlan,
        title: String,
        price: String,
        detail: String
    ) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(isSelected ? PhotoDeleteStyle.accent : PhotoDeleteStyle.primaryText)

                Text(price)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(detail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? PhotoDeleteStyle.accent.opacity(0.1) : PhotoDeleteStyle.elevatedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? PhotoDeleteStyle.accent : PhotoDeleteStyle.hairline, lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel("\(title)，\(price)，\(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SupporterPurchaseAuxiliaryActionsRow: View {
    let isLoading: Bool
    let onRestore: () -> Void
    let onRedeemCode: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            auxiliaryButton(
                title: L10n.string("恢复购买"),
                systemImage: "arrow.clockwise",
                action: onRestore
            )

            if #available(iOS 16.3, *) {
                Rectangle()
                    .fill(PhotoDeleteStyle.hairline)
                    .frame(width: 1, height: 14)

                auxiliaryButton(
                    title: L10n.string("兑换代码"),
                    systemImage: "ticket",
                    action: onRedeemCode
                )
            }
        }
    }

    private func auxiliaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct SupporterLegalLinksRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Link(L10n.string("隐私政策"), destination: AppConstants.privacyPolicyURL)
                .accessibilityIdentifier("supporter-privacy-policy-link")

            Text("·")
                .accessibilityHidden(true)

            Link(L10n.string("使用条款"), destination: AppConstants.termsOfUseURL)
                .accessibilityIdentifier("supporter-terms-of-use-link")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(PhotoDeleteStyle.secondaryText)
    }
}

private enum PurchaseButtonStyle {
    case primary
    case secondary
}

private struct PurchaseButtonModifier: ViewModifier {
    let style: PurchaseButtonStyle

    func body(content: Content) -> some View {
        switch style {
        case .primary:
            content.photoDeletePrimaryButton()
        case .secondary:
            content.photoDeleteSecondaryButton()
        }
    }
}

private struct SupporterUnlockedContent: View {
    let purchaseDate: Date?
    let expirationDate: Date?
    let accessKind: SupporterAccessKind?
    let accessNotice: String?

    var body: some View {
        VStack(spacing: 20) {
            SupporterBadgeCard(accessKind: accessKind)

            SupporterPurchaseStatusCard(
                purchaseDate: purchaseDate,
                expirationDate: expirationDate,
                accessKind: accessKind
            )

            if let accessNotice {
                SupporterEntitlementNotice(message: accessNotice)
            }

            SupporterPlanComparisonCard()
        }
    }
}

private struct SupporterEntitlementNotice: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)

            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .photoDeleteCard()
    }
}

private struct SupporterBadgeCard: View {
    let accessKind: SupporterAccessKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(PhotoDeleteStyle.accent.opacity(0.18))
                        .frame(width: 54, height: 54)

                    Image(systemName: "seal.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(accessKind == .annual ? L10n.string("年度 Pro 已启用") : L10n.string("永久 Pro 已解锁"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(accessKind == .annual ? L10n.string("订阅有效期内可使用全部进阶功能。") : L10n.string("一次购买，全部进阶功能永久可用。"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .photoDeleteCard()
    }
}

private struct SupporterPurchaseStatusCard: View {
    let purchaseDate: Date?
    let expirationDate: Date?
    let accessKind: SupporterAccessKind?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.positive)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string("购买状态"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(statusText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .photoDeleteCard()
    }

    private var statusText: String {
        if accessKind == .annual {
            guard let expirationDate else {
                return L10n.string("年度 Pro 已启用，订阅状态会由 App Store 自动更新。")
            }
            return String(
                format: L10n.string("年度 Pro 当前有效至 %@，续订状态以 App Store 为准。"),
                CleanupStatsFormatter.sessionDate.string(from: expirationDate)
            )
        }

        guard let purchaseDate else {
            return L10n.string("永久 Pro 已解锁，所有进阶功能可长期使用。")
        }
        return String(
            format: L10n.string("已于 %@ 解锁永久 Pro，可长期使用。"),
            CleanupStatsFormatter.sessionDate.string(from: purchaseDate)
        )
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
                .foregroundColor(PhotoDeleteStyle.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .photoDeleteCard()
    }
}

struct SupporterMonthlySection: View {
    let summaries: [CleanupMonthlySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("月度统计"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            if summaries.isEmpty {
                SupporterEmptyText(L10n.string("完成一次整理后，这里会出现月度记录。"))
            } else {
                VStack(spacing: 0) {
                    ForEach(summaries.prefix(6)) { summary in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(summary.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(PhotoDeleteStyle.primaryText)

                                Text(L10n.string("\(summary.sessions) 次 · 整理 \(summary.organizedPhotos) 张"))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                            }

                            Spacer()

                            Text(summary.formattedSpaceSaved)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.positive)
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
        .photoDeleteCard()
    }
}

struct SupporterHistorySection: View {
    let sessions: [CleanupSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("清理历史"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            if sessions.isEmpty {
                SupporterEmptyText(L10n.string("确认删除或收藏后，会在本机留下清理记录。"))
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.positive)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.formattedDate)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(PhotoDeleteStyle.primaryText)

                                Text(L10n.string("删除 \(session.deletedPhotos) 张 · 收藏 \(session.favoritedPhotos) 张"))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                            }

                            Spacer()

                            Text(session.formattedSpaceSaved)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.positive)
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
        .photoDeleteCard()
    }
}

struct SupporterDivider: View {
    var body: some View {
        Divider()
            .background(PhotoDeleteStyle.hairline)
            .padding(.leading, 16)
    }
}

struct SupporterPlanComparisonCard: View {
    static let features: [SupporterPlanComparisonFeature] = [
        .init(titleID: .randomReview, free: .included, supporter: .included),
        .init(titleID: .basicSwipeReview, free: .included, supporter: .included),
        .init(titleID: .confirmedDeleteAndFavorite, free: .included, supporter: .included),
        .init(titleID: .basicTimeOrganizing, free: .included, supporter: .included),
        .init(titleID: .localCleanupHistory, free: .included, supporter: .included),
        .init(titleID: .basicSpaceSavedStats, free: .included, supporter: .included),
        .init(titleID: .fullTimeList, free: .notIncluded, supporter: .included),
        .init(titleID: .largeFileCleanup, free: .notIncluded, supporter: .included),
        .init(titleID: .imageCompression, free: .notIncluded, supporter: .included),
        .init(titleID: .videoCompression, free: .notIncluded, supporter: .included),
        .init(titleID: .similarPhotoCleanup, free: .notIncluded, supporter: .included),
        .init(titleID: .themeSwitching, free: .notIncluded, supporter: .included)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.string("版本对比"))
                .font(.headline)
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                Text(L10n.string("功能"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.string("免费版"))
                    .frame(width: 64)
                Text(L10n.string("Pro"))
                    .frame(width: 64)
            }
            .font(.caption.bold())
            .foregroundColor(PhotoDeleteStyle.secondaryText)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ForEach(Self.features) { row in
                SupporterPlanComparisonRow(model: row)
                if row.id != Self.features.last?.id {
                    SupporterDivider()
                }
            }
        }
        .photoDeleteCard()
    }
}

struct SupporterPlanComparisonFeature: Identifiable, Equatable {
    let titleID: SupporterPlanFeatureTitle
    let free: SupporterPlanAvailability
    let supporter: SupporterPlanAvailability

    var id: String { titleID.rawValue }
    var title: String { titleID.localizedTitle }
}

enum SupporterPlanFeatureTitle: String {
    case randomReview = "随机整理"
    case basicSwipeReview = "基础滑动整理"
    case confirmedDeleteAndFavorite = "确认后删除和收藏"
    case basicTimeOrganizing = "按时间整理"
    case localCleanupHistory = "本机清理历史"
    case basicSpaceSavedStats = "基础节省空间统计"
    case fullTimeList = "完整时间列表"
    case largeFileCleanup = "大文件清理"
    case imageCompression = "图片压缩"
    case videoCompression = "视频压缩"
    case similarPhotoCleanup = "相似照片清理"
    case themeSwitching = "主题切换"

    var localizedTitle: String {
        switch self {
        case .randomReview: return L10n.string("随机整理")
        case .basicSwipeReview: return L10n.string("基础滑动整理")
        case .confirmedDeleteAndFavorite: return L10n.string("确认后删除和收藏")
        case .basicTimeOrganizing: return L10n.string("按时间整理")
        case .localCleanupHistory: return L10n.string("本机清理历史")
        case .basicSpaceSavedStats: return L10n.string("基础节省空间统计")
        case .fullTimeList: return L10n.string("完整时间列表")
        case .largeFileCleanup: return L10n.string("大文件清理")
        case .imageCompression: return L10n.string("图片压缩")
        case .videoCompression: return L10n.string("视频压缩")
        case .similarPhotoCleanup: return L10n.string("相似照片清理")
        case .themeSwitching: return L10n.string("主题切换")
        }
    }
}

private struct SupporterPlanComparisonRow: View {
    let model: SupporterPlanComparisonFeature

    var body: some View {
        HStack(spacing: 10) {
            Text(model.title)
                .font(.subheadline)
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            availabilityCell(model.free)
            availabilityCell(model.supporter)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func availabilityCell(_ availability: SupporterPlanAvailability) -> some View {
        Image(systemName: availability.systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(availability.tint)
            .frame(width: 64)
            .frame(minHeight: 24)
            .accessibilityLabel(availability.accessibilityLabel)
    }
}

enum SupporterPlanAvailability: Equatable {
    case included
    case notIncluded

    var systemImage: String {
        switch self {
        case .included: return "checkmark.circle.fill"
        case .notIncluded: return "minus"
        }
    }

    var tint: Color {
        switch self {
        case .included: return PhotoDeleteStyle.accent
        case .notIncluded: return PhotoDeleteStyle.tertiaryText
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .included: return L10n.string("包含")
        case .notIncluded: return L10n.string("不包含")
        }
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
            .foregroundColor(PhotoDeleteStyle.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

struct SupporterBenefitsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        Text(L10n.string("免费版保留随机整理、滑动整理和按时间整理；支持者版额外解锁完整时间列表、图片压缩、视频压缩、大文件清理、相似照片清理和主题切换。"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        SupporterPlanComparisonCard()
                    }
                    .padding(PhotoDeleteStyle.screenHorizontalPadding)
                }
            }
            .navigationTitle(L10n.string("功能区别"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                }
            }
        }
    }
}

struct CleanupHistoryView: View {
    @ObservedObject var statsStore: CleanupStatsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false

    private var summary: CleanupStatsSummary {
        statsStore.summary
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            SupporterMetricCard(value: "\(summary.organizedPhotos)", label: L10n.string("累计整理"), tint: PhotoDeleteStyle.accent)
                            SupporterMetricCard(value: "\(summary.deletedPhotos)", label: L10n.string("累计删除"), tint: PhotoDeleteStyle.destructive)
                            SupporterMetricCard(value: summary.formattedSpaceSaved, label: L10n.string("节省空间"), tint: PhotoDeleteStyle.positive)
                            SupporterMetricCard(value: "\(summary.sessions)", label: L10n.string("清理次数"), tint: PhotoDeleteStyle.warning)
                        }

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
                    .padding(PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.string("清理历史"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
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
}

#Preview {
    SupporterView()
        .environmentObject(DataManager())
        .environmentObject(PurchaseManager())
}
