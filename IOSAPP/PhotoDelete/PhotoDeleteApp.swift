//
//  PhotoDeleteApp.swift
//  PhotoDelete
//
//  Created by jackie xiao on 11/7/25.
//

import SwiftUI

@main
struct PhotoDeleteApp: App {
    @AppStorage(AppConstants.appLanguageKey) private var appLanguageValue = AppLanguage.system.rawValue
    @AppStorage(AppConstants.appAppearanceKey) private var appAppearanceValue = AppAppearance.system.rawValue
    @AppStorage(AppConstants.appThemeKey) private var appThemeValue = PhotoDeleteTheme.defaultTheme.rawValue
    @StateObject private var purchaseManager = PurchaseManager()

    init() {
        #if DEBUG
        PhotoDeleteUITestDefaults.applyIfNeeded()
        #endif
        SwipeGesturePreferences.migrateStoredDefaultsIfNeeded()
        ReviewPlaybackPreferences.applyLaunchDefaults()
        PhotoRandomReviewMigration.applyIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseManager)
                .environment(\.locale, selectedLanguage.locale)
                .modifier(AppLayoutDirectionModifier(language: selectedLanguage))
                .environment(\.photoDeleteTheme, selectedTheme)
                .tint(selectedTheme.navigationTint)
                .preferredColorScheme(selectedAppearance.colorScheme)
                .statusBarHidden(false)
        }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageValue) ?? .system
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceValue) ?? .system
    }

    private var selectedTheme: PhotoDeleteTheme {
        guard purchaseManager.isSupporter else { return .defaultTheme }
        return PhotoDeleteTheme.normalized(appThemeValue)
    }
}

private struct AppLayoutDirectionModifier: ViewModifier {
    let language: AppLanguage

    func body(content: Content) -> some View {
        if language == .system {
            content
        } else {
            content.environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        }
    }
}

#if DEBUG
private enum PhotoDeleteUITestDefaults {
    static func applyIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PHOTO_DELETE_UI_TEST"] == "1" else { return }

        let defaults = UserDefaults.standard
        reset(defaults)

        if let appLanguage = environment["PHOTO_DELETE_UI_TEST_APP_LANGUAGE"] {
            defaults.set(appLanguage, forKey: AppConstants.appLanguageKey)
        }

        if let appAppearance = environment["PHOTO_DELETE_UI_TEST_APP_APPEARANCE"] {
            defaults.set(appAppearance, forKey: AppConstants.appAppearanceKey)
        }

        setBool(
            environment["PHOTO_DELETE_UI_TEST_HAS_COMPLETED_ONBOARDING"],
            forKey: AppConstants.hasCompletedOnboardingKey,
            defaults: defaults
        )
        setBool(
            environment["PHOTO_DELETE_UI_TEST_HAS_SEEN_INTRO"],
            forKey: AppConstants.hasSeenIntroKey,
            defaults: defaults
        )

        if environment["PHOTO_DELETE_UI_TEST_SUPPORTER_TRIAL_ACTIVE"] == "1" {
            defaults.set(Date(), forKey: AppConstants.supporterTrialStartDateKey)
        }
    }

    private static func reset(_ defaults: UserDefaults) {
        [
            AppConstants.appLanguageKey,
            AppConstants.hasCompletedOnboardingKey,
            AppConstants.hasSeenIntroKey,
            AppConstants.pendingDeleteCandidateIDsKey,
            AppConstants.pendingFavoriteCandidateIDsKey,
            AppConstants.leftSwipeActionKey,
            AppConstants.rightSwipeActionKey,
            AppConstants.upSwipeActionKey,
            AppConstants.gestureDefaultMigrationKey,
            AppConstants.reviewMediaAutoPlayKey,
            AppConstants.reviewLivePhotoAutoPlayKey,
            AppConstants.reviewVideoMutedKey,
            AppConstants.reviewModeKey,
            AppConstants.gestureUpdateNoticePendingKey,
            AppConstants.hasSeenAlbumShortcutHintKey,
            AppConstants.hasSeenDeleteButtonTipKey,
            AppConstants.hasDismissedAlbumSwipeHintKey,
            AppConstants.reviewProgressByScopeKey,
            AppConstants.randomReviewSessionsKey,
            AppConstants.randomReviewMigrationVersionKey,
            AppConstants.customAlbumOrderKey,
            AppConstants.appAppearanceKey,
            AppConstants.appThemeKey,
            AppConstants.supporterEntitlementKey,
            AppConstants.supporterPurchaseDateKey,
            AppConstants.supporterTrialStartDateKey
        ].forEach(defaults.removeObject)
    }

    private static func setBool(_ rawValue: String?, forKey key: String, defaults: UserDefaults) {
        guard let rawValue else { return }
        defaults.set(rawValue == "1", forKey: key)
    }
}
#endif
