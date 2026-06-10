//
//  MainTabView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 整理页面
            HomeView()
                .environmentObject(dataManager)
                .tabItem {
                    Image(systemName: "square.and.arrow.up.on.square")
                    Text("整理")
                }
                .tag(0)
            
            // 相册页面
            AlbumsView()
                .environmentObject(dataManager)
                .tabItem {
                    Image(systemName: "photo.stack")
                    Text("相册")
                }
                .tag(1)
            
            // 设置页面
            SettingsView()
                .environmentObject(dataManager)
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("设置")
                }
                .tag(2)
        }
        .accentColor(.white)
        .preferredColorScheme(.dark)
        .onAppear {
            // 自定义TabBar外观
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.black
            appearance.selectionIndicatorTintColor = UIColor.white
            
            // 未选中状态
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.gray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.gray
            ]
            
            // 选中状态
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.white
            ]
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(DataManager())
}
