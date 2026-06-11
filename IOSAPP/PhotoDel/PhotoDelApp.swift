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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, selectedLanguage.locale)
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageValue) ?? .system
    }
}
