//
//  SettingsView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MessageUI)
import MessageUI
#endif

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @AppStorage("hasSeenPhotoDelIntro") private var hasSeenPhotoDelIntro = false
    @AppStorage(AppConstants.hapticsEnabledKey) private var hapticsEnabled = true
    @AppStorage(AppConstants.leftSwipeActionKey) private var leftSwipeActionValue = SwipeGesturePreset.standard.leftAction.rawValue
    @AppStorage(AppConstants.rightSwipeActionKey) private var rightSwipeActionValue = SwipeGesturePreset.standard.rightAction.rawValue
    @AppStorage(AppConstants.upSwipeActionKey) private var upSwipeActionValue = SwipeGesturePreset.standard.upAction.rawValue
    @State private var showingMailCompose = false
    @State private var showingAbout = false
    @State private var showingAuthor = false
    @State private var showingPrivacyInfo = false
    @State private var showingSupporter = false
    @State private var showingGestureSettings = false
    @State private var showingWeChatCopied = false
    @State private var settingsToast: PhotoDelToast?
    
    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDelScreenBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        // 顶部标题
                        VStack(spacing: 8) {
                            Text("设置")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.primaryText)
                            
                            Text("个人设置与偏好")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                        }
                        .padding(.top, 20)
                        
                        // 使用统计
                        statsSection

                        // 支持者版
                        supporterSection

                        // 应用设置
                        appSettingsSection
                        
                        // 关于与支持
                        aboutSection
                        
                        // 版本信息
                        versionInfo
                        
                        // 底部安全区域
                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.horizontal, 24)
                }

                if showingWeChatCopied {
                    copyToast
                }

                if let settingsToast {
                    settingsToastView(settingsToast)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingMailCompose) {
            #if canImport(MessageUI)
            if MFMailComposeViewController.canSendMail() {
                MailComposeView()
            } else {
                // 如果设备不支持邮件，显示替代方案
                Text("此设备不支持发送邮件")
                    .foregroundColor(PhotoDelStyle.primaryText)
                    .padding()
            }
            #else
            Text("此设备不支持发送邮件")
                .foregroundColor(PhotoDelStyle.primaryText)
                .padding()
            #endif
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingAuthor) {
            AuthorView()
        }
        .sheet(isPresented: $showingPrivacyInfo) {
            PrivacyInfoView()
        }
        .sheet(isPresented: $showingSupporter) {
            SupporterView()
                .environmentObject(dataManager)
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingGestureSettings) {
            GestureSettingsView()
        }
    }
    
    // MARK: - 使用统计
    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("使用统计")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                Spacer()
            }
            
            HStack(spacing: 0) {
                StatCard(
                    value: "\(dataManager.organizeStats.totalPhotos)",
                    label: "总照片",
                    color: PhotoDelStyle.accent
                )
                
                StatCard(
                    value: "\(dataManager.organizeStats.deletedPhotos)",
                    label: "已删除",
                    color: PhotoDelStyle.destructive
                )
                
                StatCard(
                    value: "\(dataManager.getVideosCount())",
                    label: "视频",
                    color: PhotoDelStyle.iconTint(for: "video")
                )
                
                StatCard(
                    value: dataManager.organizeStats.formattedSpaceSaved,
                    label: "节省空间",
                    color: PhotoDelStyle.positive
                )
            }
            .padding(20)
            .photoDelCard()
        }
    }

    // MARK: - 支持者版
    private var supporterSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("支持者版")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                Spacer()
            }

            VStack(spacing: 0) {
                SettingRow(
                    icon: purchaseManager.isSupporter ? "seal.fill" : "sparkles",
                    iconColor: purchaseManager.isSupporter ? PhotoDelStyle.positive : PhotoDelStyle.accent,
                    title: "PhotoDel 支持者版",
                    subtitle: purchaseManager.isSupporter ? "已解锁长期统计和支持者功能" : "长期统计、月度记录和徽章",
                    action: {
                        showingSupporter = true
                    }
                )
            }
            .photoDelCard()
        }
    }
    
    // MARK: - 关于与支持
    private var aboutSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("关于与支持")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                Spacer()
            }
            
            VStack(spacing: 0) {
                SettingRow(
                    icon: "lock.shield.fill",
                    iconColor: PhotoDelStyle.positive,
                    title: "隐私说明",
                    subtitle: "本机整理，不上传照片",
                    action: {
                        showingPrivacyInfo = true
                    }
                )

                Divider()
                    .background(PhotoDelStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "person.text.rectangle.fill",
                    iconColor: PhotoDelStyle.accent,
                    title: "了解作者",
                    subtitle: "01MVP 与小产品创作",
                    action: {
                        showingAuthor = true
                    }
                )
                
                Divider()
                    .background(PhotoDelStyle.hairline)
                    .padding(.horizontal, 16)
                
                SettingRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    iconColor: PhotoDelStyle.positive,
                    title: "微信反馈",
                    subtitle: AppConstants.wechatID,
                    action: copyWeChatID
                )

                Divider()
                    .background(PhotoDelStyle.hairline)
                    .padding(.horizontal, 16)

                // 邮件反馈
                SettingRow(
                    icon: "envelope.fill",
                    iconColor: PhotoDelStyle.secondaryText,
                    title: "邮件反馈",
                    subtitle: AppConstants.feedbackEmail,
                    action: {
                        handleMailAction()
                    }
                )
                
                Divider()
                    .background(PhotoDelStyle.hairline)
                    .padding(.horizontal, 16)
                
                // 关于应用
                SettingRow(
                    icon: "info.circle.fill",
                    iconColor: PhotoDelStyle.secondaryText,
                    title: "关于 PhotoDel",
                    subtitle: "版本 \(AppConstants.version)",
                    action: {
                        showingAbout = true
                    }
                )
            }
            .photoDelCard()
        }
    }

    // MARK: - 应用设置
    private var appSettingsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("应用设置")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)
                Spacer()
            }

            VStack(spacing: 0) {
                SettingRow(
                    icon: "photo.badge.checkmark",
                    iconColor: PhotoDelStyle.accent,
                    title: "照片访问权限",
                    subtitle: photoAccessSubtitle,
                    action: {
                        dataManager.openPhotoLibrarySettings()
                    }
                )

                Divider()
                    .background(PhotoDelStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "hand.draw.fill",
                    iconColor: PhotoDelStyle.accent,
                    title: "手势控制",
                    subtitle: gestureSettingsSubtitle,
                    action: {
                        showingGestureSettings = true
                    }
                )

                Divider()
                    .background(PhotoDelStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "tray.full.fill",
                    iconColor: PhotoDelStyle.positive,
                    title: "本机整理数据",
                    subtitle: localDataSubtitle,
                    showsChevron: false,
                    action: clearLocalOrganizeData
                )

                Divider()
                    .background(PhotoDelStyle.hairline)
                    .padding(.horizontal, 16)

                SettingRow(
                    icon: "questionmark.circle.fill",
                    iconColor: PhotoDelStyle.secondaryText,
                    title: "重新查看引导",
                    subtitle: "下次打开 App 时显示使用说明",
                    showsChevron: false,
                    action: resetIntro
                )

                Divider()
                    .background(PhotoDelStyle.hairline)
                    .padding(.horizontal, 16)

                SettingToggleRow(
                    icon: "hand.tap.fill",
                    iconColor: PhotoDelStyle.accent,
                    title: "触感反馈",
                    subtitle: "滑动、撤销和归类时提供轻微反馈",
                    isOn: $hapticsEnabled
                )
            }
            .photoDelCard()
        }
    }
    
    // MARK: - 版本信息
    private var versionInfo: some View {
        VStack(spacing: 8) {
            Text("PhotoDel v\(AppConstants.version)")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(PhotoDelStyle.secondaryText)
            
            Text("让照片整理变得简单")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(PhotoDelStyle.tertiaryText)
        }
    }

    private var copyToast: some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.positive)

                Text("已复制微信号 \(AppConstants.wechatID)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(PhotoDelStyle.primaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(PhotoDelStyle.surface)
                    .overlay(
                        Capsule()
                            .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.24), radius: 12, x: 0, y: 8)
            .padding(.bottom, 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func settingsToastView(_ toast: PhotoDelToast) -> some View {
        VStack {
            Spacer()
            PhotoDelToastView(toast: toast)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var photoAccessSubtitle: String {
        switch dataManager.photoLibraryManager.authorizationStatus {
        case .authorized:
            return "已允许访问全部照片"
        case .limited:
            return "当前仅可访问 \(dataManager.photoLibraryManager.totalPhotosCount) 张照片"
        case .denied, .restricted:
            return "未授权，点击前往系统设置"
        case .notDetermined:
            return "尚未选择照片访问范围"
        @unknown default:
            return "点击查看系统照片权限"
        }
    }

    private var localDataSubtitle: String {
        let reviewedCount = dataManager.reviewedAssetIDs.count
        let pendingCount = dataManager.deleteCandidates.count + dataManager.favoriteCandidates.count
        if reviewedCount == 0 && pendingCount == 0 {
            return "没有本机整理记录"
        }
        return "已整理 \(reviewedCount) 张 · 候选 \(pendingCount) 张"
    }

    private var gestureSettingsSubtitle: String {
        let left = currentGestureAction(for: .left)
        let right = currentGestureAction(for: .right)
        let up = currentGestureAction(for: .up)
        return "左滑\(left.title) · 右滑\(right.title) · 上滑\(up.title)"
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
            showingMailCompose = true
        } else {
            openFeedbackMailURL()
        }
        #else
        openFeedbackMailURL()
        #endif
    }
    
    // MARK: - 方法
    private func openFeedbackMailURL() {
        let subject = "PhotoDel App 反馈".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(AppConstants.feedbackEmail)?subject=\(subject)") {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }
    }

    private func copyWeChatID() {
        #if canImport(UIKit)
        UIPasteboard.general.string = AppConstants.wechatID
        withAnimation(.easeInOut(duration: 0.18)) {
            showingWeChatCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.18)) {
                showingWeChatCopied = false
            }
        }
        #endif
    }

    private func clearLocalOrganizeData() {
        dataManager.clearLocalOrganizeData()
        showSettingsToast("已清空本机整理记录", icon: "checkmark.circle.fill", style: .positive)
    }

    private func resetIntro() {
        hasSeenPhotoDelIntro = false
        showSettingsToast("已恢复开屏引导", icon: "sparkles", style: .positive)
    }

    private func showSettingsToast(_ message: String, icon: String, style: PhotoDelToastStyle) {
        let toast = PhotoDelToast(message: message, icon: icon, style: style)
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

// MARK: - 统计卡片
struct StatCard: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(PhotoDelStyle.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 设置行
struct SettingRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var showsChevron = true
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(PhotoDelStyle.elevatedSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(iconColor.opacity(0.36), lineWidth: 1)
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(iconColor)
                }
                
                // 文字信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(PhotoDelStyle.primaryText)
                    
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                }
                
                Spacer()
                
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PhotoDelStyle.tertiaryText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(PhotoDelStyle.elevatedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(iconColor.opacity(0.36), lineWidth: 1)
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(PhotoDelStyle.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
                PhotoDelScreenBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        currentGesturePreview
                        presetSection
                        customGestureSection
                        resetButton
                    }
                    .padding(24)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("手势控制")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(PhotoDelStyle.accent)
                }
            }
        }
    }

    private var currentGesturePreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("当前手势")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)

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
            Text("快速方案")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)

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
            Text("自定义")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)

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
                            .background(PhotoDelStyle.hairline)
                            .padding(.leading, 60)
                    }
                }
            }
            .photoDelCard()
        }
    }

    private var resetButton: some View {
        Button(action: {
            applyPreset(.standard)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                Text("恢复默认")
            }
        }
        .photoDelSecondaryButton()
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
            Image(systemName: direction.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(action.tint)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(PhotoDelStyle.elevatedSurface)
                        .overlay(
                            Circle()
                                .stroke(action.tint.opacity(0.34), lineWidth: 1)
                        )
                )

            VStack(spacing: 3) {
                Text(direction.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(action.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDelStyle.secondaryText)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .photoDelCard(radius: 15)
    }
}

private struct GesturePresetButton: View {
    let preset: SwipeGesturePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text(preset.subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(isSelected ? PhotoDelStyle.positive : PhotoDelStyle.tertiaryText)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PhotoDelStyle.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? PhotoDelStyle.positive.opacity(0.38) : PhotoDelStyle.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct GestureActionPickerRow: View {
    let direction: SwipeGestureDirection
    let selectedAction: SwipeGestureAction
    let onSelect: (SwipeGestureAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: direction.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(selectedAction.tint)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(PhotoDelStyle.elevatedSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selectedAction.tint.opacity(0.32), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(direction.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(selectedAction.detailTitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
            }

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
                    Text(selectedAction.title)
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(PhotoDelStyle.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(PhotoDelStyle.elevatedSurface)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                        )
                )
            }
        }
        .padding(16)
    }
}

// MARK: - 邮件编写视图
#if canImport(MessageUI)
struct MailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setSubject("PhotoDel App 反馈")
        composer.setToRecipients([AppConstants.feedbackEmail])
        
        let body = """
        请在此处写下您的反馈和建议：
        
        
        
        ---
        App版本: \(AppConstants.version)
        设备信息: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        """
        composer.setMessageBody(body, isHTML: false)
        
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

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDelScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 14) {
                                AuthorAvatar()

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Created by Michael Jackie")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(PhotoDelStyle.primaryText)

                                    Text("免费的小相册整理工具")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(PhotoDelStyle.secondaryText)
                                }
                            }

                            Text("PhotoDel 是一个免费的相册整理小工具，目标是把删照片、归类照片这件事做得足够直接。")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Text("01MVP")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.primaryText)

                            Text("如果你也想用 AI 开发类似的小 App，可以看看 01mvp.com 的实战教程。")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)

                            Button(action: openWebsite) {
                                HStack(spacing: 8) {
                                    Text("打开 01mvp.com")
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                            .photoDelPrimaryButton()
                        }
                        .padding(18)
                        .photoDelCard(radius: 18)

                        VStack(alignment: .leading, spacing: 10) {
                            Label("微信反馈：\(AppConstants.wechatID)", systemImage: "bubble.left.and.bubble.right.fill")
                            Label("邮件反馈：\(AppConstants.feedbackEmail)", systemImage: "envelope.fill")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(PhotoDelStyle.secondaryText)

                        Spacer(minLength: 24)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("了解作者")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(PhotoDelStyle.accent)
                }
            }
        }
    }

    private func openWebsite() {
        if let url = URL(string: AppConstants.websiteURL) {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }
    }
}

