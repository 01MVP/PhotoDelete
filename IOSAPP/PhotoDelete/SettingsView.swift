//
//  SettingsView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import SwiftUI
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MessageUI)
import MessageUI
#endif

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppConstants.hasSeenIntroKey) private var hasSeenPhotoDeleteIntro = false
    @AppStorage(AppConstants.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @AppStorage(AppConstants.hapticsEnabledKey) private var hapticsEnabled = true
    @AppStorage(AppConstants.appLanguageKey) private var appLanguageValue = AppLanguage.system.rawValue
    @AppStorage(AppConstants.leftSwipeActionKey) private var leftSwipeActionValue = SwipeGesturePreset.standard.leftAction.rawValue
    @AppStorage(AppConstants.rightSwipeActionKey) private var rightSwipeActionValue = SwipeGesturePreset.standard.rightAction.rawValue
    @AppStorage(AppConstants.upSwipeActionKey) private var upSwipeActionValue = SwipeGesturePreset.standard.upAction.rawValue
    @AppStorage(AppConstants.reviewMediaAutoPlayKey) private var reviewMediaAutoPlay = true
    @AppStorage(AppConstants.appAppearanceKey) private var appAppearanceValue = AppAppearance.system.rawValue
    @AppStorage(AppConstants.appThemeKey) private var appThemeValue = PhotoDeleteTheme.defaultTheme.rawValue
    @State private var activeSheet: SettingsSheet?
    @State private var showingClearLocalDataConfirmation = false
    @State private var settingsToast: PhotoDeleteToast?

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(spacing: PhotoDeleteStyle.sectionSpacing) {
                        // 使用统计
                        statsSection

                        // 支持者版
                        supporterSection

                        // 偏好设置
                        preferencesSection

                        // 数据与权限
                        dataPermissionsSection

                        // 关于与支持
                        aboutSection

                        // 作者的更多 App
                        moreAppsSection

                        // 版本信息
                        versionInfo

                        // 底部安全区域
                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, PhotoDeleteStyle.rootContentTopSpacing)
                    .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                    .frame(maxWidth: .infinity)
                }

                if let settingsToast {
                    settingsToastView(settingsToast)
                }
            }
            .navigationTitle(L10n.string("设置"))
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .mail:
            #if canImport(MessageUI)
                MailComposeView()
            #else
                Text(L10n.string("此设备不支持发送邮件"))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .padding()
            #endif
            case .about:
                AboutView()
            case .author:
                AuthorView()
            case .privacy:
                PrivacyInfoView()
            case .supporter:
                SupporterView()
                    .environmentObject(dataManager)
                    .environmentObject(purchaseManager)
            case .cleanupActivity:
                NavigationStack {
                    CleanupAchievementsView(
                        statsStore: dataManager.cleanupStatsStore,
                        showsDoneButton: true,
                        showsHistory: true
                    )
                }
            case .gestureSettings:
                GestureSettingsView()
            case .languageSettings:
                LanguageSettingsView()
            case .appearanceSettings:
                AppearanceSettingsView()
            }
        }
        .task {
            await purchaseManager.refreshEntitlementsAfterPotentialExternalChange()
        }
    }

    // MARK: - 使用统计
    private var statsSection: some View {
        let stats = dataManager.makeSettingsStatsSummary()

        return VStack(spacing: 16) {
            HStack {
                Text(L10n.string("使用统计"))
                    .photoDeleteSectionHeading()
                Spacer()
            }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    StatCard(
                        value: "\(stats.totalAssets)",
                        label: L10n.string("照片"),
                        color: PhotoDeleteStyle.accent
                    )

                    StatCard(
                        value: "\(stats.organizedAssets)",
                        label: L10n.string("已整理"),
                        color: PhotoDeleteStyle.positive
                    )

                    StatCard(
                        value: "\(stats.deletedAssets)",
                        label: L10n.string("已删除"),
                        color: PhotoDeleteStyle.destructive
                    )

                    StatCard(
                        value: stats.formattedSpaceSaved,
                        label: L10n.string("节省"),
                        color: PhotoDeleteStyle.warning
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingsStorageSummaryRow(storage: stats.storageSnapshot)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "seal.fill",
                    iconColor: PhotoDeleteStyle.warning,
                    title: L10n.string("成就与历史"),
                    subtitle: cleanupActivitySubtitle,
                    action: {
                        activeSheet = .cleanupActivity
                    }
                )
            }
            .photoDeleteCard()
        }
    }

    private var cleanupActivitySubtitle: String {
        String(
            format: L10n.string("已获得 %lld/%lld 枚徽章 · %lld 次清理"),
            Int64(dataManager.cleanupStatsStore.unlockedAchievements.count),
            Int64(dataManager.cleanupStatsStore.achievementProgresses.count),
            Int64(dataManager.cleanupStatsStore.summary.sessions)
        )
    }

    // MARK: - 支持者版
    private var supporterSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L10n.string("购买与恢复"))
                    .photoDeleteSectionHeading()
                Spacer()
            }

            VStack(spacing: 0) {
                SettingRow(
                    icon: supporterRowIcon,
                    iconColor: supporterRowIconColor,
                    title: supporterRowTitle,
                    subtitle: supporterRowSubtitle,
                    action: {
                        activeSheet = .supporter
                    }
                )
            }
            .photoDeleteCard()
        }
    }

    private var supporterRowIcon: String {
        if purchaseManager.hasPaidSupporterAccess {
            return "seal"
        }

        if purchaseManager.isUsingTrialSupporterAccess {
            return "timer"
        }

        return "sparkles"
    }

    private var supporterRowIconColor: Color {
        if purchaseManager.hasPaidSupporterAccess {
            return PhotoDeleteStyle.positive
        }

        return PhotoDeleteStyle.accent
    }

    private var supporterRowTitle: String {
        if purchaseManager.hasPaidSupporterAccess {
            return L10n.string("支持者版已完整解锁")
        }

        if purchaseManager.isUsingTrialSupporterAccess {
            return L10n.string("支持者版试用中")
        }

        if purchaseManager.isSupporterTrialExpired {
            return L10n.string("体验已结束")
        }

        return L10n.string("解锁进阶功能")
    }

    private var supporterRowSubtitle: String {
        if purchaseManager.hasPaidSupporterAccess {
            return L10n.string("查看购买信息和功能区别")
        }

        if purchaseManager.isUsingTrialSupporterAccess {
            return String(format: L10n.string("还剩 %lld 天，可随时一次性解锁"), purchaseManager.supporterTrialDaysRemaining)
        }

        if purchaseManager.isSupporterTrialExpired {
            return L10n.string("3 天体验已结束，可一次性解锁进阶功能")
        }

        return L10n.string("可先免费体验 3 天，也可一次性解锁")
    }

    // MARK: - 关于与支持
    private var aboutSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L10n.string("关于与支持"))
                    .photoDeleteSectionHeading()
                Spacer()
            }

            VStack(spacing: 0) {
                SettingRow(
                    icon: "star",
                    iconColor: PhotoDeleteStyle.warning,
                    title: L10n.string("给删图评分"),
                    showsChevron: false,
                    action: requestAppReview
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "envelope",
                    iconColor: PhotoDeleteStyle.secondaryText,
                    title: L10n.string("邮件反馈"),
                    subtitle: AppConstants.feedbackEmail,
                    action: handleMailAction
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "person.text.rectangle",
                    title: L10n.string("关于创作者"),
                    action: {
                        activeSheet = .author
                    }
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "lock.shield",
                    iconColor: PhotoDeleteStyle.positive,
                    title: L10n.string("隐私说明"),
                    action: {
                        activeSheet = .privacy
                    }
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "info.circle",
                    iconColor: PhotoDeleteStyle.secondaryText,
                    title: L10n.string("关于删图"),
                    subtitle: L10n.string("版本 \(AppConstants.displayVersion)"),
                    action: {
                        activeSheet = .about
                    }
                )
            }
            .photoDeleteCard()
        }
    }

    // MARK: - 作者的更多 App
    private var moreAppsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L10n.string("作者的更多 App"))
                    .photoDeleteSectionHeading()
                Spacer()
            }

            VStack(spacing: 0) {
                AppPromotionRow(
                    imageName: "OneZenAppIcon",
                    title: L10n.string("OneZen 一念"),
                    subtitle: L10n.string("冥想、呼吸与专注练习"),
                    accessibilityIdentifier: "settings-onezen-app-row",
                    action: openOneZenAppStore
                )
            }
            .photoDeleteCard()
        }
    }

    // MARK: - 偏好设置
    private var preferencesSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L10n.string("偏好设置"))
                    .photoDeleteSectionHeading()
                Spacer()
            }

            VStack(spacing: 0) {
                SettingRow(
                    icon: "hand.draw",
                    title: L10n.string("手势与播放"),
                    subtitle: gestureSettingsSubtitle,
                    action: {
                        activeSheet = .gestureSettings
                    }
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "globe",
                    title: L10n.string("语言"),
                    subtitle: selectedLanguage.title,
                    action: {
                        activeSheet = .languageSettings
                    }
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: selectedTheme.icon,
                    iconColor: selectedTheme.primaryAccent,
                    title: L10n.string("主题与外观"),
                    subtitle: "\(selectedTheme.title) · \(selectedAppearance.title)",
                    action: {
                        activeSheet = .appearanceSettings
                    }
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingToggleRow(
                    icon: "hand.tap",
                    title: L10n.string("触感反馈"),
                    subtitle: L10n.string("滑动、撤销和归类时提供轻微反馈"),
                    isOn: $hapticsEnabled
                )
            }
            .photoDeleteCard()
        }
    }

    // MARK: - 数据与权限
    private var dataPermissionsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L10n.string("数据与权限"))
                    .photoDeleteSectionHeading()
                Spacer()
            }

            VStack(spacing: 0) {
                SettingRow(
                    icon: "tray.full",
                    iconColor: PhotoDeleteStyle.positive,
                    title: L10n.string("本机整理数据"),
                    subtitle: localDataSubtitle,
                    showsChevron: false,
                    action: {
                        showingClearLocalDataConfirmation = true
                    }
                )
                .confirmationDialog(
                    L10n.string("清空本机整理记录？"),
                    isPresented: $showingClearLocalDataConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(L10n.string("清空"), role: .destructive) {
                        clearLocalOrganizeData()
                    }
                    Button(L10n.string("取消"), role: .cancel) {}
                } message: {
                    Text(L10n.string("待删除、待收藏和已整理进度会被清空，不会删除照片库中的任何照片。"))
                }

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "photo.badge.checkmark",
                    title: L10n.string("照片访问权限"),
                    subtitle: photoAccessSubtitle,
                    action: {
                        dataManager.managePhotoLibraryAccessSettings()
                    }
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "questionmark.circle",
                    title: L10n.string("重新查看引导"),
                    showsChevron: false,
                    action: resetIntro
                )
            }
            .photoDeleteCard()
        }
    }

    // MARK: - 版本信息
    private var versionInfo: some View {
        VStack(spacing: 8) {
            Text("\(AppConstants.appDisplayName) v\(AppConstants.displayVersion)")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)

            Text(L10n.string("让照片整理变得简单"))
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
        }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageValue) ?? .system
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceValue) ?? .system
    }

    private var selectedTheme: PhotoDeleteTheme {
        PhotoDeleteTheme.normalized(appThemeValue)
    }

    private func settingsToastView(_ toast: PhotoDeleteToast) -> some View {
        VStack {
            Spacer()
            PhotoDeleteToastView(toast: toast)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var photoAccessSubtitle: String {
        switch dataManager.photoLibraryManager.authorizationStatus {
        case .authorized:
            return L10n.string("全部照片")
        case .limited:
            return L10n.string("仅 \(dataManager.photoLibraryManager.totalPhotosCount) 张")
        case .denied, .restricted:
            return L10n.string("未授权")
        case .notDetermined:
            return L10n.string("未选择")
        @unknown default:
            return L10n.string("查看权限")
        }
    }

    private var localDataSubtitle: String {
        let reviewedCount = dataManager.reviewedAssetIDs.count
        let pendingCount = dataManager.deleteCandidates.count + dataManager.favoriteCandidates.count
        if reviewedCount > 0 {
            return L10n.string("已整理 \(compactPhotoCount(reviewedCount))")
        }
        if pendingCount > 0 {
            return L10n.string("待确认 \(compactPhotoCount(pendingCount))")
        }
        return L10n.string("无记录")
    }

    private var gestureSettingsSubtitle: String {
        let left = "\(shortDirectionTitle(.left))\(shortActionTitle(currentGestureAction(for: .left)))"
        let right = "\(shortDirectionTitle(.right))\(shortActionTitle(currentGestureAction(for: .right)))"
        let up = "\(shortDirectionTitle(.up))\(shortActionTitle(currentGestureAction(for: .up)))"
        let playback = reviewMediaAutoPlay ? L10n.string("自动播放") : L10n.string("手动播放")
        return "\(left) · \(right) · \(up) · \(playback)"
    }

    private var usesChineseCompactText: Bool {
        switch selectedLanguage {
        case .zhHans, .zhHant:
            return true
        case .en:
            return false
        case .system:
            return Locale.autoupdatingCurrent.language.languageCode?.identifier == "zh"
        }
    }

    private func compactPhotoCount(_ count: Int) -> String {
        if usesChineseCompactText {
            if count >= 10_000 {
                return L10n.string("\(oneDecimalTrimmed(Double(count) / 10_000)) 万张")
            }
            return L10n.string("\(count) 张")
        }

        return L10n.string("\(compactPlainCount(count)) photos")
    }

    private func shortDirectionTitle(_ direction: SwipeGestureDirection) -> String {
        if usesChineseCompactText {
            switch direction {
            case .left:
                return L10n.string("左")
            case .right:
                return L10n.string("右")
            case .up:
                return L10n.string("上")
            }
        }

        switch direction {
        case .left:
            return "L"
        case .right:
            return "R"
        case .up:
            return "Up"
        }
    }

    private func shortActionTitle(_ action: SwipeGestureAction) -> String {
        if usesChineseCompactText {
            switch action {
            case .previous:
                return L10n.string("上张")
            case .next:
                return L10n.string("下张")
            case .close:
                return L10n.string("返回")
            case .delete:
                return L10n.string("删")
            case .keep:
                return L10n.string("留")
            case .favorite:
                return L10n.string("收藏")
            }
        }

        switch action {
        case .previous:
            return "Prev"
        case .next:
            return "Next"
        case .close:
            return "Back"
        case .delete:
            return "Delete"
        case .keep:
            return "Keep"
        case .favorite:
            return "Favorite"
        }
    }

    private func compactPlainCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return "\(oneDecimalTrimmed(Double(count) / 1_000_000))M"
        }
        if count >= 1_000 {
            return "\(oneDecimalTrimmed(Double(count) / 1_000))K"
        }
        return "\(count)"
    }

    private func oneDecimalTrimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return rounded.formatted(.number.grouping(.never).precision(.fractionLength(1)))
    }

    private func currentGestureAction(for direction: SwipeGestureDirection) -> SwipeGestureAction {
        switch direction {
        case .left:
            return SwipeGesturePreferences.normalizedAction(leftSwipeActionValue, fallback: SwipeGesturePreferences.defaultAction(for: .left))
        case .right:
            return SwipeGesturePreferences.normalizedAction(rightSwipeActionValue, fallback: SwipeGesturePreferences.defaultAction(for: .right))
        case .up:
            return SwipeGesturePreferences.normalizedAction(upSwipeActionValue, fallback: SwipeGesturePreferences.defaultAction(for: .up))
        }
    }

    private func handleMailAction() {
        #if canImport(MessageUI)
        if MFMailComposeViewController.canSendMail() {
            activeSheet = .mail
        } else {
            openFeedbackMailURL()
        }
        #else
        openFeedbackMailURL()
        #endif
    }

    // MARK: - 方法
    private func openFeedbackMailURL() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppConstants.feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: L10n.string("删图 App 反馈")),
            URLQueryItem(name: "body", value: FeedbackDiagnostics.emailBody())
        ]

        if let url = components.url {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }
    }

    private func openOneZenAppStore() {
        #if canImport(UIKit)
        UIApplication.shared.open(AppConstants.oneZenAppStoreURL)
        #endif
    }

    private func clearLocalOrganizeData() {
        dataManager.clearLocalOrganizeData()
        showSettingsToast(L10n.string("已清空本机整理记录"), icon: "checkmark.circle.fill", style: .positive)
    }

    private func resetIntro() {
        hasSeenPhotoDeleteIntro = false
        hasCompletedOnboarding = false
        showSettingsToast(L10n.string("已恢复开屏引导"), icon: "sparkles", style: .positive)
    }

    private func requestAppReview() {
        #if canImport(StoreKit) && canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            showSettingsToast(
                L10n.string("稍后可在 App Store 评分"),
                icon: "star",
                style: .positive
            )
            return
        }

        SKStoreReviewController.requestReview(in: scene)
        #else
        showSettingsToast(
            L10n.string("稍后可在 App Store 评分"),
            icon: "star",
            style: .positive
        )
        #endif
    }

    private func showSettingsToast(_ message: String, icon: String, style: PhotoDeleteToastStyle) {
        let toast = PhotoDeleteToast(message: message, icon: icon, style: style)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            settingsToast = toast
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard settingsToast?.id == toast.id else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                settingsToast = nil
            }
        }
    }
}

