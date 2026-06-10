//
//  ContentView.swift
//  PhotoDel
//
//  Created by jackie xiao on 11/7/25.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedPhotoDelOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasSeenPhotoDelIntro") private var hasSeenHomeIntro = false

    var body: some View {
        if hasCompletedOnboarding {
            SplashView()
        } else {
            OnboardingFlowView {
                hasSeenHomeIntro = true
                hasCompletedOnboarding = true
            }
        }
    }
}

private struct OnboardingFlowView: View {
    @State private var selectedPage = 0
    @State private var animateVisual = false

    let onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "photo.on.rectangle.angled",
            title: "快速整理相册",
            message: "用左右滑浏览照片，把想删除的先放进候选列表。完成前不会真正删除。",
            visual: .organize
        ),
        OnboardingPage(
            icon: "hand.draw",
            title: "手势很简单",
            message: "左滑待删除，右滑保留跳过，上滑加入收藏。需要时可以马上撤销。",
            visual: .swipe
        ),
        OnboardingPage(
            icon: "lock.shield",
            title: "隐私优先",
            message: "整理在手机上完成。只有你主动打开官网或邮件反馈时，才会离开 PhotoDel。",
            visual: .privacy
        ),
        OnboardingPage(
            icon: "sparkles",
            title: "Created by MakerJackie",
            message: "PhotoDel 是一个很小的 01MVP。如果你也想从 0 到 1 做自己的小产品，可以看看 01MVP。",
            visual: .maker,
            linkTitle: "了解 01MVP",
            linkURL: URL(string: "https://01mvp.com")
        )
    ]

    var body: some View {
        ZStack {
            PhotoDelScreenBackground()

            VStack(spacing: 0) {
                HStack {
                    Spacer()

                    Button("跳过") {
                        onComplete()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(PhotoDelStyle.secondaryText)
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                }

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

                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { index in
                            Capsule(style: .continuous)
                                .fill(index == selectedPage ? PhotoDelStyle.accent : PhotoDelStyle.hairline)
                                .frame(width: index == selectedPage ? 24 : 7, height: 7)
                                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedPage)
                        }
                    }

                    Button(action: advance) {
                        HStack(spacing: 8) {
                            Text(selectedPage == pages.count - 1 ? "开始整理" : "继续")

                            Image(systemName: selectedPage == pages.count - 1 ? "checkmark" : "arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .photoDelPrimaryButton()
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 34)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.12)) {
                animateVisual = true
            }
        }
        .onChange(of: selectedPage) { _ in
            animateVisual = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
                    animateVisual = true
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func advance() {
        if selectedPage < pages.count - 1 {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                selectedPage += 1
            }
        } else {
            onComplete()
        }
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
    case privacy
    case maker
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let index: Int
    let animateVisual: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 30) {
                Spacer(minLength: 18)

                OnboardingVisualView(page: page, animate: animateVisual)
                    .frame(width: min(geometry.size.width - 54, 322), height: min(geometry.size.height * 0.42, 306))

                VStack(spacing: 12) {
                    Text(page.title)
                        .font(.system(size: page.visual == .maker ? 26 : 30, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.86)

                    Text(page.message)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if let linkTitle = page.linkTitle, let linkURL = page.linkURL {
                        Link(destination: linkURL) {
                            HStack(spacing: 7) {
                                Text(linkTitle)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.accent)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 18)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct OnboardingVisualView: View {
    let page: OnboardingPage
    let animate: Bool

    var body: some View {
        switch page.visual {
        case .organize:
            OrganizeIntroVisual(animate: animate)
        case .swipe:
            SwipeIntroVisual(animate: animate)
        case .privacy:
            PrivacyIntroVisual(animate: animate)
        case .maker:
            MakerIntroVisual(animate: animate)
        }
    }
}

private struct OrganizeIntroVisual: View {
    let animate: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(PhotoDelStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                )
                .frame(width: 254, height: 238)

            VStack(spacing: 18) {
                ZStack {
                    MiniPhotoCard(symbol: "photo", tint: PhotoDelStyle.secondaryText)
                        .rotationEffect(.degrees(animate ? -10 : -4))
                        .offset(x: animate ? -46 : -22, y: animate ? 12 : 2)

                    MiniPhotoCard(symbol: "sparkles", tint: PhotoDelStyle.accent)
                        .rotationEffect(.degrees(animate ? 10 : 3))
                        .offset(x: animate ? 44 : 20, y: animate ? -10 : 0)

                    MiniPhotoCard(symbol: "checkmark.circle", tint: PhotoDelStyle.positive)
                        .scaleEffect(animate ? 0.9 : 1)
                        .offset(y: animate ? 48 : 0)
                }
                .frame(height: 162)

                HStack(spacing: 8) {
                    Image(systemName: "tray.full")
                    Text("候选列表")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText.opacity(0.78))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(PhotoDelStyle.elevatedSurface)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                        )
                )
            }

            Capsule(style: .continuous)
                .fill(PhotoDelStyle.accent)
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
            swipeDestination(symbol: "trash", text: "左滑", color: PhotoDelStyle.destructive, x: -102, y: 8)
            swipeDestination(symbol: "arrow.right", text: "右滑", color: PhotoDelStyle.positive, x: 102, y: 8)
            swipeDestination(symbol: "heart", text: "上滑", color: Color(red: 1.0, green: 0.62, blue: 0.72), x: 0, y: -104)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PhotoDelStyle.surface)
                .frame(width: 236, height: 236)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                )

            MiniPhotoCard(symbol: "photo", tint: PhotoDelStyle.primaryText.opacity(0.72), width: 132, height: 174)
                .overlay(
                    VStack {
                        Spacer()
                        HStack(spacing: 28) {
                            Image(systemName: "arrow.left")
                            Image(systemName: "arrow.up")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.accent)
                        .padding(.bottom, 18)
                    }
                )
                .rotationEffect(.degrees(animate ? -7 : 7))
                .offset(x: animate ? -38 : 38, y: animate ? -6 : 8)
                .animation(.easeInOut(duration: 1.18).repeatForever(autoreverses: true), value: animate)
        }
    }

    private func swipeDestination(symbol: String, text: String, color: Color, x: CGFloat, y: CGFloat) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))

            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(color)
        .frame(width: 70, height: 58)
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
        .animation(.spring(response: 0.7, dampingFraction: 0.74), value: animate)
    }
}

