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
    @State private var showingMailCompose = false
    @State private var showingAbout = false
    @State private var showingAuthor = false
    @State private var showingPrivacyInfo = false
    @State private var showingWeChatCopied = false
    
    var body: some View {
        NavigationView {
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
                    subtitle: "不需要账号，不上传照片",
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
                    subtitle: "mvps01",
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
                    subtitle: "contact@01mvp.com",
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
                    subtitle: "版本 1.0.0",
                    action: {
                        showingAbout = true
                    }
                )
            }
            .photoDelCard()
        }
    }
    
    // MARK: - 版本信息
    private var versionInfo: some View {
        VStack(spacing: 8) {
            Text("PhotoDel v1.0.0")
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

                Text("已复制微信号 mvps01")
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
        if let url = URL(string: "mailto:contact@01mvp.com?subject=\(subject)") {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }
    }

    private func copyWeChatID() {
        #if canImport(UIKit)
        UIPasteboard.general.string = "mvps01"
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
                
                // 箭头
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDelStyle.tertiaryText)
            }
            .padding(16)
        }
        .buttonStyle(PlainButtonStyle())
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
        composer.setToRecipients(["contact@01mvp.com"])
        
        let body = """
        请在此处写下您的反馈和建议：
        
        
        
        ---
        App版本: 1.0.0
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
        NavigationView {
            ZStack {
                PhotoDelScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("关于作者")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.primaryText)

                            Text("我是 Jackie，长期做独立产品、AI 工具和 01MVP 实战内容。PhotoDel 是一个很小的相册整理工具，目标是把删照片这件事做得足够直接。")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDelStyle.secondaryText)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Text("01MVP")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(PhotoDelStyle.primaryText)

                            Text("01mvp.com 是一个教你如何从 0 到 1 创作自己的小产品的网站，记录真实产品从想法、设计、开发到发布的过程。")
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
                            Label("微信反馈：mvps01", systemImage: "bubble.left.and.bubble.right.fill")
                            Label("邮件反馈：contact@01mvp.com", systemImage: "envelope.fill")
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
        .preferredColorScheme(.dark)
    }

    private func openWebsite() {
        if let url = URL(string: "https://01mvp.com") {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }
    }
}

// MARK: - 隐私说明视图
struct PrivacyInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                PhotoDelScreenBackground()

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("隐私优先")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.primaryText)

                        Text("PhotoDel 的照片整理流程不需要账号，也不会上传您的照片。")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        PrivacyInfoRow(
                            icon: "person.crop.circle.badge.xmark",
                            title: "不需要账号",
                            detail: "打开 App 后即可整理授权范围内的照片。"
                        )

                        PrivacyInfoRow(
                            icon: "icloud.slash",
                            title: "不上传照片",
                            detail: "照片判断、候选列表和批量确认都在设备上完成。"
                        )

                        PrivacyInfoRow(
                            icon: "link",
                            title: "主动打开外部链接才会离开 App",
                            detail: "例如官网、邮件反馈或系统设置。"
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
        .preferredColorScheme(.dark)
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
        NavigationView {
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
                        
                        Text("版本 1.0.0")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                        
                        Text("一款专注于照片整理和删除的移动应用，通过直观的滑动手势帮助用户快速清理手机中的照片。")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                    
                    Spacer()
                    
                    // 版权信息
                    Text("© 2025 PhotoDel Team. All rights reserved.")
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
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataManager())
}
