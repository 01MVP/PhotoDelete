import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum PhotoDeleteStyle {
    #if canImport(UIKit)
    static let background = Color(uiColor: dynamicUIColor(
        light: UIColor.systemGroupedBackground,
        dark: UIColor(red: 0.035, green: 0.037, blue: 0.042, alpha: 1)
    ))
    static let backgroundTop = Color(uiColor: dynamicUIColor(
        light: UIColor.systemGroupedBackground,
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
        light: UIColor.separator.withAlphaComponent(0.14),
        dark: UIColor(white: 1, alpha: 0.115)
    ))
    static let cardStroke = Color(uiColor: dynamicUIColor(
        light: UIColor.separator.withAlphaComponent(0.08),
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
    static let floatingShadow = Color(uiColor: dynamicUIColor(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 0, alpha: 0.24)
    ))
    #else
    static let background = Color(red: 0.035, green: 0.037, blue: 0.042)
    static let backgroundTop = Color(red: 0.058, green: 0.06, blue: 0.068)
    static let surface = Color.white.opacity(0.075)
    static let elevatedSurface = Color.white.opacity(0.105)
    static let hairline = Color.white.opacity(0.115)
    static let cardStroke = Color.white.opacity(0.115)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.42)
    static let accent = Color(red: 0.64, green: 0.78, blue: 1.0)
    static let destructive = Color(red: 1.0, green: 0.38, blue: 0.34)
    static let positive = Color(red: 0.5, green: 0.9, blue: 0.64)
    static let warning = Color(red: 1.0, green: 0.79, blue: 0.47)
    static let primaryButtonText = Color.black.opacity(0.88)
    static let floatingShadow = Color.black.opacity(0.24)
    #endif

    static let screenHorizontalPadding: CGFloat = 20
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14
    static let sectionSpacing: CGFloat = 24
    static let rowIconSize: CGFloat = 32
    static let rowMinHeight: CGFloat = 58

    static func iconTint(for key: String) -> Color {
        switch key {
        case "delete", "trash": return destructive
        case "favorite", "heart": return Color(uiColor: dynamicUIColor(
            light: UIColor(red: 0.82, green: 0.16, blue: 0.38, alpha: 1),
            dark: UIColor(red: 1.0, green: 0.62, blue: 0.72, alpha: 1)
        ))
        case "screenshot", "iphone": return Color(uiColor: dynamicUIColor(
            light: UIColor(red: 0.0, green: 0.48, blue: 0.78, alpha: 1),
            dark: UIColor(red: 0.44, green: 0.78, blue: 1.0, alpha: 1)
        ))
        case "video": return Color(uiColor: dynamicUIColor(
            light: UIColor(red: 0.44, green: 0.31, blue: 0.88, alpha: 1),
            dark: UIColor(red: 0.72, green: 0.7, blue: 1.0, alpha: 1)
        ))
        case "livephoto": return Color(uiColor: dynamicUIColor(
            light: UIColor(red: 0.02, green: 0.55, blue: 0.42, alpha: 1),
            dark: UIColor(red: 0.36, green: 0.84, blue: 0.68, alpha: 1)
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

struct PhotoDeleteScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                PhotoDeleteStyle.backgroundTop,
                PhotoDeleteStyle.background
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct PhotoDeleteCardBackground: ViewModifier {
    var radius: CGFloat = PhotoDeleteStyle.cardRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(PhotoDeleteStyle.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(PhotoDeleteStyle.cardStroke, lineWidth: 1)
                    )
            )
    }
}

enum PhotoDeleteIconTileStyle {
    case soft
    case solid
    case plain
}

struct PhotoDeleteIconTile: View {
    let icon: String
    let tint: Color
    var size: CGFloat = PhotoDeleteStyle.rowIconSize
    var cornerRadius: CGFloat = 9
    var style: PhotoDeleteIconTileStyle = .soft
    var filled: Bool? = nil

    var body: some View {
        iconContent
            .frame(width: size, height: size)
    }

    private var resolvedStyle: PhotoDeleteIconTileStyle {
        if let filled {
            return filled ? .solid : .soft
        }
        return style
    }

    @ViewBuilder
    private var iconContent: some View {
        switch resolvedStyle {
        case .soft:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(tint.opacity(0.12), lineWidth: 1)
                )
                .overlay(symbol.foregroundColor(tint))
        case .solid:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint)
                .overlay(symbol.foregroundColor(.white))
        case .plain:
            symbol.foregroundColor(tint)
        }
    }

    private var symbol: some View {
        Image(systemName: icon)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: max(size * 0.46, 14), weight: .medium))
    }
}