private enum SettingsSheet: Identifiable {
    case mail
    case about
    case author
    case privacy
    case supporter
    case cleanupActivity
    case gestureSettings
    case languageSettings
    case appearanceSettings

    var id: String {
        switch self {
        case .mail: return "mail"
        case .about: return "about"
        case .author: return "author"
        case .privacy: return "privacy"
        case .supporter: return "supporter"
        case .cleanupActivity: return "cleanupActivity"
        case .gestureSettings: return "gestureSettings"
        case .languageSettings: return "languageSettings"
        case .appearanceSettings: return "appearanceSettings"
        }
    }
}

// MARK: - 统计卡片
struct StatCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .bold()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)

            Text(label)
                .photoDeleteSecondaryLabel(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsStorageSummaryRow: View {
    let storage: DeviceStorageSnapshot

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "internaldrive")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PhotoDeleteStyle.accent)
                    .frame(width: 22)

                Text(L10n.string("手机存储空间"))
                    .photoDeletePrimaryLabel(.body.weight(.semibold))

                Spacer()

                Text("\(Int(storage.usedFraction * 100))%")
                    .photoDeleteSecondaryLabel(.subheadline.weight(.semibold))
            }

            ProgressView(value: storage.usedFraction)
                .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                .clipShape(Capsule(style: .continuous))

            HStack {
                Text(L10n.string("已用 \(storage.formattedUsed)"))
                Spacer()
                Text(L10n.string("可用 \(storage.formattedFree)"))
            }
            .font(.caption)
            .foregroundStyle(PhotoDeleteStyle.tertiaryText)
        }
    }
}

