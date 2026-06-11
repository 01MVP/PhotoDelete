import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum PhotoDelStyle {
    #if canImport(UIKit)
    static let background = Color(uiColor: dynamicUIColor(
        light: UIColor.systemGroupedBackground,
        dark: UIColor(red: 0.035, green: 0.037, blue: 0.042, alpha: 1)
    ))
    static let backgroundTop = Color(uiColor: dynamicUIColor(
        light: UIColor.systemBackground,
        dark: UIColor(red: 0.058, green: 0.06, blue: 0.068, alpha: 1)
    ))
    static let surface = Color(uiColor: dynamicUIColor(
        light: UIColor.secondarySystemGroupedBackground,
        dark: UIColor(white: 1, alpha: 0.075)
    ))
    static let elevatedSurface = Color(uiColor: dynamicUIColor(
        light: UIColor.tertiarySystemGroupedBackground,
        dark: UIColor(white: 1, alpha: 0.105)
    ))
    static let hairline = Color(uiColor: dynamicUIColor(
        light: UIColor.separator.withAlphaComponent(0.22),
        dark: UIColor(white: 1, alpha: 0.115)
    ))
    static let primaryText = Color(uiColor: dynamicUIColor(
        light: UIColor.label,
        dark: UIColor(white: 1, alpha: 0.96)
    ))
    static let secondaryText = Color(uiColor: dynamicUIColor(
        light: UIColor.secondaryLabel,
        dark: UIColor(white: 1, alpha: 0.62)
    ))
    static let tertiaryText = Color(uiColor: dynamicUIColor(
        light: UIColor.tertiaryLabel,
        dark: UIColor(white: 1, alpha: 0.42)
    ))
    static let accent = Color(uiColor: dynamicUIColor(
        light: UIColor.systemBlue,
        dark: UIColor(red: 0.64, green: 0.78, blue: 1, alpha: 1)
    ))
    static let destructive = Color(uiColor: dynamicUIColor(
        light: UIColor(red: 0.86, green: 0.13, blue: 0.12, alpha: 1),
        dark: UIColor(red: 1, green: 0.38, blue: 0.34, alpha: 1)
    ))
    static let positive = Color(uiColor: dynamicUIColor(
        light: UIColor(red: 0.06, green: 0.5, blue: 0.22, alpha: 1),
        dark: UIColor(red: 0.5, green: 0.9, blue: 0.64, alpha: 1)
    ))
    static let warning = Color(uiColor: dynamicUIColor(
        light: UIColor(red: 0.78, green: 0.45, blue: 0.02, alpha: 1),
        dark: UIColor(red: 1, green: 0.79, blue: 0.47, alpha: 1)
    ))
    static let primaryButtonText = Color(uiColor: dynamicUIColor(
        light: UIColor.white,
        dark: UIColor(white: 0, alpha: 0.88)
    ))

    static let uiBackground = dynamicUIColor(
        light: UIColor.systemGroupedBackground,
        dark: UIColor(red: 0.035, green: 0.037, blue: 0.042, alpha: 1)
    )
    static let uiAccent = dynamicUIColor(
        light: UIColor.systemBlue,
        dark: UIColor(red: 0.64, green: 0.78, blue: 1, alpha: 1)
    )
    static let uiSecondaryText = dynamicUIColor(
        light: UIColor.secondaryLabel,
        dark: UIColor(white: 1.0, alpha: 0.58)
    )
    static let cardShadow = Color(uiColor: dynamicUIColor(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 0, alpha: 0)
    ))
    #else
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
    static let primaryButtonText = Color.black.opacity(0.88)
    static let cardShadow = Color.clear
    #endif

    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14

    static func iconTint(for key: String) -> Color {
        switch key {
        case "delete", "trash": return destructive
        case "favorite", "heart": return Color(uiColor: dynamicUIColor(
            light: UIColor(red: 0.82, green: 0.16, blue: 0.38, alpha: 1),
            dark: UIColor(red: 1.0, green: 0.62, blue: 0.72, alpha: 1)
        ))
        case "video": return Color(uiColor: dynamicUIColor(
            light: UIColor(red: 0.44, green: 0.31, blue: 0.88, alpha: 1),
            dark: UIColor(red: 0.72, green: 0.7, blue: 1.0, alpha: 1)
        ))
        default: return accent
        }
    }

    #if canImport(UIKit)
    private static func dynamicUIColor(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
    #endif
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
            .shadow(color: PhotoDelStyle.cardShadow, radius: 12, x: 0, y: 5)
    }
}

struct PhotoDelPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(PhotoDelStyle.primaryButtonText)
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
    static var version: String { bundleShortVersion }
    static var displayVersion: String {
        "\(bundleShortVersion) (\(bundleBuildNumber))"
    }

    private static var bundleShortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private static var bundleBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static let authorName = "maker jackie"
    static let feedbackEmail = "contact@01mvp.com"
    static let wechatID = "mvps01"
    static let websiteURL = "https://01mvp.com"
    static let landscapeBreakpoint: CGFloat = 700
    static let hapticsEnabledKey = "photoDelHapticsEnabled"
    static let hasSeenIntroKey = "hasSeenPhotoDelIntro"
    static let hasCompletedOnboardingKey = "hasCompletedPhotoDelOnboarding"
    static let reviewedAssetIDsKey = "photoDelReviewedAssetIDs"
    static let customAlbumOrderKey = "photoDelCustomAlbumOrder"
    static let appLanguageKey = "photoDelAppLanguage"
    static let anonymousUserIDKey = "photoDelAnonymousUserID"
    static let leftSwipeActionKey = "photoDelLeftSwipeAction"
    static let rightSwipeActionKey = "photoDelRightSwipeAction"
    static let upSwipeActionKey = "photoDelUpSwipeAction"
    static let reviewModeKey = "photoDelReviewMode"
    static let appAppearanceKey = "photoDelAppAppearance"
    static let supporterProductID = "com.01mvp.photodel.supporter.stats"
    static let supporterEntitlementKey = "photoDelSupporterUnlocked"
    static let supporterThemeKey = "photoDelSupporterTheme"
    static var privacyShortText: String {
        L10n.string("照片整理只在本机完成。不需要账号，也不会上传你的照片。")
    }
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

            Text(toast.message.appLocalized)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if toast.showsUndo, let onUndo {
                Divider()
                    .frame(height: 18)
                    .background(PhotoDelStyle.hairline)

                Button(L10n.string("撤销"), action: onUndo)
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

            Text(L10n.string("需要访问照片库"))
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(PhotoDelStyle.primaryText)

            Text(subtitle.appLocalized)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(PhotoDelStyle.secondaryText)
                .multilineTextAlignment(.center)

            Button(action: onRequestAccess) {
                Text(L10n.string("继续"))
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
