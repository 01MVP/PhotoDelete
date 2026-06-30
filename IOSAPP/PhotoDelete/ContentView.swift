//
//  ContentView.swift
//  PhotoDelete
//
//  Created by jackie xiao on 11/7/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @AppStorage(AppConstants.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @AppStorage(AppConstants.hasSeenIntroKey) private var hasSeenHomeIntro = false
    @StateObject private var dataManager = DataManager()

    var body: some View {
        if hasCompletedOnboarding {
            MainTabView()
                .environmentObject(dataManager)
                .environmentObject(purchaseManager)
        } else {
            OnboardingFlowView(
                onSkip: {
                    hasSeenHomeIntro = false
                    hasCompletedOnboarding = true
                },
                onComplete: {
                    hasSeenHomeIntro = true
                    hasCompletedOnboarding = true
                    DispatchQueue.main.async {
                        dataManager.requestPhotoLibraryAccess()
                    }
                }
            )
        }
    }
}

private struct OnboardingFlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPage = 0
    @State private var animateVisual = false

    let onSkip: () -> Void
    let onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "photo.on.rectangle.angled",
            title: L10n.string("让照片整理变得简单"),
            message: L10n.string("用滑动快速判断照片去留。想删除的照片会先进入待确认列表，完成前不会真正删除。"),
            visual: .organize
        ),
        OnboardingPage(
            icon: "hand.draw",
            title: L10n.string("左滑删除，右滑保留"),
            message: L10n.string("左滑删除，右滑保留，上滑收藏。点完成后再统一确认。"),
            visual: .swipe
        ),
        OnboardingPage(
            icon: "externaldrive",
            title: L10n.string("找回更多空间"),
            message: L10n.string("相似照片、大文件、视频压缩和图片压缩集中在高级清理里，适合处理真正占空间的内容。"),
            visual: .advanced
        ),
        OnboardingPage(
            icon: "lock.shield",
            title: L10n.string("照片不会上传"),
            message: L10n.string("不需要账号，也不会上传照片。点开始后才会请求访问照片库。"),
            visual: .privacy
        )
    ]

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            VStack(spacing: 0) {
                OnboardingHeaderView(onSkip: onSkip)

                TabView(selection: $selectedPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(
                            page: page,
                            index: index,
                            animateVisual: animateVisual && selectedPage == index
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 18) {
                    OnboardingPageIndicator(
                        pageCount: pages.count,
                        selectedPage: selectedPage
                    )

                    Button(action: advance) {
                        HStack(spacing: 8) {
                            Text(selectedPage == pages.count - 1 ? L10n.string("开始整理照片") : L10n.string("继续"))

                            Image(systemName: selectedPage == pages.count - 1 ? "checkmark" : "arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .photoDeletePrimaryButton()
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            guard !reduceMotion else {
                animateVisual = true
                return
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.12)) {
                animateVisual = true
            }
        }
        .onChange(of: selectedPage) { _ in
            guard !reduceMotion else {
                animateVisual = true
                return
            }
            animateVisual = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
                    animateVisual = true
                }
            }
        }
    }

    private func advance() {
        if selectedPage < pages.count - 1 {
            selectedPage += 1
        } else {
            onComplete()
        }
    }
}

private struct OnboardingHeaderView: View {
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label {
                Text(AppConstants.appDisplayName)
                    .font(.callout.weight(.semibold))
            } icon: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(PhotoDeleteStyle.primaryText)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(PhotoDeleteStyle.elevatedSurface)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                    )
            )

            Spacer()

            Button(action: onSkip) {
                Text(L10n.string("跳过"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(PhotoDeleteStyle.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .photoDeleteMinimumTapTarget()
            .accessibilityHint(L10n.string("稍后也可以在设置里重新查看引导。"))
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }
}

private struct OnboardingPageIndicator: View {
    let pageCount: Int
    let selectedPage: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == selectedPage ? PhotoDeleteStyle.accent : PhotoDeleteStyle.hairline)
                    .frame(width: index == selectedPage ? 24 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedPage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("引导页"))
        .accessibilityValue(
            Text(
                String(
                    format: L10n.string("第 %lld/%lld 页"),
                    Int64(selectedPage + 1),
                    Int64(pageCount)
                )
            )
        )
    }
}