struct AuthorAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(PhotoDelStyle.accent)
                .overlay(
                    Circle()
                        .stroke(PhotoDelStyle.primaryText.opacity(0.22), lineWidth: 1)
                )

            Text("MJ")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.84))
        }
        .frame(width: 62, height: 62)
        .shadow(color: PhotoDelStyle.accent.opacity(0.2), radius: 18, x: 0, y: 10)
        .accessibilityLabel("Michael Jackie")
    }
}

// MARK: - 隐私说明视图
struct PrivacyInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDelScreenBackground()

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("隐私优先")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.primaryText)

                        Text(AppConstants.privacyShortText)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        PrivacyInfoRow(
                            icon: "iphone",
                            title: "本机整理",
                            detail: "预览、候选列表和删除确认都保存在你的设备上。"
                        )

                        PrivacyInfoRow(
                            icon: "icloud.slash",
                            title: "不上传照片",
                            detail: "PhotoDel 不接入自己的云端服务，也不会把照片发到服务器。"
                        )

                        PrivacyInfoRow(
                            icon: "person.crop.circle.badge.xmark",
                            title: "不需要账号",
                            detail: "授权照片后即可使用，不需要注册或登录。"
                        )
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("隐私")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(PhotoDelStyle.accent)
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
                .foregroundColor(PhotoDelStyle.accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(PhotoDelStyle.elevatedSurface)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.primaryText)

                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .photoDelCard(radius: 16)
    }
}

// MARK: - 关于视图
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDelScreenBackground()

                VStack(spacing: 32) {
                    // App图标
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(PhotoDelStyle.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundColor(PhotoDelStyle.accent)
                    }
                    
                    // App信息
                    VStack(spacing: 16) {
                        Text("PhotoDel")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(PhotoDelStyle.primaryText)
                        
                        Text("版本 \(AppConstants.version)")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                        
                        Text("一个免费的相册整理工具。滑动判断照片去留，完成后再统一确认。")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                    
                    Spacer()
                    
                    // 版权信息
                    Text("Created by Michael Jackie")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(PhotoDelStyle.tertiaryText)
                }
                .padding(.horizontal, 32)
                .padding(.top, 60)
                .padding(.bottom, 32)
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(PhotoDelStyle.accent)
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