// MARK: - 设置行
struct SettingRow: View {
    let icon: String
    var iconColor: Color? = nil
    let title: String
    var subtitle = ""
    var showsChevron = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PhotoDeleteIconTile(icon: icon, tint: iconColor)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        titleLabel
                        Spacer(minLength: 8)
                        subtitleLabel
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        titleLabel
                        subtitleLabel
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PhotoDeleteStyle.tertiaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: PhotoDeleteStyle.rowMinHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title.appLocalized))
        .accessibilityValue(Text(subtitle.appLocalized))
    }

    private var titleLabel: some View {
        Text(title.appLocalized)
            .photoDeletePrimaryLabel()
            .lineLimit(1)
    }

    @ViewBuilder
    private var subtitleLabel: some View {
        if !subtitle.isEmpty {
            Text(subtitle.appLocalized)
                .photoDeleteSecondaryLabel()
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .multilineTextAlignment(.trailing)
                .truncationMode(.tail)
        }
    }
}

struct SettingToggleRow: View {
    @Environment(\.photoDeleteTheme) private var theme
    let icon: String
    var iconColor: Color? = nil
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                PhotoDeleteIconTile(icon: icon, tint: iconColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title.appLocalized)
                        .photoDeletePrimaryLabel()
                        .lineLimit(1)

