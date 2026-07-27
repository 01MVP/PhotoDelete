//
//  OneAppsPromotion.swift
//  PhotoDelete
//
//  One Apps Studio catalog entry + dedicated "More Apps" page.
//  Layout mirrors OneAppsKit's catalog link → catalog page pattern.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum OneAppsPromotionCatalog {
    static let studioURL = URL(string: "https://oneapps.studio")!
    static let appsURL = URL(string: "https://oneapps.studio/apps")!

    /// Public One Apps products plus related MakerJackie apps we still promote.
    static let apps: [OneAppsPromotionItem] = [
        .init(
            id: "onescan",
            name: "OneScan",
            systemImage: "doc.viewfinder",
            assetImageName: "OneAppsIcon_onescan",
            subtitleKey: "私密文档扫描",
            summaryKey: "扫描纸质文档，在本地整理最近扫描，并按需导出清晰 PDF。",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6788495535"),
            productURL: URL(string: "https://oneapps.studio/apps/onescan")!
        ),
        .init(
            id: "onehabit",
            name: "OneHabit",
            systemImage: "checkmark.circle",
            assetImageName: "OneAppsIcon_onehabit",
            subtitleKey: "私密习惯追踪",
            summaryKey: "用灵活计划、清晰进度和私有同步，建立真正适合日常生活的习惯。",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6788409678"),
            productURL: URL(string: "https://oneapps.studio/apps/onehabit")!
        ),
        .init(
            id: "onepack",
            name: "OnePack",
            systemImage: "suitcase.rolling",
            assetImageName: "OneAppsIcon_onepack",
            subtitleKey: "可复用的打包清单",
            summaryKey: "从模板创建本次打包清单，逐项勾选，完成后归档，下次还能继续用。",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6788841724"),
            productURL: URL(string: "https://oneapps.studio/apps/onepack")!
        ),
        .init(
            id: "onefocus",
            name: "OneFocus",
            systemImage: "timer",
            assetImageName: "OneAppsIcon_onefocus",
            subtitleKey: "跨设备专注计时",
            summaryKey: "在 iPhone、iPad 与 Mac 上开始同一场专注，并查看真实保护状态。",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6790143964"),
            productURL: URL(string: "https://oneapps.studio/apps/onefocus")!
        ),
        .init(
            id: "onetune",
            name: "OneTune",
            systemImage: "tuningfork",
            assetImageName: "OneAppsIcon_onetune",
            subtitleKey: "调音器与节拍器",
            summaryKey: "离线乐器调音器，提供形象化指引、节拍器与常用和弦。",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6789659103"),
            productURL: URL(string: "https://oneapps.studio/apps/onetune")!
        ),
        .init(
            id: "oneuke",
            name: "OneUke",
            systemImage: "guitars.fill",
            assetImageName: "OneAppsIcon_oneuke",
            subtitleKey: "尤克里里零基础入门",
            summaryKey: "从调音、节奏与和弦开始，逐步弹出第一首熟悉旋律。",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6783200326"),
            productURL: URL(string: "https://oneapps.studio/apps/oneuke")!
        ),
        .init(
            id: "onemarkup",
            name: "OneMarkup",
            systemImage: "text.page.badge.magnifyingglass",
            assetImageName: "OneAppsIcon_onemarkup",
            subtitleKey: "Markdown 与 HTML 编辑",
            summaryKey: "快速打开、编辑并分享 Markdown、HTML、SVG 与纯文本，私密且离线。",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6792251542"),
            productURL: URL(string: "https://oneapps.studio/apps/onemarkup")!
        ),
        .init(
            id: "onevoice",
            name: "OneVoice",
            systemImage: "waveform",
            assetImageName: "OneAppsIcon_onevoice",
            subtitleKey: "录音与语音转文字",
            summaryKey: "录音、离线转写，并在 Apple 设备间通过私有 iCloud 同步。",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6789639056"),
            productURL: URL(string: "https://oneapps.studio/apps/onevoice")!
        ),
        .init(
            id: "oneround",
            name: "OneRound",
            systemImage: "person.2.circle.fill",
            assetImageName: "OneAppsIcon_oneround",
            subtitleKey: "双人面对面小游戏",
            summaryKey: "十款为两台附近 iPhone 打造的插画游戏，无需互联网或账号。",
            appStoreURL: nil,
            productURL: URL(string: "https://oneapps.studio/apps/oneround")!
        ),
        .init(
            id: "oneposture",
            name: "OnePosture",
            systemImage: "figure.stand",
            assetImageName: "OneAppsIcon_oneposture",
            subtitleKey: "本地坐姿提醒",
            summaryKey: "隐私优先的本地姿势监控，减少误报并提供可靠提醒。",
            appStoreURL: nil,
            productURL: URL(string: "https://oneapps.studio/apps/oneposture")!
        ),
        .init(
            id: "onezen",
            name: "OneZen",
            systemImage: "leaf.fill",
            assetImageName: "OneZenAppIcon",
            subtitleKey: "冥想、呼吸与专注练习",
            summaryKey: "用简短的冥想与呼吸练习，帮你更快安静下来。",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6780318004"),
            productURL: URL(string: "https://oneapps.studio")!
        )
    ]

    static func open(_ item: OneAppsPromotionItem) {
        open(item.destinationURL)
    }

    static func openStudio() {
        open(studioURL)
    }

    static func openAllApps() {
        open(appsURL)
    }

    private static func open(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

struct OneAppsPromotionItem: Identifiable, Equatable {
    let id: String
    let name: String
    let systemImage: String
    var assetImageName: String? = nil
    let subtitleKey: String
    let summaryKey: String
    let appStoreURL: URL?
    let productURL: URL

    var destinationURL: URL {
        appStoreURL ?? productURL
    }

    var subtitle: String {
        L10n.key(subtitleKey)
    }

    var summary: String {
        L10n.key(summaryKey)
    }
}

// MARK: - Settings entry (card only)

/// Settings entry that matches OneAppsKit's "More Apps" catalog link.
struct OneAppsPromotionSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.string("更多 App"))
                    .photoDeleteSectionHeading()
                Spacer()
            }

            NavigationLink {
                OneAppsCatalogPage()
            } label: {
                HStack(spacing: 12) {
                    Image("OneAppsStudioLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("One Apps Studio"))
                            .photoDeletePrimaryLabel()
                            .lineLimit(1)

                        Text(L10n.string("系列简洁好用的 App"))
                            .photoDeleteSecondaryLabel(.subheadline)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PhotoDeleteStyle.tertiaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(minHeight: PhotoDeleteStyle.rowMinHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .photoDeleteCard()
            .accessibilityIdentifier("settings-oneapps-catalog-entry")
            .accessibilityHint(L10n.string("打开完整的 App 列表"))
        }
    }
}

// MARK: - Dedicated catalog page

struct OneAppsCatalogPage: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(OneAppsPromotionCatalog.apps) { app in
                        NavigationLink {
                            OneAppsCatalogDetailPage(item: app)
                        } label: {
                            OneAppsCatalogAppRow(item: app)
                        }
                        .buttonStyle(.plain)
                    }

                    studioFooterCard
                        .padding(.top, 8)
                }
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L10n.string("更多 App"))
        .navigationBarTitleDisplayMode(.large)
    }

    private var studioFooterCard: some View {
        Button(action: OneAppsPromotionCatalog.openStudio) {
            VStack(spacing: 14) {
                Image("OneAppsStudioLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                    )
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(L10n.string("One Apps Studio"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(L10n.string("独立小而美的 App，专注、私密、好用。"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.string("每个 App 只解决一个小痛点，基础功能无广告、无限制。"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.tertiaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text(L10n.string("访问 OneApps.Studio"))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .photoDeleteCard()
        .accessibilityIdentifier("settings-oneapps-studio-link")
    }
}

// MARK: - App detail

struct OneAppsCatalogDetailPage: View {
    let item: OneAppsPromotionItem
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        OneAppsCatalogIcon(item: item, size: 64)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.primaryText)

                            Text(item.subtitle)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(item.summary)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .photoDeleteCard()

                    Button {
                        OneAppsPromotionCatalog.open(item)
                    } label: {
                        HStack(spacing: 8) {
                            Text(
                                item.appStoreURL == nil
                                    ? L10n.string("查看产品页")
                                    : L10n.string("在 App Store 查看")
                            )
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .photoDeletePrimaryButton()
                    .accessibilityIdentifier("settings-oneapps-\(item.id)-open")
                }
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared rows / icons

private struct OneAppsCatalogAppRow: View {
    let item: OneAppsPromotionItem

    var body: some View {
        HStack(spacing: 14) {
            OneAppsCatalogIcon(item: item, size: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PhotoDeleteStyle.tertiaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .contentShape(Rectangle())
        .photoDeleteCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.name))
        .accessibilityValue(Text(item.subtitle))
        .accessibilityIdentifier("settings-oneapps-\(item.id)-row")
    }
}

private struct OneAppsCatalogIcon: View {
    let item: OneAppsPromotionItem
    let size: CGFloat

    var body: some View {
        Group {
            if let assetImageName = item.assetImageName {
                Image(assetImageName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.systemImage)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PhotoDeleteStyle.accent.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .stroke(PhotoDeleteStyle.hairline, lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}