private struct PrivacyIntroVisual: View {
    let animate: Bool

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(PhotoDelStyle.accent.opacity(0.08 + Double(index) * 0.04), lineWidth: 1)
                    .frame(width: CGFloat(160 + index * 48), height: CGFloat(160 + index * 48))
                    .scaleEffect(animate ? 1.03 : 0.94)
                    .opacity(animate ? 1 : 0.5)
            }

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(PhotoDelStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                )
                .frame(width: 210, height: 230)

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(PhotoDelStyle.elevatedSurface)
                        .frame(width: 116, height: 94)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                        )

                    Image(systemName: "lock.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.accent)
                        .scaleEffect(animate ? 1 : 0.92)
                        .shadow(color: PhotoDelStyle.accent.opacity(0.22), radius: animate ? 18 : 6, x: 0, y: 0)
                }

                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                    Text("在手机上完成")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText.opacity(0.76))
            }
        }
        .animation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true), value: animate)
    }
}

private struct MakerIntroVisual: View {
    let animate: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(PhotoDelStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                )
                .frame(width: 254, height: 238)

            VStack(spacing: 20) {
                HStack(spacing: 14) {
                    productNode(text: "0", subtitle: "想法", filled: true)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.accent)
                        .offset(x: animate ? 4 : -2)
                    productNode(text: "1", subtitle: "产品", filled: animate)
                }

                VStack(spacing: 8) {
                    Text("01MVP")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text("MakerJackie")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(PhotoDelStyle.elevatedSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                        )
                )
            }
        }
        .animation(.spring(response: 0.72, dampingFraction: 0.72), value: animate)
    }

    private func productNode(text: String, subtitle: String, filled: Bool) -> some View {
        VStack(spacing: 6) {
            Text(text)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(filled ? Color.black.opacity(0.86) : PhotoDelStyle.primaryText)
                .frame(width: 70, height: 70)
                .background(
                    Circle()
                        .fill(filled ? PhotoDelStyle.accent : PhotoDelStyle.elevatedSurface)
                        .overlay(
                            Circle()
                                .stroke(filled ? PhotoDelStyle.accent.opacity(0.35) : PhotoDelStyle.hairline, lineWidth: 1)
                        )
                )

            Text(subtitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PhotoDelStyle.secondaryText)
        }
        .scaleEffect(filled ? 1 : 0.92)
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
                        PhotoDelStyle.elevatedSurface,
                        PhotoDelStyle.surface
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
                    .stroke(PhotoDelStyle.hairline, lineWidth: 1)
            )
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 12)
    }
}

#Preview {
    ContentView()
}