                    Text(subtitle.appLocalized)
                        .photoDeleteSecondaryLabel(.caption)
                        .lineLimit(2)
                }
            }
        }
        .tint(theme.selectionTint)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: PhotoDeleteStyle.rowMinHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AppPromotionRow: View {
    let imageName: String
    let title: String
    let subtitle: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .photoDeletePrimaryLabel()
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Text(subtitle)
                        .photoDeleteSecondaryLabel(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                }

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PhotoDeleteStyle.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: PhotoDeleteStyle.rowMinHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(subtitle))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

// MARK: - 手势设置
struct GestureSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppConstants.leftSwipeActionKey) private var leftSwipeActionValue = SwipeGesturePreset.standard.leftAction.rawValue
    @AppStorage(AppConstants.rightSwipeActionKey) private var rightSwipeActionValue = SwipeGesturePreset.standard.rightAction.rawValue
    @AppStorage(AppConstants.upSwipeActionKey) private var upSwipeActionValue = SwipeGesturePreset.standard.upAction.rawValue
    @AppStorage(AppConstants.reviewMediaAutoPlayKey) private var reviewMediaAutoPlay = true
    @AppStorage(AppConstants.reviewVideoMutedKey) private var reviewVideoMuted = true

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(spacing: PhotoDeleteStyle.sectionSpacing) {
                        mediaPlaybackSection
                        currentGesturePreview
                        presetSection
                        customGestureSection
                        resetButton
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(L10n.string("手势与播放"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.accent)
                }
            }
        }
    }

    private var mediaPlaybackSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("播放"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            VStack(spacing: 0) {
                SettingToggleRow(
                    icon: "play.circle",
                    title: L10n.string("视频和实况照片自动播放"),
                    subtitle: L10n.string("只播放当前照片，切换后会自动停止"),
                    isOn: $reviewMediaAutoPlay
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingToggleRow(
                    icon: reviewVideoMuted ? "speaker.slash" : "speaker.wave.2",
                    title: L10n.string("视频和实况照片静音播放"),
                    subtitle: L10n.string("开启后每次进入整理页默认静音；整理页可临时打开声音"),
                    isOn: $reviewVideoMuted
                )
            }
            .photoDeleteCard()
        }
    }

    private var currentGesturePreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("当前手势"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            HStack(spacing: 10) {
                ForEach(SwipeGestureDirection.allCases) { direction in
                    GesturePreviewTile(
                        direction: direction,
                        action: currentAction(for: direction)
                    )
                }
            }
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("快速方案"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            VStack(spacing: 10) {
                ForEach(SwipeGesturePreset.presets) { preset in
                    GesturePresetButton(
                        preset: preset,
                        isSelected: matches(preset)
                    ) {
                        applyPreset(preset)
                    }
                }
            }
        }
    }

    private var customGestureSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("自定义"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            VStack(spacing: 0) {
                ForEach(SwipeGestureDirection.allCases) { direction in
                    GestureActionPickerRow(
                        direction: direction,
                        selectedAction: currentAction(for: direction),
                        onSelect: { action in
                            setAction(action, for: direction)
                        }
                    )

                    if direction != .up {
                        Divider()
                            .background(PhotoDeleteStyle.hairline)
                            .padding(.leading, 60)
                    }
                }
            }
            .photoDeleteCard()
        }
    }

    private var resetButton: some View {
        Button(action: {
            applyPreset(.standard)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.string("恢复默认"))
            }
        }
        .photoDeleteSecondaryButton()
    }

    private func currentAction(for direction: SwipeGestureDirection) -> SwipeGestureAction {
        switch direction {
        case .left:
            return SwipeGesturePreferences.normalizedAction(leftSwipeActionValue, fallback: SwipeGesturePreferences.defaultAction(for: .left))
        case .right:
            return SwipeGesturePreferences.normalizedAction(rightSwipeActionValue, fallback: SwipeGesturePreferences.defaultAction(for: .right))
        case .up:
            return SwipeGesturePreferences.normalizedAction(upSwipeActionValue, fallback: SwipeGesturePreferences.defaultAction(for: .up))
        }
    }

    private func setAction(_ action: SwipeGestureAction, for direction: SwipeGestureDirection) {
        switch direction {
        case .left:
            leftSwipeActionValue = action.rawValue
        case .right:
            rightSwipeActionValue = action.rawValue
        case .up:
            upSwipeActionValue = action.rawValue
        }
        HapticManager.impact(.light)
    }

    private func applyPreset(_ preset: SwipeGesturePreset) {
        leftSwipeActionValue = preset.leftAction.rawValue
        rightSwipeActionValue = preset.rightAction.rawValue
        upSwipeActionValue = preset.upAction.rawValue
        HapticManager.impact(.light)
    }

    private func matches(_ preset: SwipeGesturePreset) -> Bool {
        currentAction(for: .left) == preset.leftAction &&
            currentAction(for: .right) == preset.rightAction &&
            currentAction(for: .up) == preset.upAction
    }
}

