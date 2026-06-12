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
    @AppStorage(AppConstants.hasSeenIntroKey) private var hasSeenPhotoDeleteIntro = false
    @AppStorage(AppConstants.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @AppStorage(AppConstants.hapticsEnabledKey) private var hapticsEnabled = true
    @AppStorage(AppConstants.appLanguageKey) private var appLanguageValue = AppLanguage.system.rawValue
    @AppStorage(AppConstants.leftSwipeActionKey) private var leftSwipeActionValue = SwipeGesturePreset.standard.leftAction.rawValue
    @AppStorage(AppConstants.rightSwipeActionKey) private var rightSwipeActionValue = SwipeGesturePreset.standard.rightAction.rawValue
    @AppStorage(AppConstants.upSwipeActionKey) private var upSwipeActionValue = SwipeGesturePreset.standard.upAction.rawValue
    @AppStorage(AppConstants.appAppearanceKey) private var appAppearanceValue = AppAppearance.system.rawValue
    @State private var activeSheet: SettingsSheet?
    @State private var showingClearLocalDataConfirmation = false
    @State private var settingsToast: PhotoDeleteToast?

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(spacing: PhotoDeleteStyle.sectionSpacing) {
                        Text(L10n.string("个人设置与偏好"))
                            .font(.subheadline)
                            .foregroundStyle(PhotoDeleteStyle.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)

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

                        // 版本信息
                        versionInfo

                        // 底部安全区域
                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
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
            case .gestureSettings:
                GestureSettingsView()
            case .languageSettings:
                LanguageSettingsView()
            case .appearanceSettings:
                AppearanceSettingsView()
            }
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 12)], spacing: 14) {
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
                .padding(20)

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingsStorageSummaryRow(storage: stats.storageSnapshot)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .photoDeleteCard()
        }
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
                    icon: purchaseManager.isSupporter ? "seal" : "sparkles",
                    iconColor: purchaseManager.isSupporter ? PhotoDeleteStyle.positive : PhotoDeleteStyle.accent,
                    title: purchaseManager.isSupporter ? L10n.string("支持者版已解锁") : L10n.string("解锁进阶功能"),
                    subtitle: purchaseManager.isSupporter ? L10n.string("已购买") : L10n.string("购买或恢复"),
                    action: {
                        activeSheet = .supporter
                    }
                )
            }
            .photoDeleteCard()
        }
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
                    iconColor: PhotoDeleteStyle.accent,
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
                    iconColor: PhotoDeleteStyle.accent,
                    title: L10n.string("手势控制"),
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
                    iconColor: PhotoDeleteStyle.accent,
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
                    icon: selectedAppearance.icon,
                    iconColor: PhotoDeleteStyle.warning,
                    title: L10n.string("外观"),
                    subtitle: selectedAppearance.title,
                    action: {
                        activeSheet = .appearanceSettings
                    }
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.horizontal, 16)

                SettingToggleRow(
                    icon: "hand.tap",
                    iconColor: PhotoDeleteStyle.accent,
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
                    iconColor: PhotoDeleteStyle.secondaryText,
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
                    iconColor: PhotoDeleteStyle.secondaryText,
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
        return "\(left) · \(right) · \(up)"
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
            case .delete:
                return L10n.string("删")
            case .keep:
                return L10n.string("留")
            case .favorite:
                return L10n.string("收藏")
            }
        }

        switch action {
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
        return String(format: "%.1f", rounded)
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
                .font(.headline)
                .bold()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .photoDeleteSecondaryLabel(.caption)
        }
        .frame(maxWidth: .infinity)
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
    let iconColor: Color
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
    let icon: String
    let iconColor: Color
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
        .tint(PhotoDeleteStyle.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: PhotoDeleteStyle.rowMinHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 手势设置
struct GestureSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppConstants.leftSwipeActionKey) private var leftSwipeActionValue = SwipeGesturePreset.standard.leftAction.rawValue
    @AppStorage(AppConstants.rightSwipeActionKey) private var rightSwipeActionValue = SwipeGesturePreset.standard.rightAction.rawValue
    @AppStorage(AppConstants.upSwipeActionKey) private var upSwipeActionValue = SwipeGesturePreset.standard.upAction.rawValue

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(spacing: PhotoDeleteStyle.sectionSpacing) {
                        currentGesturePreview
                        presetSection
                        customGestureSection
                        resetButton
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(L10n.string("手势控制"))
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
                ForEach(SwipeGestureAction.allCases) { action in
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
    @AppStorage(AppConstants.appAppearanceKey) private var selectedAppearanceID = AppAppearance.system.rawValue

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("外观"))
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)

                            Text(L10n.string("选择日间、夜间，或跟随 iPhone 系统外观。"))
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 0) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Button {
                                    selectedAppearanceID = appearance.rawValue
                                    HapticManager.impact(.light)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: appearance.icon)
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(selectedAppearance == appearance ? PhotoDeleteStyle.accent : PhotoDeleteStyle.tertiaryText)
                                            .frame(width: 24)

                                        Text(appearance.title)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(PhotoDeleteStyle.primaryText)
                                            .lineLimit(1)

                                        Spacer()

                                        Image(systemName: selectedAppearance == appearance ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(selectedAppearance == appearance ? PhotoDeleteStyle.positive : PhotoDeleteStyle.tertiaryText)
                                    }
                                    .padding(16)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(Text(appearance.detail))
                                .accessibilityAddTraits(selectedAppearance == appearance ? .isSelected : [])
                                .accessibilityValue(Text(selectedAppearance == appearance ? L10n.string("已选") : L10n.string("未选择")))

                                if appearance != AppAppearance.allCases.last {
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
                }
            }
            .navigationTitle(L10n.string("外观"))
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

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: selectedAppearanceID) ?? .system
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

                            Text(try! AttributedString(
                                markdown: L10n.string("喜欢旅行和探索世界，也用 AI 做一些有趣的小产品。博客和作品集在 [makerjackie.com](https://makerjackie.com)。"),
                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
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
