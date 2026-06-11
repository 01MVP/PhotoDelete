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
    @State private var selectedTab = 0
    
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
        .preferredColorScheme(.dark)
        .onAppear {
            // 自定义TabBar外观
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = PhotoDelStyle.uiBackground.withAlphaComponent(0.92)
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            appearance.selectionIndicatorTintColor = PhotoDelStyle.uiAccent
            
            // 未选中状态
            appearance.stackedLayoutAppearance.normal.iconColor = PhotoDelStyle.uiSecondaryText
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: PhotoDelStyle.uiSecondaryText
            ]
            
            // 选中状态
            appearance.stackedLayoutAppearance.selected.iconColor = PhotoDelStyle.uiAccent
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: PhotoDelStyle.uiAccent
            ]
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance

            dataManager.syncPhotoLibraryAuthorization()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            dataManager.syncPhotoLibraryAuthorization()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(DataManager())
        .environmentObject(PurchaseManager())
}