private struct GesturePreviewTile: View {
    let direction: SwipeGestureDirection
    let action: SwipeGestureAction

    var body: some View {
        VStack(spacing: 8) {
            PhotoDeleteIconTile(
                icon: direction.icon,
                tint: action.tint,
                size: 34,
                cornerRadius: 10
            )

            VStack(spacing: 3) {
                Text(direction.title.appLocalized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(action.title.appLocalized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .photoDeleteCard()
    }
}

private struct GesturePresetButton: View {
    let preset: SwipeGesturePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(preset.title.appLocalized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(isSelected ? PhotoDeleteStyle.positive : PhotoDeleteStyle.tertiaryText)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: PhotoDeleteStyle.cardRadius, style: .continuous)
                    .fill(PhotoDeleteStyle.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PhotoDeleteStyle.cardRadius, style: .continuous)
                            .stroke(isSelected ? PhotoDeleteStyle.positive.opacity(0.38) : PhotoDeleteStyle.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(preset.subtitle.appLocalized))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(Text(isSelected ? L10n.string("已选") : L10n.string("未选择")))
    }
}

private struct GestureActionPickerRow: View {
    let direction: SwipeGestureDirection
    let selectedAction: SwipeGestureAction
    let onSelect: (SwipeGestureAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(
                icon: direction.icon,
                tint: selectedAction.tint,
                size: 36,
                cornerRadius: 10
            )

            Text(direction.title.appLocalized)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .lineLimit(1)

            Spacer()

            Menu {
                ForEach(SwipeGestureAction.configurableCases) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        Label(action.detailTitle, systemImage: action == selectedAction ? "checkmark" : action.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedAction.title.appLocalized)
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(PhotoDeleteStyle.elevatedSurface)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                        )
                    )
                .photoDeleteMinimumTapTarget()
            }
            .accessibilityLabel(Text("\(direction.title.appLocalized) \(L10n.string("手势"))"))
            .accessibilityValue(Text(selectedAction.title.appLocalized))
            .accessibilityHint(Text(selectedAction.detailTitle.appLocalized))
        }
        .padding(16)
    }
}

