//
//  MainTabView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MainTabView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.photoDeleteTheme) private var theme
    @AppStorage(AppConstants.appAppearanceKey) private var appAppearanceValue = AppAppearance.system.rawValue
    @State private var selectedTab: PhotoDeleteMainTab = .organize
    
    var body: some View {
        tabRoot
        .tint(theme.navigationTint)
        .onAppear {
            configureTabBarAppearance()
            dataManager.syncPhotoLibraryAuthorization()
            #if DEBUG
            UITestPhotoLibrarySeeder.seedIfRequested {
                dataManager.syncPhotoLibraryAuthorization(showPreparing: true)
                dataManager.refreshAlbumsFromLibrary(showLoading: false)
            }
            #endif
        }
        .onChange(of: appAppearanceValue) { _ in
            configureTabBarAppearance()
        }
        .onChange(of: theme) { _ in
            configureTabBarAppearance()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            configureTabBarAppearance()
            dataManager.syncPhotoLibraryAuthorization()
            Task {
                await purchaseManager.refreshEntitlementsAfterPotentialExternalChange()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.openAlbumsTabNotificationName)) { _ in
            selectedTab = .albums
        }
    }

    private var tabRoot: some View {
        TabView(selection: $selectedTab) {
            tabContent(for: .organize)
                .tabItem {
                    Image(systemName: PhotoDeleteMainTab.organize.systemImage)
                    Text(PhotoDeleteMainTab.organize.title)
                }
                .tag(PhotoDeleteMainTab.organize)
            
            tabContent(for: .albums)
                .tabItem {
                    Image(systemName: PhotoDeleteMainTab.albums.systemImage)
                    Text(PhotoDeleteMainTab.albums.title)
                }
                .tag(PhotoDeleteMainTab.albums)

            tabContent(for: .advanced)
                .tabItem {
                    Image(systemName: PhotoDeleteMainTab.advanced.systemImage)
                    Text(PhotoDeleteMainTab.advanced.title)
                }
                .tag(PhotoDeleteMainTab.advanced)
            
            tabContent(for: .settings)
                .tabItem {
                    Image(systemName: PhotoDeleteMainTab.settings.systemImage)
                    Text(PhotoDeleteMainTab.settings.title)
                }
                .tag(PhotoDeleteMainTab.settings)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: PhotoDeleteMainTab) -> some View {
        switch tab {
        case .organize:
            HomeView()
                .environmentObject(dataManager)
        case .albums:
            AlbumsView()
                .environmentObject(dataManager)
        case .advanced:
            AdvancedView()
                .environmentObject(dataManager)
                .environmentObject(purchaseManager)
        case .settings:
            SettingsView()
                .environmentObject(dataManager)
                .environmentObject(purchaseManager)
        }
    }

    private func configureTabBarAppearance() {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 else {
            return
        }

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = theme.uiBackground.withAlphaComponent(0.92)
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.selectionIndicatorTintColor = theme.uiTabSelected

        appearance.stackedLayoutAppearance.normal.iconColor = theme.uiSecondaryText
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: theme.uiSecondaryText
        ]

        appearance.stackedLayoutAppearance.selected.iconColor = theme.uiTabSelected
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: theme.uiTabSelected
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

private enum PhotoDeleteMainTab: CaseIterable, Identifiable, Hashable {
    case organize
    case albums
    case advanced
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .organize:
            return L10n.string("整理")
        case .albums:
            return L10n.string("相册")
        case .advanced:
            return L10n.string("进阶")
        case .settings:
            return L10n.string("设置")
        }
    }

    var systemImage: String {
        switch self {
        case .organize:
            return "sparkles"
        case .albums:
            return "photo.on.rectangle"
        case .advanced:
            return "chart.bar.xaxis"
        case .settings:
            return "gearshape"
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(DataManager())
        .environmentObject(PurchaseManager())
}
