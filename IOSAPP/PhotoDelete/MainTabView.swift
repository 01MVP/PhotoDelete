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
    @AppStorage(AppConstants.appAppearanceKey) private var appAppearanceValue = AppAppearance.system.rawValue
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 整理页面
            HomeView()
                .environmentObject(dataManager)
                .tabItem {
                    Image(systemName: "sparkles")
                    Text(L10n.string("整理"))
                }
                .tag(0)
            
            // 相册页面
            AlbumsView()
                .environmentObject(dataManager)
                .tabItem {
                    Image(systemName: "photo.on.rectangle")
                    Text(L10n.string("相册"))
                }
                .tag(1)

            // 进阶页面
            AdvancedView()
                .environmentObject(dataManager)
                .environmentObject(purchaseManager)
                .tabItem {
                    Image(systemName: "chart.bar.xaxis")
                    Text(L10n.string("进阶"))
                }
                .tag(2)
            
            // 设置页面
            SettingsView()
                .environmentObject(dataManager)
                .environmentObject(purchaseManager)
                .tabItem {
                    Image(systemName: "gearshape")
                    Text(L10n.string("设置"))
                }
                .tag(3)
        }
        .tint(PhotoDeleteStyle.accent)
        .onAppear {
            configureTabBarAppearance()
            dataManager.syncPhotoLibraryAuthorization()
        }
        .onChange(of: appAppearanceValue) { _ in
            configureTabBarAppearance()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            configureTabBarAppearance()
            dataManager.syncPhotoLibraryAuthorization()
        }
    }

    private func configureTabBarAppearance() {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 else {
            return
        }

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = PhotoDeleteStyle.uiBackground.withAlphaComponent(0.92)
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.selectionIndicatorTintColor = PhotoDeleteStyle.uiAccent

        appearance.stackedLayoutAppearance.normal.iconColor = PhotoDeleteStyle.uiSecondaryText
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: PhotoDeleteStyle.uiSecondaryText
        ]

        appearance.stackedLayoutAppearance.selected.iconColor = PhotoDeleteStyle.uiAccent
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: PhotoDeleteStyle.uiAccent
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    MainTabView()
        .environmentObject(DataManager())
        .environmentObject(PurchaseManager())
}