// MARK: - 语言设置
private struct LanguageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppConstants.appLanguageKey) private var selectedLanguageID = AppLanguage.system.rawValue

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("显示语言"))
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)

                            Text(L10n.string("默认跟随 iPhone 系统语言。也可以在这里固定删图的显示语言。"))
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 0) {
                            ForEach(AppLanguage.allCases) { language in
                                Button {
                                    selectedLanguageID = language.rawValue
                                    HapticManager.impact(.light)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedLanguage == language ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(selectedLanguage == language ? PhotoDeleteStyle.positive : PhotoDeleteStyle.tertiaryText)

                                        Text(language.title)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(PhotoDeleteStyle.primaryText)
                                            .lineLimit(1)

                                        Spacer()
                                    }
                                    .padding(16)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(Text(language.detail))
                                .accessibilityAddTraits(selectedLanguage == language ? .isSelected : [])
                                .accessibilityValue(Text(selectedLanguage == language ? L10n.string("已选") : L10n.string("未选择")))

                                if language != AppLanguage.allCases.last {
                                    Divider()
                                        .background(PhotoDeleteStyle.hairline)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .photoDeleteCard()
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(L10n.string("语言"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.accent)
                }
            }
        }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguageID) ?? .system
    }
}

// MARK: - 外观设置
private struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var dataManager: DataManager
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @AppStorage(AppConstants.appAppearanceKey) private var selectedAppearanceID = AppAppearance.system.rawValue
    @AppStorage(AppConstants.appThemeKey) private var selectedThemeID = PhotoDeleteTheme.defaultTheme.rawValue
    @State private var showingSupporter = false

    private let themeColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        themeSection
                        appearanceSection
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(L10n.string("主题与外观"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.accent)
                }
            }
        }
        .sheet(isPresented: $showingSupporter) {
            SupporterView()
                .environmentObject(dataManager)
                .environmentObject(purchaseManager)
        }
        .onAppear(perform: ensureThemeAccess)
        .onChange(of: purchaseManager.isSupporter) { _ in
            ensureThemeAccess()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("主题与外观"))
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            Text(L10n.string("选择界面色调，以及日间、夜间或跟随系统外观。"))
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("界面色调"))
                    .photoDeleteSectionHeading()

                Text(canChooseThemes ? L10n.string("色调会影响背景、图标、按钮和选中状态。") : L10n.string("支持者版可切换更多主题。"))
                    .photoDeleteSecondaryLabel(.subheadline)
            }

            LazyVGrid(columns: themeColumns, spacing: 10) {
                ForEach(PhotoDeleteTheme.allCases) { theme in
                    themeButton(theme)
                }
            }
        }
    }

    private func themeButton(_ theme: PhotoDeleteTheme) -> some View {
        let isLocked = !canChooseThemes && theme != .defaultTheme
        let isSelected = selectedTheme == theme

        return Button {
            guard !isLocked else {
                showingSupporter = true
                HapticManager.impact(.light)
                return
            }
            selectedThemeID = theme.rawValue
            HapticManager.impact(.light)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    PhotoDeleteThemeSwatches(colors: theme.swatches)
                    Spacer(minLength: 8)
                    Image(systemName: themeStatusImage(isSelected: isSelected, isLocked: isLocked))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? theme.selectionTint : PhotoDeleteStyle.tertiaryText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .lineLimit(1)

                    Text(theme.subtitle)
                        .photoDeleteSecondaryLabel(.caption)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? theme.primaryAccentSoftFill : PhotoDeleteStyle.surfaceFill(for: selectedTheme, elevated: true))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? theme.primaryAccentSoftStroke : PhotoDeleteStyle.strokeFill(for: selectedTheme), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(isLocked ? 0.76 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(isLocked ? L10n.string("支持者版可切换更多主题。") : theme.subtitle))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(Text(isSelected ? L10n.string("已选") : isLocked ? L10n.string("解锁后可用") : L10n.string("未选择")))
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("外观"))
                .photoDeleteSectionHeading()

            VStack(spacing: 0) {
                ForEach(AppAppearance.allCases) { appearance in
                    Button {
                        selectedAppearanceID = appearance.rawValue
                        HapticManager.impact(.light)
                    } label: {
                        HStack(spacing: 12) {
                            PhotoDeleteIconTile(
                                icon: appearance.icon,
                                tint: selectedAppearance == appearance ? selectedTheme.selectionTint : PhotoDeleteStyle.tertiaryText,
                                size: 30,
                                cornerRadius: 9
                            )

                            Text(appearance.title)
                                .font(.body.weight(.semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: selectedAppearance == appearance ? "checkmark.circle.fill" : "circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(selectedAppearance == appearance ? selectedTheme.selectionTint : PhotoDeleteStyle.tertiaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text(appearance.detail))
                    .accessibilityAddTraits(selectedAppearance == appearance ? .isSelected : [])
                    .accessibilityValue(Text(selectedAppearance == appearance ? L10n.string("已选") : L10n.string("未选择")))

                    if appearance != AppAppearance.allCases.last {
                        Divider()
                            .background(PhotoDeleteStyle.hairline)
                            .padding(.leading, 58)
                    }
                }
            }
            .photoDeleteCard()
        }
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: selectedAppearanceID) ?? .system
    }

    private var selectedTheme: PhotoDeleteTheme {
        guard canChooseThemes else { return .defaultTheme }
        return PhotoDeleteTheme.normalized(selectedThemeID)
    }

    private var canChooseThemes: Bool {
        purchaseManager.isSupporter
    }

    private func ensureThemeAccess() {
        guard !canChooseThemes, selectedThemeID != PhotoDeleteTheme.defaultTheme.rawValue else { return }
        selectedThemeID = PhotoDeleteTheme.defaultTheme.rawValue
    }

    private func themeStatusImage(isSelected: Bool, isLocked: Bool) -> String {
        if isLocked { return "lock.fill" }
        return isSelected ? "checkmark.circle.fill" : "circle"
    }
}

