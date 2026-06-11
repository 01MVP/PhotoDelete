//
//  PhotoDelApp.swift
//  PhotoDel
//
//  Created by jackie xiao on 11/7/25.
//

import SwiftUI

@main
struct PhotoDelApp: App {
    @AppStorage(AppConstants.appLanguageKey) private var appLanguageValue = AppLanguage.system.rawValue
    @AppStorage(AppConstants.appAppearanceKey) private var appAppearanceValue = AppAppearance.system.rawValue

    init() {
        #if DEBUG
        PhotoDelUITestDefaults.applyIfNeeded()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, selectedLanguage.locale)
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
}

#if DEBUG
private enum PhotoDelUITestDefaults {
    static func applyIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PHOTO_DEL_UI_TEST"] == "1" else { return }

        let defaults = UserDefaults.standard
        reset(defaults)

        if let appLanguage = environment["PHOTO_DEL_UI_TEST_APP_LANGUAGE"] {
            defaults.set(appLanguage, forKey: AppConstants.appLanguageKey)
        }

        setBool(
            environment["PHOTO_DEL_UI_TEST_HAS_COMPLETED_ONBOARDING"],
            forKey: AppConstants.hasCompletedOnboardingKey,
            defaults: defaults
        )
        setBool(
            environment["PHOTO_DEL_UI_TEST_HAS_SEEN_INTRO"],
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
            AppConstants.customAlbumOrderKey,
            AppConstants.appAppearanceKey
        ].forEach(defaults.removeObject)
    }

    private static func setBool(_ rawValue: String?, forKey key: String, defaults: UserDefaults) {
        guard let rawValue else { return }
        defaults.set(rawValue == "1", forKey: key)
    }
}
#endif