private struct OnboardingPage {
    let icon: String
    let title: String
    let message: String
    let visual: OnboardingVisual
    var linkTitle: String?
    var linkURL: URL?
}

private enum OnboardingVisual {
    case organize
    case swipe
    case advanced
    case privacy
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let index: Int
    let animateVisual: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 26) {
                    OnboardingVisualView(page: page, animate: animateVisual)
                        .frame(width: min(geometry.size.width - 54, 322), height: min(geometry.size.height * 0.4, 292))
                        .accessibilityHidden(true)

                    VStack(spacing: 12) {
                        Text(page.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(PhotoDeleteStyle.primaryText)
                            .multilineTextAlignment(.center)

                        Text(page.message)
                            .font(.body)
                            .foregroundStyle(PhotoDeleteStyle.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        if let linkTitle = page.linkTitle, let linkURL = page.linkURL {
                            Link(destination: linkURL) {
                                Label(linkTitle, systemImage: "arrow.up.right")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(PhotoDeleteStyle.accent)
                                    .labelStyle(.titleAndIcon)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 22)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct OnboardingVisualView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let page: OnboardingPage
    let animate: Bool

    var body: some View {
        Group {
            switch page.visual {
            case .organize:
                OrganizeIntroVisual(animate: animate)
            case .swipe:
                SwipeIntroVisual(animate: animate)
            case .advanced:
                AdvancedCleanupIntroVisual(animate: animate)
            case .privacy:
                PrivacyIntroVisual(animate: animate)
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }
}

private struct OrganizeIntroVisual: View {
    let animate: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(PhotoDeleteStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                )
                .frame(width: 254, height: 238)

            VStack(spacing: 18) {
                ZStack {
                    MiniPhotoCard(symbol: "photo", tint: PhotoDeleteStyle.secondaryText)
                        .rotationEffect(.degrees(animate ? -10 : -4))
                        .offset(x: animate ? -46 : -22, y: animate ? 12 : 2)

                    MiniPhotoCard(symbol: "sparkles", tint: PhotoDeleteStyle.accent)
                        .rotationEffect(.degrees(animate ? 10 : 3))
                        .offset(x: animate ? 44 : 20, y: animate ? -10 : 0)

                    MiniPhotoCard(symbol: "checkmark.circle", tint: PhotoDeleteStyle.positive)
                        .scaleEffect(animate ? 0.9 : 1)
                        .offset(y: animate ? 48 : 0)
                }
                .frame(height: 162)

                HStack(spacing: 8) {
                    Image(systemName: "tray.full")
                    Text(L10n.string("待确认列表"))
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText.opacity(0.78))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(PhotoDeleteStyle.elevatedSurface)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                        )
                )
            }

            Capsule(style: .continuous)
                .fill(PhotoDeleteStyle.accent)
                .frame(width: animate ? 124 : 34, height: 5)
                .offset(y: 104)
        }
        .animation(.spring(response: 0.76, dampingFraction: 0.78), value: animate)
    }
}

private struct SwipeIntroVisual: View {
    let animate: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(PhotoDeleteStyle.surface.opacity(0.72))
                .frame(width: 194, height: 212)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                )

            MiniPhotoCard(symbol: "photo", tint: PhotoDeleteStyle.primaryText.opacity(0.72), width: 122, height: 162)
                .overlay(
                    VStack {
                        Spacer()
                        HStack(spacing: 22) {
                            Image(systemName: "arrow.left")
                            Image(systemName: "arrow.up")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.accent)
                        .padding(.bottom, 17)
                    }
                )
                .rotationEffect(.degrees(animate ? -5 : 4))
                .offset(x: animate ? -20 : 20, y: animate ? -4 : 5)

            swipeDestination(
                symbol: "arrow.left",
                direction: L10n.string("左滑"),
                action: L10n.string("删除"),
                color: PhotoDeleteStyle.destructive,
                x: -118,
                y: 12
            )
            swipeDestination(
                symbol: "arrow.right",
                direction: L10n.string("右滑"),
                action: L10n.string("保留"),
                color: PhotoDeleteStyle.positive,
                x: 118,
                y: 12
            )
            swipeDestination(
                symbol: "arrow.up",
                direction: L10n.string("上滑"),
                action: L10n.string("收藏"),
                color: PhotoDeleteStyle.accent,
                x: 0,
                y: -106
            )
        }
        .animation(.spring(response: 0.72, dampingFraction: 0.84), value: animate)
    }

    private func swipeDestination(symbol: String, direction: String, action: String, color: Color, x: CGFloat, y: CGFloat) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))

            VStack(spacing: 1) {
                Text(direction)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)

                Text(action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
        .foregroundColor(color)
        .frame(width: 82, height: 68)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(color.opacity(0.28), lineWidth: 1)
                )
        )
        .scaleEffect(animate ? 1 : 0.88)
        .opacity(animate ? 1 : 0.52)
        .offset(x: x, y: y)
        .animation(.spring(response: 0.72, dampingFraction: 0.86), value: animate)
    }
}

