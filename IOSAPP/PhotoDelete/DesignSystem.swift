import SwiftUI

#if canImport(UIKit)
import UIKit

struct SystemShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

enum PhotoDeleteStyle {
    #if canImport(UIKit)
    static var background: Color { PhotoDeleteTheme.current.backgroundBottom }
    static var backgroundTop: Color { PhotoDeleteTheme.current.backgroundTop }
    static var surface: Color { PhotoDeleteTheme.current.surface }
    static var elevatedSurface: Color { PhotoDeleteTheme.current.elevatedSurface }
    static var hairline: Color { PhotoDeleteTheme.current.hairline }
    static var cardStroke: Color { PhotoDeleteTheme.current.cardStroke }
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
    static var accent: Color { PhotoDeleteTheme.current.primaryAccent }
    static var destructive: Color { PhotoDeleteTheme.current.danger }
    static var positive: Color { PhotoDeleteTheme.current.success }
    static var warning: Color { PhotoDeleteTheme.current.warning }
    static var favorite: Color { PhotoDeleteTheme.current.favorite }
    static var primaryButtonText: Color { PhotoDeleteTheme.current.primaryAccentOnFill }

    static var uiBackground: UIColor { PhotoDeleteTheme.current.uiBackground }
    static var uiAccent: UIColor { PhotoDeleteTheme.current.uiAccent }
    static let uiSecondaryText = dynamicUIColor(
        light: UIColor.secondaryLabel,
        dark: UIColor(white: 1.0, alpha: 0.58)
    )
    static var floatingShadow: Color { PhotoDeleteTheme.current.floatingShadow }
    #else
    static var background: Color { PhotoDeleteTheme.current.backgroundBottom }
    static var backgroundTop: Color { PhotoDeleteTheme.current.backgroundTop }
    static var surface: Color { PhotoDeleteTheme.current.surface }
    static var elevatedSurface: Color { PhotoDeleteTheme.current.elevatedSurface }
    static var hairline: Color { PhotoDeleteTheme.current.hairline }
    static var cardStroke: Color { PhotoDeleteTheme.current.cardStroke }
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.42)
    static var accent: Color { PhotoDeleteTheme.current.primaryAccent }
    static var destructive: Color { PhotoDeleteTheme.current.danger }
    static var positive: Color { PhotoDeleteTheme.current.success }
    static var warning: Color { PhotoDeleteTheme.current.warning }
    static var favorite: Color { PhotoDeleteTheme.current.favorite }
    static var primaryButtonText: Color { PhotoDeleteTheme.current.primaryAccentOnFill }
    static var floatingShadow: Color { PhotoDeleteTheme.current.floatingShadow }
    #endif

    static let screenHorizontalPadding: CGFloat = 20
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14
    static let sectionSpacing: CGFloat = 24
    static let rootContentTopSpacing: CGFloat = 8
    static let rowIconSize: CGFloat = 32
    static let rowMinHeight: CGFloat = 58

    static func iconTint(for key: String) -> Color {
        let theme = PhotoDeleteTheme.current
        switch key {
        case "delete", "trash":
            return theme.danger
        case "favorite", "heart":
            return theme.favorite
        case "video", "livephoto":
            return theme.secondaryAccent
        case "screenshot", "iphone", "photo", "album":
            return theme.primaryAccent
        default:
            return theme.primaryAccent
        }
    }

    static func surfaceFill(for theme: PhotoDeleteTheme, elevated: Bool = false) -> Color {
        elevated ? theme.elevatedSurface : theme.surface
    }

    static func strokeFill(for theme: PhotoDeleteTheme) -> Color {
        theme.cardStroke
    }

    static func hairlineFill(for theme: PhotoDeleteTheme) -> Color {
        theme.hairline
    }

    #if canImport(UIKit)
    private static func dynamicUIColor(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
    #endif
}

enum PhotoDeleteAdaptiveLayout {
    static func isRegularPad(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        isPad && horizontalSizeClass == .regular
    }

    static func prefersExpandedContent(in size: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        isPad && horizontalSizeClass == .regular && size.width >= 760 && size.height >= 560
    }

    static func homeContentMaxWidth(in size: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        prefersExpandedContent(in: size, horizontalSizeClass: horizontalSizeClass) ? min(size.width - 48, 1040) : 520
    }

    static func homeHorizontalPadding(in size: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        prefersExpandedContent(in: size, horizontalSizeClass: horizontalSizeClass) ? 32 : PhotoDeleteStyle.screenHorizontalPadding
    }

    static func homeTopPadding(in size: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        PhotoDeleteStyle.rootContentTopSpacing
    }