private struct PhotoDeleteThemeSwatches: View {
    let colors: [Color]

    var body: some View {
        HStack(spacing: -5) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(PhotoDeleteStyle.cardStroke, lineWidth: 1)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 邮件编写视图
#if canImport(MessageUI)
struct MailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setSubject(L10n.string("删图 App 反馈"))
        composer.setToRecipients([AppConstants.feedbackEmail])
        composer.setMessageBody(FeedbackDiagnostics.emailBody(), isHTML: false)

        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var parent: MailComposeView

        init(_ parent: MailComposeView) {
            self.parent = parent
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.dismiss()
        }
    }
}
#endif

// MARK: - 作者介绍视图
struct AuthorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authorToast: PhotoDeleteToast?

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 14) {
                                AuthorAvatar()

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(AppConstants.authorName)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(PhotoDeleteStyle.primaryText)

                                    Text(L10n.string("独立开发者 / 数字游民"))
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Text(L10n.attributedMarkdown(
                                "喜欢旅行和探索世界，也用 AI 做一些有趣的小产品。博客和作品集在 [makerjackie.com](https://makerjackie.com)。"
                            ))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .tint(PhotoDeleteStyle.accent)
                        }

                        if AppLanguage.current.showsSimplifiedChineseOnlyContent {
                            HStack(alignment: .center, spacing: 12) {
                                PhotoDeleteIconTile(icon: "bubble.left.and.bubble.right.fill", tint: PhotoDeleteStyle.positive, size: 38, cornerRadius: 11)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.string("联系作者微信"))
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(PhotoDeleteStyle.primaryText)

                                    Text(AppConstants.wechatID)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                                }

                                Spacer(minLength: 8)

                                Button(action: copyWeChatID) {
                                    Text(authorToast == nil ? L10n.string("复制") : L10n.string("已复制"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(PhotoDeleteStyle.primaryButtonText)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(PhotoDeleteStyle.accent)
                                        )
                                        .photoDeleteMinimumTapTarget()
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(format: L10n.string("复制微信号 %@"), AppConstants.wechatID))
                                .accessibilityHint(L10n.string("轻点复制"))
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .photoDeleteCard()
                        }

                        CreatorMVPGuideSection()

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }

                if let authorToast {
                    authorToastView(authorToast)
                }
            }
            .navigationTitle(L10n.string("关于创作者"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.accent)
                }
            }
        }
    }

    private func authorToastView(_ toast: PhotoDeleteToast) -> some View {
        VStack {
            Spacer()

            PhotoDeleteToastView(toast: toast)
                .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
    }

    private func copyWeChatID() {
        #if canImport(UIKit)
        UIPasteboard.general.string = AppConstants.wechatID
        showAuthorToast(L10n.string("已复制微信号 \(AppConstants.wechatID)"), icon: "checkmark.circle.fill", style: .positive)
        #endif
    }

    private func showAuthorToast(_ message: String, icon: String, style: PhotoDeleteToastStyle) {
        let toast = PhotoDeleteToast(message: message, icon: icon, style: style)

        withAnimation(.easeInOut(duration: 0.18)) {
            authorToast = toast
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard authorToast?.id == toast.id else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                authorToast = nil
            }
        }
    }
}

