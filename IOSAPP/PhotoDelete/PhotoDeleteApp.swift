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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseManager)
                .environment(\.locale, selectedLanguage.locale)
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
    }

    private static func reset(_ defaults: UserDefaults) {
        [
            AppConstants.appLanguageKey,
            AppConstants.hasCompletedOnboardingKey,
            AppConstants.hasSeenIntroKey,
            AppConstants.leftSwipeActionKey,
            AppConstants.rightSwipeActionKey,
            AppConstants.upSwipeActionKey,
            AppConstants.gestureDefaultMigrationKey,
            AppConstants.reviewModeKey,
            AppConstants.hasSeenAlbumShortcutHintKey,
            AppConstants.hasSeenDeleteButtonTipKey,
            AppConstants.hasDismissedAlbumSwipeHintKey,
            AppConstants.reviewProgressByScopeKey,
            AppConstants.customAlbumOrderKey,
            AppConstants.appAppearanceKey,
            AppConstants.appThemeKey
        ].forEach(defaults.removeObject)
    }

    private static func setBool(_ rawValue: String?, forKey key: String, defaults: UserDefaults) {
        guard let rawValue else { return }
        defaults.set(rawValue == "1", forKey: key)
    }
}
#endif
