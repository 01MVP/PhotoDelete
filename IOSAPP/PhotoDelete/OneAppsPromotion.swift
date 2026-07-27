//
//  OneAppsPromotion.swift
//  PhotoDelete
//
//  Lightweight in-app catalog for One Apps Studio products.
//  Source of truth for product list: OneApps/Catalog + oneapps.studio
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
            subtitleKey: "私密文档扫描",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6788495535"),
            productURL: URL(string: "https://oneapps.studio/apps/onescan")!
        ),
        .init(
            id: "onehabit",
            name: "OneHabit",
            systemImage: "checkmark.circle",
            subtitleKey: "私密习惯追踪",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6788409678"),
            productURL: URL(string: "https://oneapps.studio/apps/onehabit")!
        ),
        .init(
            id: "onepack",
            name: "OnePack",
            systemImage: "suitcase.rolling",
            subtitleKey: "可复用的打包清单",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6788841724"),
            productURL: URL(string: "https://oneapps.studio/apps/onepack")!
        ),
        .init(
            id: "onefocus",
            name: "OneFocus",
            systemImage: "timer",
            subtitleKey: "跨设备专注计时",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6790143964"),
            productURL: URL(string: "https://oneapps.studio/apps/onefocus")!
        ),
        .init(
            id: "onetune",
            name: "OneTune",
            systemImage: "tuningfork",
            subtitleKey: "调音器与节拍器",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6789659103"),
            productURL: URL(string: "https://oneapps.studio/apps/onetune")!
        ),
        .init(
            id: "oneuke",
            name: "OneUke",
            systemImage: "guitars.fill",
            subtitleKey: "尤克里里零基础入门",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6783200326"),
            productURL: URL(string: "https://oneapps.studio/apps/oneuke")!
        ),
        .init(
            id: "onemarkup",
            name: "OneMarkup",
            systemImage: "text.page.badge.magnifyingglass",
            subtitleKey: "Markdown 与 HTML 编辑",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6792251542"),
            productURL: URL(string: "https://oneapps.studio/apps/onemarkup")!
        ),
        .init(
            id: "onevoice",
            name: "OneVoice",
            systemImage: "waveform",
            subtitleKey: "录音与语音转文字",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6789639056"),
            productURL: URL(string: "https://oneapps.studio/apps/onevoice")!
        ),
        .init(
            id: "oneround",
            name: "OneRound",
            systemImage: "person.2.circle.fill",
            subtitleKey: "双人面对面小游戏",
            appStoreURL: nil,
            productURL: URL(string: "https://oneapps.studio/apps/oneround")!
        ),
        .init(
            id: "oneposture",
            name: "OnePosture",
            systemImage: "figure.stand",
            subtitleKey: "本地坐姿提醒",
            appStoreURL: nil,
            productURL: URL(string: "https://oneapps.studio/apps/oneposture")!
        ),
        .init(
            id: "onezen",
            name: "OneZen",
            systemImage: "leaf.fill",
            assetImageName: "OneZenAppIcon",
            subtitleKey: "冥想、呼吸与专注练习",
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
    let appStoreURL: URL?
    let productURL: URL

    var destinationURL: URL {
        appStoreURL ?? productURL
    }

    var subtitle: String {
        L10n.key(subtitleKey)
    }
}

/// Settings section promoting the full One Apps Studio series.
struct OneAppsPromotionSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.string("One Apps 系列"))
                    .photoDeleteSectionHeading()
                Spacer()
            }

            studioIntroCard

            VStack(spacing: 0) {
                ForEach(Array(OneAppsPromotionCatalog.apps.enumerated()), id: \.element.id) { index, app in
                    OneAppsPromotionRow(item: app)

                    if index < OneAppsPromotionCatalog.apps.count - 1 {
                        Divider()
                            .background(PhotoDeleteStyle.hairline)
                            .padding(.leading, 64)
                    }
                }
            }
            .photoDeleteCard()

            Button(action: OneAppsPromotionCatalog.openAllApps) {
                HStack(spacing: 8) {
                    Text(L10n.string("在 OneApps.Studio 查看全部"))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings-oneapps-studio-link")
        }
    }

    private var studioIntroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PhotoDeleteStyle.accent.opacity(0.14))
                        .frame(width: 42, height: 42)

                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("One Apps Studio"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(L10n.string("可以无脑下载的系列 App"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)
            }

            Text(L10n.string("全部无广告，基础功能无限制，页面简洁。每个 App 只专注解决一个小痛点。"))
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                OneAppsPill(text: L10n.string("无广告"))
                OneAppsPill(text: L10n.string("基础无限制"))
                OneAppsPill(text: L10n.string("一 App 一痛点"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .photoDeleteCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(
                "\(L10n.string("One Apps Studio")). \(L10n.string("可以无脑下载的系列 App")). \(L10n.string("全部无广告，基础功能无限制，页面简洁。每个 App 只专注解决一个小痛点。"))"
            )
        )
    }
}

private struct OneAppsPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(PhotoDeleteStyle.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(PhotoDeleteStyle.elevatedSurface)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                    )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct OneAppsPromotionRow: View {
    let item: OneAppsPromotionItem

    var body: some View {
        Button {
            OneAppsPromotionCatalog.open(item)
        } label: {
            HStack(spacing: 12) {
                appIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .photoDeletePrimaryLabel()
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Text(item.subtitle)
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
        .accessibilityLabel(Text(item.name))
        .accessibilityValue(Text(item.subtitle))
        .accessibilityIdentifier("settings-oneapps-\(item.id)-row")
    }

    @ViewBuilder
    private var appIcon: some View {
        if let assetImageName = item.assetImageName {
            Image(assetImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PhotoDeleteStyle.accent.opacity(0.12))
                    .frame(width: 38, height: 38)

                Image(systemName: item.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
            )
        }
    }
}
