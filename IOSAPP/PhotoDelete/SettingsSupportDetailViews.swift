import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct CreatorMVPGuideSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("想要做自己的小产品？"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(L10n.string("删图是我用 AI 从 0 到 1 做出来的——发现痛点、写代码、上架，全程记录在 01MVP。不管你是想做自己的小产品，还是单纯好奇 AI 写代码能到什么程度，都可以看看。"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                MVPGuidePointRow(
                    icon: "scope",
                    title: L10n.string("看真实项目拆解"),
                    detail: L10n.string("从想法到上架的完整过程。")
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.leading, 48)

                MVPGuidePointRow(
                    icon: "book.closed",
                    title: L10n.string("拿能直接改的代码模板"),
                    detail: L10n.string("包括这个 App 的源码。")
                )

                Divider()
                    .background(PhotoDeleteStyle.hairline)
                    .padding(.leading, 48)

                MVPGuidePointRow(
                    icon: "shippingbox",
                    title: L10n.string("学用 AI 写代码的方法"),
                    detail: L10n.string("从零开始，一步步走。")
                )
            }
            .padding(.vertical, 2)

            Text(L10n.string("适合想把一个小想法真正做出来的人。"))
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openWebsite) {
                HStack(spacing: 8) {
                    Text(L10n.string("查看 01MVP 教程"))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .photoDeletePrimaryButton()
        }
        .padding(18)
        .photoDeleteCard()
    }

    private func openWebsite() {
        guard let url = URL(string: AppConstants.websiteURL) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

private struct MVPGuidePointRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PhotoDeleteIconTile(icon: icon, size: 34, cornerRadius: 10)
                .accessibilityHidden(true)

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
        .padding(.vertical, 12)
    }
}
