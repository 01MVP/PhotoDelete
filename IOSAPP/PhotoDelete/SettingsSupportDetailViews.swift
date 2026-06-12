import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct MVPGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("从一个小功能开始"))
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)

                            Text(L10n.string("删图来自 01MVP 的小产品实践：先把一个真实问题做顺，再逐步补上体验和边界。"))
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 12) {
                            SettingsDetailRow(
                                icon: "scope",
                                title: L10n.string("先收窄问题"),
                                detail: L10n.string("只做相册整理里最常见的判断：删、留、收藏。")
                            )

                            SettingsDetailRow(
                                icon: "hand.tap",
                                title: L10n.string("让交互可重复"),
                                detail: L10n.string("用短手势处理高频动作，最后统一确认。")
                            )

                            SettingsDetailRow(
                                icon: "checkmark.seal",
                                title: L10n.string("再补可信细节"),
                                detail: L10n.string("权限、撤销、反馈和隐私说明都围绕实际使用补齐。")
                            )
                        }

                        Button(action: openWebsite) {
                            HStack(spacing: 8) {
                                Text(L10n.string("打开 01mvp.com"))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .photoDeletePrimaryButton()

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(L10n.string("MVP 教程"))
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

    private func openWebsite() {
        guard let url = URL(string: AppConstants.websiteURL) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

struct CreationPhilosophyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoDeleteScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("少打扰，多确认"))
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)

                            Text(L10n.string("删图的核心不是替你决定，而是让你更快、更安心地完成判断。"))
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 12) {
                            SettingsDetailRow(
                                icon: "rectangle.stack.badge.play",
                                title: L10n.string("先判断，再执行"),
                                detail: L10n.string("删除和收藏先进入候选列表，确认后才真正写入照片库。")
                            )

                            SettingsDetailRow(
                                icon: "iphone",
                                title: L10n.string("尽量留在本机"),
                                detail: L10n.string("整理进度、候选列表和统计都围绕本机照片库工作。")
                            )

                            SettingsDetailRow(
                                icon: "text.alignleft",
                                title: L10n.string("文案保持短"),
                                detail: L10n.string("高频界面只保留能帮助当下操作的信息。")
                            )
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(L10n.string("创作理念"))
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

private struct SettingsDetailRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PhotoDeleteIconTile(icon: icon, tint: PhotoDeleteStyle.accent, size: 34, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .photoDeleteCard()
    }
}
