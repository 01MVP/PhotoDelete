import SwiftUI
import Photos

struct RealPhotoView: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let size: CGSize

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay(
                        overlayContent,
                        alignment: .topTrailing
                    )
            } else {
                // 加载状态
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.1, blue: 0.15),
                                Color(red: 0.15, green: 0.15, blue: 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                        }
                    )
                    .overlay(
                        overlayContent,
                        alignment: .topTrailing
                    )
            }
        }
        .cornerRadius(8)
        .onAppear {
            loadImage()
        }
        .onChange(of: asset.localIdentifier) { _ in
            loadImage()
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        VStack(spacing: 4) {
            // 视频图标
            if asset.mediaType == .video {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20))
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 24, height: 24)
                    )
            }

            // 收藏图标
            if asset.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 16))
                    .background(
                        Circle()
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                    )
            }

            // 截图标识
            if isScreenshot {
                Image(systemName: "camera.viewfinder")
                    .foregroundColor(.yellow)
                    .font(.system(size: 14))
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 18, height: 18)
                    )
            }
        }
        .padding(8)
    }

    private var isScreenshot: Bool {
        if #available(iOS 9.0, *) {
            return asset.mediaSubtypes.contains(.photoScreenshot)
        }

        // 备用方法：通过尺寸判断
        let screenScale = UIScreen.main.scale
        let screenSize = UIScreen.main.bounds.size
        let screenPixelSize = CGSize(
            width: screenSize.width * screenScale,
            height: screenSize.height * screenScale
        )

        let assetSize = CGSize(width: CGFloat(asset.pixelWidth), height: CGFloat(asset.pixelHeight))

        return abs(assetSize.width - screenPixelSize.width) < 10 &&
               abs(assetSize.height - screenPixelSize.height) < 10
    }

    private func loadImage() {
        isLoading = true
        image = nil

        photoLibraryManager.loadImage(for: asset, size: size) { loadedImage in
            self.image = loadedImage
            self.isLoading = false
        }
    }
}

// MARK: - Photo Grid View

struct PhotoGridView: View {
    let photos: [PHAsset]
    let photoLibraryManager: PhotoLibraryManager
    let columns = 3
    let spacing: CGFloat = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
            ForEach(photos, id: \.localIdentifier) { asset in
                RealPhotoView(
                    asset: asset,
                    photoLibraryManager: photoLibraryManager,
                    size: CGSize(width: itemWidth, height: itemWidth)
                )
            }
        }
        .padding(.horizontal, 16)
    }

    private var itemWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let totalSpacing = CGFloat(columns - 1) * spacing + 32 // 32 for horizontal padding
        return (screenWidth - totalSpacing) / CGFloat(columns)
    }
}

// MARK: - Full Screen Photo View

struct FullScreenPhotoView: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    @State private var image: UIImage?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }

            // 关闭按钮
            VStack {
                HStack {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()

                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear {
            loadFullImage()
        }
    }

    private func loadFullImage() {
        photoLibraryManager.loadFullImage(for: asset) { loadedImage in
            self.image = loadedImage
            self.isLoading = false
        }
    }
}

// MARK: - Preview

struct RealPhotoView_Previews: PreviewProvider {
    static var previews: some View {
        // 注意：预览无法显示真实照片，需要在真机或模拟器上运行
        Text("需要在真机或模拟器上运行以显示真实照片")
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
    }
}
