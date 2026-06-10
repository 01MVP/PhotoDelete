//
//  SplashView.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import SwiftUI

struct SplashView: View {
    @StateObject private var dataManager = DataManager()
    @State private var showMainApp = false
    @State private var animateIcon = false
    @State private var loadingText = "正在准备..."
    @State private var showProgress = false
    
    var body: some View {
        ZStack {
            PhotoDelScreenBackground()
            
            VStack(spacing: 24) {
                Spacer()
                
                // App图标
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(PhotoDelStyle.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(PhotoDelStyle.hairline, lineWidth: 1)
                        )
                        .frame(width: 120, height: 120)

                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(PhotoDelStyle.accent)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(PhotoDelStyle.accent)
                        .offset(x: 26, y: 26)
                }
                .scaleEffect(animateIcon ? 1.0 : 0.9)
                .opacity(animateIcon ? 1.0 : 0.8)
                .animation(.easeOut(duration: 0.6), value: animateIcon)
                
                // App名称和标语
                VStack(spacing: 8) {
                    Text("PhotoDel")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(PhotoDelStyle.primaryText)
                    
                    Text("照片整理助手")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(PhotoDelStyle.secondaryText)
                }
                .opacity(animateIcon ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.6).delay(0.2), value: animateIcon)
                
                // 加载进度区域
                if showProgress {
                    VStack(spacing: 16) {
                        // 进度条
                        if dataManager.photoLibraryManager.isLoading {
                            VStack(spacing: 8) {
                                ProgressView(value: dataManager.photoLibraryManager.loadingProgress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDelStyle.accent))
                                    .frame(width: 200)
                                
                                Text("\(Int(dataManager.photoLibraryManager.loadingProgress * 100))%")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(PhotoDelStyle.primaryText)
                            }
                        }
                        
                        // 加载状态文字
                        Text(loadingText)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(PhotoDelStyle.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .transition(.opacity)
                }
                
                Spacer()
            }
        }
        .onAppear {
            // 启动动画
            animateIcon = true
            
            // 检查照片库权限状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                checkPhotoLibraryStatus()
            }
        }
        .fullScreenCover(isPresented: $showMainApp) {
            MainTabView()
                .environmentObject(dataManager)
        }
    }
    
    private func checkPhotoLibraryStatus() {
        if dataManager.photoLibraryManager.hasPhotoLibraryAccess {
            // 已授权，显示加载进度
            showProgress = true
            loadingText = "正在加载照片库..."
            if dataManager.photoLibraryManager.totalPhotosCount == 0 &&
                !dataManager.photoLibraryManager.isLoading {
                dataManager.reloadLibraryData()
            }

            // 监听加载完成
            monitorLoadingProgress()
        } else if dataManager.photoLibraryManager.authorizationStatus == .notDetermined {
            // 未确定权限，显示准备状态
            showProgress = true
            loadingText = "正在准备照片库访问..."
            
            // 等待权限请求结果
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showMainApp = true
            }
        } else {
            // 权限被拒绝，直接进入主应用
            loadingText = "准备完成"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showMainApp = true
            }
        }
    }
    
    private func monitorLoadingProgress() {
        // 监听加载进度
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if !dataManager.photoLibraryManager.isLoading && !dataManager.isPreparingLibrary {
                // 加载完成
                timer.invalidate()
                loadingText = "准备完成！"
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showMainApp = true
                }
            } else {
                // 更新加载文字
                let progress = dataManager.photoLibraryManager.loadingProgress
                if progress < 0.3 {
                    loadingText = "正在扫描照片库..."
                } else if progress < 0.6 {
                    loadingText = "正在分析照片信息..."
                } else if progress < 0.9 {
                    loadingText = "正在整理照片分类..."
                } else {
                    loadingText = "即将完成..."
                }
            }
        }
    }
}

#Preview {
    SplashView()
}
