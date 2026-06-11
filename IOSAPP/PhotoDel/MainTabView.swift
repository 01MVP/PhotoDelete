//
//  MainTabView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
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
    @State private var displayedCelebration: CleanupCelebration?
    @State private var celebrationDismissWorkItem: DispatchWorkItem?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 整理页面
            HomeView()
                .environmentObject(dataManager)
                .tabItem {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("整理")
                }
                .tag(0)
            
            // 相册页面
            AlbumsView()
                .environmentObject(dataManager)
                .tabItem {
                    Image(systemName: "rectangle.stack")
                    Text("相册")
                }
                .tag(1)

            // 进阶页面
            AdvancedView()
                .environmentObject(dataManager)
                .environmentObject(purchaseManager)
                .tabItem {
                    Image(systemName: "chart.bar.xaxis")
                    Text("进阶")
                }
                .tag(2)
            
            // 设置页面
            SettingsView()
                .environmentObject(dataManager)
                .environmentObject(purchaseManager)
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("设置")
                }
                .tag(3)
        }
        .tint(PhotoDelStyle.accent)
        .overlay {
            if let displayedCelebration {
                CleanupCelebrationOverlay(
                    celebration: displayedCelebration,
                    onDismiss: dismissCelebration
                )
            }
        }
        .onAppear {
            configureTabBarAppearance()
            dataManager.syncPhotoLibraryAuthorization()
        }
        .onChange(of: appAppearanceValue) { _ in
            configureTabBarAppearance()
        }
        .onChange(of: dataManager.latestCleanupCelebration) { celebration in
            guard let celebration else { return }
            presentCelebration(celebration)
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            configureTabBarAppearance()
            dataManager.syncPhotoLibraryAuthorization()
        }
    }

    private func presentCelebration(_ celebration: CleanupCelebration) {
        celebrationDismissWorkItem?.cancel()
        HapticManager.notify(.success)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            displayedCelebration = celebration
        }

        let workItem = DispatchWorkItem {
            dismissCelebration()
        }
        celebrationDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4, execute: workItem)
    }

    private func dismissCelebration() {
        celebrationDismissWorkItem?.cancel()
        celebrationDismissWorkItem = nil
        withAnimation(.easeOut(duration: 0.2)) {
            displayedCelebration = nil
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = PhotoDelStyle.uiBackground.withAlphaComponent(0.92)
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.selectionIndicatorTintColor = PhotoDelStyle.uiAccent

        appearance.stackedLayoutAppearance.normal.iconColor = PhotoDelStyle.uiSecondaryText
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: PhotoDelStyle.uiSecondaryText
        ]

        appearance.stackedLayoutAppearance.selected.iconColor = PhotoDelStyle.uiAccent
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: PhotoDelStyle.uiAccent
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
