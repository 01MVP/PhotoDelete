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

// MARK: - App Constants
enum AppConstants {
    static let version = "1.0.0"
    static let feedbackEmail = "contact@01mvp.com"
    static let wechatID = "mvps01"
    static let websiteURL = "https://01mvp.com"
    static let landscapeBreakpoint: CGFloat = 700
    static let hapticsEnabledKey = "photoDelHapticsEnabled"
    static let customAlbumOrderKey = "photoDelCustomAlbumOrder"
    static let leftSwipeActionKey = "photoDelLeftSwipeAction"
    static let rightSwipeActionKey = "photoDelRightSwipeAction"
    static let upSwipeActionKey = "photoDelUpSwipeAction"
    static let supporterProductID = "com.01mvp.photodel.supporter.stats"
    static let supporterEntitlementKey = "photoDelSupporterUnlocked"
    static let supporterThemeKey = "photoDelSupporterTheme"
    static let privacyShortText = "照片整理只在本机完成。不需要账号，也不会上传你的照片。"
}

// MARK: - Haptic Manager
enum HapticManager {
    private static let mediumFeedback = UIImpactFeedbackGenerator(style: .medium)
    private static let lightFeedback = UIImpactFeedbackGenerator(style: .light)
    private static let heavyFeedback = UIImpactFeedbackGenerator(style: .heavy)
    private static let notificationFeedback = UINotificationFeedbackGenerator()

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        switch style {
        case .medium: mediumFeedback.impactOccurred()
        case .light: lightFeedback.impactOccurred()
        case .heavy: heavyFeedback.impactOccurred()
        default: UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        notificationFeedback.notificationOccurred(type)
    }

    private static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: AppConstants.hapticsEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: AppConstants.hapticsEnabledKey)
    }
}

// MARK: - Shared Toast
struct PhotoDelToast: Identifiable {
    let id = UUID()
    let message: String
    let icon: String
    let style: PhotoDelToastStyle
    var showsUndo: Bool = false
}

enum PhotoDelToastStyle {
    case neutral
    case positive
    case destructive
    case favorite
    case warning

    var color: Color {
        switch self {
        case .neutral: return PhotoDelStyle.accent
        case .positive: return PhotoDelStyle.positive
        case .destructive: return PhotoDelStyle.destructive
        case .favorite: return PhotoDelStyle.iconTint(for: "favorite")
        case .warning: return PhotoDelStyle.warning
        }
    }
}

struct PhotoDelToastView: View {
    let toast: PhotoDelToast
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(toast.style.color)
                .frame(width: 22)

            Text(toast.message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if toast.showsUndo, let onUndo {
                Divider()
                    .frame(height: 18)
                    .background(PhotoDelStyle.hairline)

                Button("撤销", action: onUndo)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDelStyle.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            Capsule(style: .continuous)
                .fill(PhotoDelStyle.background.opacity(0.9))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(toast.style.color.opacity(0.34), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 8)
    }
}

// MARK: - Authorization Card
struct PhotoAuthorizationCard: View {
    let subtitle: String
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60, weight: .medium))
                .foregroundColor(PhotoDelStyle.accent)

            Text("需要访问照片库")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)

            Text(subtitle)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(PhotoDelStyle.secondaryText)
                .multilineTextAlignment(.center)

            Button(action: onRequestAccess) {
                Text("继续")
                    .frame(maxWidth: 180)
            }
            .photoDelPrimaryButton()
        }
        .padding(24)
        .photoDelCard()
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
