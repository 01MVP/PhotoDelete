import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum PhotoDelStyle {
    static let background = Color(red: 0.035, green: 0.037, blue: 0.042)
    static let backgroundTop = Color(red: 0.058, green: 0.06, blue: 0.068)
    static let surface = Color.white.opacity(0.075)
    static let elevatedSurface = Color.white.opacity(0.105)
    static let hairline = Color.white.opacity(0.115)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.42)
    static let accent = Color(red: 0.64, green: 0.78, blue: 1.0)
    static let destructive = Color(red: 1.0, green: 0.38, blue: 0.34)
    static let positive = Color(red: 0.5, green: 0.9, blue: 0.64)
    static let warning = Color(red: 1.0, green: 0.79, blue: 0.47)

    #if canImport(UIKit)
    static let uiBackground = UIColor(red: 0.035, green: 0.037, blue: 0.042, alpha: 1)
    static let uiAccent = UIColor(red: 0.64, green: 0.78, blue: 1.0, alpha: 1)
    static let uiSecondaryText = UIColor(white: 1.0, alpha: 0.58)
    #endif

    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14

    static func iconTint(for key: String) -> Color {
        switch key {
        case "delete", "trash": return destructive
        case "favorite", "heart": return Color(red: 1.0, green: 0.62, blue: 0.72)
        case "video": return Color(red: 0.72, green: 0.7, blue: 1.0)
        default: return accent
        }
    }
}

struct PhotoDelScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                PhotoDelStyle.backgroundTop,
                PhotoDelStyle.background
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct PhotoDelCardBackground: ViewModifier {
    var radius: CGFloat = PhotoDelStyle.cardRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(PhotoDelStyle.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                    )
            )
    }
}

struct PhotoDelPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Color.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: PhotoDelStyle.controlRadius, style: .continuous)
                    .fill(PhotoDelStyle.accent)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct PhotoDelSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(PhotoDelStyle.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: PhotoDelStyle.controlRadius, style: .continuous)
                    .fill(PhotoDelStyle.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PhotoDelStyle.controlRadius, style: .continuous)
                            .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                    )
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.74 : 1) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension View {
    func photoDelCard(radius: CGFloat = PhotoDelStyle.cardRadius) -> some View {
        modifier(PhotoDelCardBackground(radius: radius))
    }

    func photoDelPrimaryButton() -> some View {
        buttonStyle(PhotoDelPrimaryButtonStyle())
    }

    func photoDelSecondaryButton() -> some View {
        buttonStyle(PhotoDelSecondaryButtonStyle())
    }
}
