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
    @State private var animateCards = false

    let onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "photo.on.rectangle.angled",
            title: "快速整理相册",
            message: "用左右滑浏览照片，把想删除的先放进候选列表。完成前不会真正删除。"
        ),
        OnboardingPage(
            icon: "hand.draw",
            title: "手势很简单",
            message: "左滑待删除，右滑保留跳过，上滑加入收藏。需要时可以马上撤销。"
        ),
        OnboardingPage(
            icon: "lock.shield",
            title: "隐私优先",
            message: "不需要账号，不上传照片，也不连接服务器。只有你主动打开官网或邮件反馈时才会离开 App。"
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
                            animateCards: animateCards && selectedPage == index
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
                animateCards = true
            }
        }
        .onChange(of: selectedPage) { _ in
            animateCards = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
                    animateCards = true
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
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let index: Int
    let animateCards: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 34) {
                Spacer(minLength: 18)

                ZStack {
                    IntroPhotoStack(animate: animateCards, pageIndex: index)

                    Image(systemName: page.icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.accent)
                        .frame(width: 82, height: 82)
                        .background(
                            Circle()
                                .fill(PhotoDelStyle.background.opacity(0.86))
                                .overlay(
                                    Circle()
                                        .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                                )
                        )
                        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 12)
                        .scaleEffect(animateCards ? 1 : 0.86)
                        .opacity(animateCards ? 1 : 0)
                }
                .frame(width: min(geometry.size.width - 64, 310), height: min(geometry.size.height * 0.42, 300))

                VStack(spacing: 12) {
                    Text(page.title)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)
                        .multilineTextAlignment(.center)

                    Text(page.message)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 18)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct IntroPhotoStack: View {
    let animate: Bool
    let pageIndex: Int

    var body: some View {
        ZStack {
            introCard(offset: CGSize(width: animate ? -46 : -16, height: animate ? 18 : 0), rotation: animate ? -9 : -2, symbol: "photo", opacity: 0.68)
            introCard(offset: CGSize(width: animate ? 42 : 16, height: animate ? -10 : 0), rotation: animate ? 8 : 2, symbol: "sparkles", opacity: 0.8)
            introCard(offset: .zero, rotation: 0, symbol: centerSymbol, opacity: 1)
        }
    }

    private var centerSymbol: String {
        switch pageIndex {
        case 1:
            return "arrow.left.and.right"
        case 2:
            return "lock"
        default:
            return "rectangle.stack"
        }
    }

    private func introCard(offset: CGSize, rotation: Double, symbol: String, opacity: Double) -> some View {
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
                    .foregroundColor(PhotoDelStyle.primaryText.opacity(0.48))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(PhotoDelStyle.hairline, lineWidth: 1)
            )
            .frame(width: 170, height: 220)
            .opacity(opacity)
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .animation(.spring(response: 0.7, dampingFraction: 0.76), value: animate)
    }
}

#Preview {
    ContentView()
}