    static func readableContentMaxWidth(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat? {
        isRegularPad(horizontalSizeClass: horizontalSizeClass) ? 760 : nil
    }

    static func listContentMaxWidth(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat? {
        isRegularPad(horizontalSizeClass: horizontalSizeClass) ? 860 : nil
    }

    static func prefersReviewSidebar(in size: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        isPad && horizontalSizeClass == .regular && size.width >= 820 && size.height >= 600
    }

    static func reviewSidebarWidth(totalWidth: CGFloat) -> CGFloat {
        min(max(totalWidth * 0.31, 300), 420)
    }

    static func reviewPhotoCardMaxSize(in containerSize: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> CGSize {
        guard isPad && horizontalSizeClass == .regular && containerSize.width >= 520 && containerSize.height >= 620 else {
            return CGSize(width: 390, height: 590)
        }

        return CGSize(width: 470, height: 700)
    }

    #if canImport(UIKit)
    private static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    #else
    private static var isPad: Bool {
        false
    }
    #endif
}

struct PhotoDeleteScreenBackground: View {
    @Environment(\.photoDeleteTheme) private var theme

    var body: some View {
        LinearGradient(
            colors: [
                theme.backgroundTop,
                theme.backgroundBottom
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct PhotoDeleteCardBackground: ViewModifier {
    var radius: CGFloat = PhotoDeleteStyle.cardRadius
    @Environment(\.photoDeleteTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(PhotoDeleteStyle.surfaceFill(for: theme))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(PhotoDeleteStyle.strokeFill(for: theme), lineWidth: 1)
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
    var tint: Color?
    var size: CGFloat = PhotoDeleteStyle.rowIconSize
    var cornerRadius: CGFloat = 9
    var style: PhotoDeleteIconTileStyle = .soft
    var filled: Bool? = nil

    @Environment(\.photoDeleteTheme) private var theme

    init(
        icon: String,
        tint: Color? = nil,
        size: CGFloat = PhotoDeleteStyle.rowIconSize,
        cornerRadius: CGFloat = 9,
        style: PhotoDeleteIconTileStyle = .soft,
        filled: Bool? = nil
    ) {
        self.icon = icon
        self.tint = tint
        self.size = size
        self.cornerRadius = cornerRadius
        self.style = style
        self.filled = filled
    }

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

    private var resolvedTint: Color {
        tint ?? theme.primaryAccent
    }

    private var softFill: Color {
        tint == nil ? theme.iconTileFill : resolvedTint.opacity(0.14)
    }

    private var softStroke: Color {
        tint == nil ? theme.iconTileStroke : resolvedTint.opacity(0.14)
    }

    private var solidSymbolColor: Color {
        tint == nil ? theme.primaryAccentOnFill : .white
    }

    @ViewBuilder
    private var iconContent: some View {
        switch resolvedStyle {
        case .soft:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(softFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(softStroke, lineWidth: 1)
                )
                .overlay(symbol.foregroundColor(resolvedTint))
        case .solid:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(resolvedTint)
                .overlay(symbol.foregroundColor(solidSymbolColor))
        case .plain:
            symbol.foregroundColor(resolvedTint)
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
    @Environment(\.photoDeleteTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(theme.buttonPrimaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                    .fill(configuration.isPressed ? theme.primaryAccentPressed : theme.buttonPrimaryFill)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct PhotoDeleteSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.photoDeleteTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(theme.buttonSecondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                    .fill(theme.buttonSecondaryFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                            .stroke(theme.buttonSecondaryStroke, lineWidth: 1)
                    )
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.74 : 1) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct PhotoDeleteDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(PhotoDeleteStyle.destructive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                    .fill(PhotoDeleteStyle.destructive.opacity(configuration.isPressed ? 0.18 : 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                            .stroke(PhotoDeleteStyle.destructive.opacity(0.28), lineWidth: 1)
                    )
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
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
    static let appStoreID = "6779493280"
    static let appStoreProductURL = URL(string: "https://apps.apple.com/app/id6779493280")!
    static let appStoreReviewURL = URL(string: "itms-apps://itunes.apple.com/app/id6779493280?action=write-review")!
    static let oneZenAppStoreURL = URL(string: "https://apps.apple.com/cn/app/id6780318004")!
    static let technicalAppName = "PhotoDelete"
    static let zhHansAppStoreName = "删图"
    static let enAppStoreName = "OnePhoto"
    static var appDisplayName: String {
        L10n.string("删图")
    }
    static let landscapeBreakpoint: CGFloat = 700
    static let hapticsEnabledKey = "photoDeleteHapticsEnabled"
    static let hasSeenIntroKey = "hasSeenPhotoDeleteIntro"
    static let hasCompletedOnboardingKey = "hasCompletedPhotoDeleteOnboarding"
    static let reviewedAssetIDsKey = "photoDeleteReviewedAssetIDs"
    static let recentOrganizedPhotosKey = "photoDeleteRecentOrganizedPhotosV1"
    static let pendingDeleteCandidateIDsKey = "photoDeletePendingDeleteCandidateIDs"
    static let pendingFavoriteCandidateIDsKey = "photoDeletePendingFavoriteCandidateIDs"
    static let customAlbumOrderKey = "photoDeleteCustomAlbumOrder"
    static let hasSeenAlbumSwipeHintKey = "photoDeleteHasSeenAlbumSwipeHint"
    static let hasDismissedAlbumSwipeHintKey = "photoDeleteHasDismissedAlbumSwipeHintV3"
    static let appLanguageKey = "photoDeleteAppLanguage"
    static let anonymousUserIDKey = "photoDeleteAnonymousUserID"
    static let leftSwipeActionKey = "photoDeleteLeftSwipeAction"
    static let rightSwipeActionKey = "photoDeleteRightSwipeAction"
    static let upSwipeActionKey = "photoDeleteUpSwipeAction"
    static let gestureDefaultMigrationKey = "photoDeleteGestureDefaultMigration"
    static let reviewVideoAutoPlayKey = "photoDeleteReviewMediaAutoPlay"
    static let reviewMediaAutoPlayKey = reviewVideoAutoPlayKey
    static let reviewLivePhotoAutoPlayKey = "photoDeleteReviewLivePhotoAutoPlay"
    static let randomReviewHideFiledPhotosKey = "photoDeleteRandomReviewHideFiledPhotos"
    static let reviewVideoMutedKey = "photoDeleteReviewVideoMuted"
    static let reviewModeKey = "photoDeleteReviewMode"
    static let reviewAlbumShortcutsExpandedKey = "photoDeleteReviewAlbumShortcutsExpanded"
    static let hasSeenReviewModeHintKey = "photoDeleteHasSeenReviewModeHint"
    static let hasSeenAlbumShortcutHintKey = "photoDeleteHasSeenAlbumShortcutHintV2"
    static let hasSeenAlbumDownSwipeHintKey = "photoDeleteHasSeenAlbumDownSwipeHint"
    static let hasSeenDeleteButtonTipKey = "photoDeleteHasSeenDeleteButtonTip"
    static let gestureUpdateNoticePendingKey = "photoDeleteGestureUpdateNoticePendingV1"
    static let reviewProgressByScopeKey = "photoDeleteReviewProgressByScope"
    static let appAppearanceKey = "photoDeleteAppAppearance"
    static let appThemeKey = "photoDeleteAppTheme"
    static let similarPhotoMatchModeKey = "photoDeleteSimilarPhotoMatchMode"
    static let openAlbumsTabNotificationName = Notification.Name("photoDeleteOpenAlbumsTab")
    static let supporterAnnualProductID = "com.01mvp.photodelete.pro.annual"
    static let supporterLifetimeProductID = "com.01mvp.photodelete.supporter.stats"
    static let supporterProductIDs: Set<String> = [
        supporterAnnualProductID,
        supporterLifetimeProductID
    ]
    static let supporterEntitlementKey = "photoDeleteSupporterUnlocked"
    static let supporterPurchaseDateKey = "photoDeleteSupporterPurchaseDate"
    static let supporterProductIDKey = "photoDeleteSupporterProductID"
    static let supporterExpirationDateKey = "photoDeleteSupporterExpirationDate"
    static let supporterTrialStartDateKey = "photoDeleteSupporterTrialStartDate"
    static let supporterTrialDuration: TimeInterval = 3 * 24 * 60 * 60
    static let isImageCompressionVisible = true
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

    func color(for theme: PhotoDeleteTheme) -> Color {
        switch self {
        case .neutral: return theme.primaryAccent
        case .positive: return theme.success
        case .destructive: return theme.danger
        case .favorite: return theme.favorite
        case .warning: return theme.warning
        }
    }

    var color: Color {
        color(for: .current)
    }
}

struct PhotoDeleteToastView: View {
    let toast: PhotoDeleteToast
    var onUndo: (() -> Void)?

    @Environment(\.photoDeleteTheme) private var theme

    private var toastColor: Color {
        toast.style.color(for: theme)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(toastColor)
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
                    .foregroundColor(theme.toolbarAction)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            Capsule(style: .continuous)
                .fill(theme.elevatedSurface.opacity(0.94))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(toastColor.opacity(0.34), lineWidth: 1)
                )
        )
        .shadow(color: theme.floatingShadow, radius: 10, x: 0, y: 5)
    }
}

// MARK: - Authorization Card
struct PhotoAuthorizationCard: View {
    let subtitle: String
    let onRequestAccess: () -> Void

    @Environment(\.photoDeleteTheme) private var theme

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle.weight(.medium))
                .foregroundStyle(theme.primaryAccent)
                .accessibilityHidden(true)

            Text(L10n.string("需要访问照片库"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(PhotoDeleteStyle.primaryText)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(PhotoDeleteStyle.secondaryText)
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

    func photoDeleteDestructiveButton() -> some View {
        buttonStyle(PhotoDeleteDestructiveButtonStyle())
    }
}
