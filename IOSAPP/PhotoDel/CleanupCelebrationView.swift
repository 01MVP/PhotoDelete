//
//  CleanupCelebrationView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 6/11/26.
//

import SwiftUI

struct CleanupCelebrationOverlay: View {
    let celebration: CleanupCelebration
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private let colors: [Color] = [
        PhotoDelStyle.accent,
        PhotoDelStyle.positive,
        PhotoDelStyle.warning,
        PhotoDelStyle.iconTint(for: "favorite")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 18) {
                ZStack {
                    if reduceMotion {
                        Image(systemName: "sparkles")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.warning)
                    } else {
                        ForEach(0..<28, id: \.self) { index in
                            fireworkParticle(index: index)
                        }

                        Image(systemName: "sparkles")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundColor(PhotoDelStyle.warning)
                            .scaleEffect(animate ? 1.08 : 0.82)
                            .animation(.spring(response: 0.36, dampingFraction: 0.56), value: animate)
                    }
                }
                .frame(width: 210, height: 150)

                VStack(spacing: 8) {
                    Text(L10n.string("清理完成"))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(PhotoDelStyle.primaryText)

                    Text(L10n.string("已删除 \(celebration.deletedPhotos) 张照片，节省 \(celebration.formattedSpaceSaved)。"))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                HStack(spacing: 10) {
                    CleanupCelebrationMetric(
                        value: "\(celebration.totalDeletedPhotos)",
                        label: L10n.string("累计删除"),
                        tint: PhotoDelStyle.destructive
                    )

                    CleanupCelebrationMetric(
                        value: celebration.formattedTotalSpaceSaved,
                        label: L10n.string("累计节省"),
                        tint: PhotoDelStyle.positive
                    )
                }

                Button(action: onDismiss) {
                    Text(L10n.string("继续整理"))
                }
                .photoDelPrimaryButton()
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(PhotoDelStyle.background.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(PhotoDelStyle.cardStroke, lineWidth: 1)
                    )
            )
            .shadow(color: PhotoDelStyle.floatingShadow, radius: 18, x: 0, y: 8)
            .padding(.horizontal, PhotoDelStyle.screenHorizontalPadding)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .onAppear {
            guard !reduceMotion else { return }
            animate = true
        }
    }

    private func fireworkParticle(index: Int) -> some View {
        let angle = Double(index) / 28.0 * Double.pi * 2
        let distance = CGFloat(48 + (index % 5) * 16)
        let x = CGFloat(cos(angle)) * distance
        let y = CGFloat(sin(angle)) * distance
        let size = CGFloat(5 + (index % 4) * 2)

        return Circle()
            .fill(colors[index % colors.count])
            .frame(width: size, height: size)
            .offset(x: animate ? x : 0, y: animate ? y : 0)
            .opacity(animate ? 0 : 1)
            .scaleEffect(animate ? 0.25 : 1)
            .animation(
                .easeOut(duration: 0.82)
                    .delay(Double(index % 7) * 0.025),
                value: animate
            )
    }
}

private struct CleanupCelebrationMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PhotoDelStyle.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PhotoDelStyle.elevatedSurface)
        )
    }
}