private struct AdvancedCleanupIntroVisual: View {
    let animate: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PhotoDeleteStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                )
                .frame(width: 262, height: 236)

            VStack(spacing: 10) {
                advancedToolRow(
                    icon: "square.stack.3d.down.right",
                    title: L10n.string("相似照片"),
                    tint: PhotoDeleteStyle.accent,
                    delayIndex: 0
                )

                advancedToolRow(
                    icon: "externaldrive",
                    title: L10n.string("大文件"),
                    tint: PhotoDeleteStyle.warning,
                    delayIndex: 1
                )

                advancedToolRow(
                    icon: "video.badge.checkmark",
                    title: L10n.string("视频压缩"),
                    tint: PhotoDeleteStyle.positive,
                    delayIndex: 2
                )

                advancedToolRow(
                    icon: "photo.badge.arrow.down",
                    title: L10n.string("图片压缩"),
                    tint: PhotoDeleteStyle.accent,
                    delayIndex: 3
                )
            }
            .padding(.horizontal, 28)
        }
        .animation(.spring(response: 0.72, dampingFraction: 0.86), value: animate)
    }

    private func advancedToolRow(icon: String, title: String, tint: Color, delayIndex: Int) -> some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(icon: icon, tint: tint, size: 34, cornerRadius: 10)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                )
        )
        .offset(y: animate ? 0 : 16)
        .opacity(animate ? 1 : 0.35)
        .animation(.spring(response: 0.62, dampingFraction: 0.84).delay(Double(delayIndex) * 0.06), value: animate)
    }
}

private struct PrivacyIntroVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animate: Bool

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(PhotoDeleteStyle.accent.opacity(0.08 + Double(index) * 0.04), lineWidth: 1)
                    .frame(width: CGFloat(160 + index * 48), height: CGFloat(160 + index * 48))
                    .scaleEffect(animate ? 1.03 : 0.94)
                    .opacity(animate ? 1 : 0.5)
            }

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(PhotoDeleteStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                )
                .frame(width: 210, height: 230)

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(PhotoDeleteStyle.elevatedSurface)
                        .frame(width: 116, height: 94)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                        )

                    Image(systemName: "lock.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.accent)
                        .scaleEffect(animate ? 1 : 0.92)
                        .shadow(color: PhotoDeleteStyle.accent.opacity(0.22), radius: animate ? 18 : 6, x: 0, y: 0)
                }

                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                    Text(L10n.string("在手机上完成"))
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText.opacity(0.76))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.86), value: animate)
    }
}

private struct MiniPhotoCard: View {
    let symbol: String
    let tint: Color
    var width: CGFloat = 112
    var height: CGFloat = 146

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        PhotoDeleteStyle.elevatedSurface,
                        PhotoDeleteStyle.surface
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
            )
            .frame(width: width, height: height)
            .shadow(color: PhotoDeleteStyle.floatingShadow, radius: 12, x: 0, y: 7)
    }
}

#Preview {
    ContentView()
        .environmentObject(PurchaseManager())
}