struct AuthorAvatar: View {
    var body: some View {
        Image("MakerJackieAvatar")
            .resizable()
            .scaledToFill()
            .frame(width: 62, height: 62)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(PhotoDeleteStyle.primaryText.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: PhotoDeleteStyle.accent.opacity(0.2), radius: 18, x: 0, y: 10)
            .accessibilityLabel(AppConstants.authorName)
    }
}

// MARK: - 隐私说明视图
struct PrivacyInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("隐私优先"))
                                .font(.title.weight(.semibold))
                                .foregroundStyle(PhotoDeleteStyle.primaryText)

                            Text(AppConstants.privacyShortText)
                                .photoDeleteSecondaryLabel(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 12) {
                            PrivacyInfoRow(
                                icon: "iphone",
                                title: L10n.string("本机整理"),
                                detail: L10n.string("预览、待确认列表和删除确认都保存在你的设备上。")
                            )

                            PrivacyInfoRow(
                                icon: "icloud.slash",
                                title: L10n.string("不上传照片"),
                                detail: L10n.string("删图不接入自己的云端服务，也不会把照片发到服务器。")
                            )

                            PrivacyInfoRow(
                                icon: "person.crop.circle.badge.xmark",
                                title: L10n.string("不需要账号"),
                                detail: L10n.string("授权照片后即可使用，不需要注册或登录。")
                            )
                        }
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(L10n.string("隐私"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.accent)
                }
            }
        }
    }
}

struct PrivacyInfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(PhotoDeleteStyle.elevatedSurface)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .photoDeletePrimaryLabel(.body.weight(.semibold))

                Text(detail)
                    .photoDeleteSecondaryLabel(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .photoDeleteCard()
    }
}

// MARK: - 关于视图
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(spacing: 32) {
                        // App图标
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(PhotoDeleteStyle.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                                )
                                .frame(width: 120, height: 120)

                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundColor(PhotoDeleteStyle.accent)
                        }

                        // App信息
                        VStack(spacing: 16) {
                            Text(AppConstants.appDisplayName)
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(PhotoDeleteStyle.primaryText)

                            Text(L10n.string("版本 \(AppConstants.displayVersion)"))
                                .photoDeleteSecondaryLabel(.body)

                            Text(L10n.string("一个免费的相册整理工具。滑动判断照片去留，完成后再统一确认。"))
                                .photoDeleteSecondaryLabel(.body)
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                        }
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 52)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.string("关于"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("完成")) {
                        dismiss()
                    }
                    .foregroundColor(PhotoDeleteStyle.accent)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataManager())
        .environmentObject(PurchaseManager())
}