struct PhotoDeletePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(PhotoDeleteStyle.primaryButtonText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                    .fill(PhotoDeleteStyle.accent)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct PhotoDeleteSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(PhotoDeleteStyle.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                    .fill(PhotoDeleteStyle.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                            .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
                    )
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.74 : 1) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension View {
    func photoDeleteMinimumTapTarget(_ size: CGFloat = 44) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }

    func photoDeleteSectionHeading() -> some View {
        font(.headline)
            .foregroundStyle(PhotoDeleteStyle.primaryText)
    }

    func photoDeletePrimaryLabel(_ font: Font = .body) -> some View {
        self.font(font)
            .foregroundStyle(PhotoDeleteStyle.primaryText)
    }

    func photoDeleteSecondaryLabel(_ font: Font = .subheadline) -> some View {
        self.font(font)
            .foregroundStyle(PhotoDeleteStyle.secondaryText)
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

    static let authorName = "MakerJackie"
    static let feedbackEmail = "contact@01mvp.com"
    static let wechatID = "mvps01"
    static let websiteURL = "https://01mvp.com"
    static let technicalAppName = "PhotoDelete"
    static let zhHansAppStoreName = "删图 - 相册清理助手"
    static let enAppStoreName = "Photo Delete: Swipe Cleaner"
    static var appDisplayName: String {
        L10n.string("删图")
    }
    static let landscapeBreakpoint: CGFloat = 700
    static let hapticsEnabledKey = "photoDeleteHapticsEnabled"
    static let hasSeenIntroKey = "hasSeenPhotoDeleteIntro"
    static let hasCompletedOnboardingKey = "hasCompletedPhotoDeleteOnboarding"
    static let reviewedAssetIDsKey = "photoDeleteReviewedAssetIDs"
    static let customAlbumOrderKey = "photoDeleteCustomAlbumOrder"
    static let hasSeenAlbumSwipeHintKey = "photoDeleteHasSeenAlbumSwipeHint"
    static let hasDismissedAlbumSwipeHintKey = "photoDeleteHasDismissedAlbumSwipeHintV2"
    static let appLanguageKey = "photoDeleteAppLanguage"
    static let anonymousUserIDKey = "photoDeleteAnonymousUserID"
    static let leftSwipeActionKey = "photoDeleteLeftSwipeAction"
    static let rightSwipeActionKey = "photoDeleteRightSwipeAction"
    static let upSwipeActionKey = "photoDeleteUpSwipeAction"
    static let gestureDefaultMigrationKey = "photoDeleteGestureDefaultMigration"
    static let reviewModeKey = "photoDeleteReviewMode"
    static let reviewProgressByScopeKey = "photoDeleteReviewProgressByScope"
    static let appAppearanceKey = "photoDeleteAppAppearance"
    static let supporterProductID = "com.01mvp.photodelete.supporter.stats"
    static let supporterEntitlementKey = "photoDeleteSupporterUnlocked"
    static let supporterThemeKey = "photoDeleteSupporterTheme"
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
struct PhotoDeleteToast: Identifiable {
    let id = UUID()
    let message: String
    let icon: String
    let style: PhotoDeleteToastStyle
    var showsUndo: Bool = false
}

enum PhotoDeleteToastStyle {
    case neutral
    case positive
    case destructive
    case favorite
    case warning

    var color: Color {
        switch self {
        case .neutral: return PhotoDeleteStyle.accent
        case .positive: return PhotoDeleteStyle.positive
        case .destructive: return PhotoDeleteStyle.destructive
        case .favorite: return PhotoDeleteStyle.iconTint(for: "favorite")
        case .warning: return PhotoDeleteStyle.warning
        }
    }
}

struct PhotoDeleteToastView: View {
    let toast: PhotoDeleteToast
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(toast.style.color)
                .frame(width: 22)

            Text(toast.message.appLocalized)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if toast.showsUndo, let onUndo {
                Divider()
                    .frame(height: 18)
                    .background(PhotoDeleteStyle.hairline)

                Button(L10n.string("撤销"), action: onUndo)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            Capsule(style: .continuous)
                .fill(PhotoDeleteStyle.background.opacity(0.9))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(toast.style.color.opacity(0.34), lineWidth: 1)
                )
        )
        .shadow(color: PhotoDeleteStyle.floatingShadow, radius: 10, x: 0, y: 5)
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
                .foregroundColor(PhotoDeleteStyle.accent)

            Text(L10n.string("需要访问照片库"))
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            Text(subtitle.appLocalized)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .multilineTextAlignment(.center)

            Button(action: onRequestAccess) {
                Text(L10n.string("继续"))
                    .frame(maxWidth: 180)
            }
            .photoDeletePrimaryButton()
        }
        .padding(24)
        .photoDeleteCard()
    }
}

extension View {
    func photoDeleteCard(radius: CGFloat = PhotoDeleteStyle.cardRadius) -> some View {
        modifier(PhotoDeleteCardBackground(radius: radius))
    }

    func photoDeletePrimaryButton() -> some View {
        buttonStyle(PhotoDeletePrimaryButtonStyle())
    }

    func photoDeleteSecondaryButton() -> some View {
        buttonStyle(PhotoDeleteSecondaryButtonStyle())
    }
}
