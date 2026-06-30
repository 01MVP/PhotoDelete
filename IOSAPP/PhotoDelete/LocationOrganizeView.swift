//
//  LocationOrganizeView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/21/26.
//

import Photos
import SwiftUI
import UIKit

struct LocationOrganizeView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var hasRequestedLocationGroups = false
    @State private var lastPhotoListSignature: String?

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    content
                }
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(L10n.string("地点整理"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            guard !hasRequestedLocationGroups else { return }
            hasRequestedLocationGroups = true
            refreshLocationGroups(force: true)
        }
        .onReceive(dataManager.photoLibraryManager.$allPhotos) { photos in
            let signature = photoListSignature(for: photos)
            guard lastPhotoListSignature != signature else { return }
            lastPhotoListSignature = signature
            dataManager.loadLocationGroups(force: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                PhotoDeleteIconTile(
                    icon: "mappin.and.ellipse",
                    tint: PhotoDeleteStyle.accent,
                    size: 42,
                    cornerRadius: 12,
                    filled: false
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("地点整理"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(L10n.string("按拍摄地点查看照片，只显示能识别出地名的分组。"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .photoDeleteCard()
    }

    @ViewBuilder
    private var content: some View {
        if shouldShowLoading {
            LocationOrganizeStateCard(
                icon: "location.magnifyingglass",
                title: L10n.string("正在整理地点"),
                message: L10n.string("读取完成后会显示可按地点整理的照片。"),
                showsProgress: true
            )
        } else if dataManager.locationGroups.isEmpty {
            LocationOrganizeStateCard(
                icon: "location.slash",
                title: L10n.string("还没有可按地点整理的照片"),
                message: emptyStateMessage,
                showsProgress: false,
                actionTitle: dataManager.unresolvedLocationGroupCount > 0 ? L10n.string("重试识别地名") : nil,
                action: dataManager.unresolvedLocationGroupCount > 0 ? {
                    refreshLocationGroups(force: true)
                } : nil
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("按地点继续"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .padding(.horizontal, 2)

                LazyVStack(spacing: 0) {
                    ForEach(Array(dataManager.locationGroups.enumerated()), id: \.element.id) { index, group in
                        NavigationLink(value: SwipeViewDestination.location(group.id)) {
                            LocationGroupRow(
                                group: group,
                                thumbnailAsset: dataManager.getPhotosForLocationGroup(group.id).first,
                                photoLibraryManager: dataManager.photoLibraryManager
                            )
                        }
                        .buttonStyle(.plain)

                        if index != dataManager.locationGroups.count - 1 {
                            Divider()
                                .background(PhotoDeleteStyle.hairline)
                                .padding(.leading, 76)
                        }
                    }
                }
                .photoDeleteCard()
            }
        }
    }

    private var shouldShowLoading: Bool {
        dataManager.locationGroups.isEmpty &&
            (
                dataManager.isLoadingLocationGroups ||
                dataManager.isResolvingLocationTitles ||
                (
                    dataManager.photoLibraryManager.hasPhotoLibraryAccess &&
                    dataManager.photoLibraryManager.isLoading &&
                    !dataManager.photoLibraryManager.hasLoadedPhotoLibrary
                )
            )
    }

    private var emptyStateMessage: String {
        if dataManager.unresolvedLocationGroupCount > 0 {
            return L10n.string("暂时没能识别出地名，可以稍后重试。")
        }
        return L10n.string("只显示能识别出地名的照片。")
    }

    private func refreshLocationGroups(force: Bool) {
        lastPhotoListSignature = photoListSignature(for: dataManager.photoLibraryManager.allPhotos)
        dataManager.loadLocationGroups(force: force)
    }

    private func photoListSignature(for photos: [PHAsset]) -> String {
        "\(photos.count)|\(photos.first?.localIdentifier ?? "")|\(photos.last?.localIdentifier ?? "")"
    }
}

private struct LocationGroupRow: View {
    let group: PhotoLocationGroupInfo
    let thumbnailAsset: PHAsset?
    let photoLibraryManager: PhotoLibraryManager

    var body: some View {
        HStack(spacing: 12) {
            LocationGroupThumbnail(
                asset: thumbnailAsset,
                photoLibraryManager: photoLibraryManager
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(group.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Text(group.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                ProgressView(value: group.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    .frame(height: 3)
                    .clipShape(Capsule(style: .continuous))
            }

            Spacer(minLength: 8)

            Text(L10n.shortPhotoCount(group.assetCount))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 82)
        .contentShape(Rectangle())
    }
}

private struct LocationGroupThumbnail: View {
    let asset: PHAsset?
    let photoLibraryManager: PhotoLibraryManager

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var loadingAssetIdentifier: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear(perform: loadImage)
        .onChange(of: asset?.localIdentifier) { _ in
            loadImage()
        }
        .onDisappear {
            photoLibraryManager.cancelImageRequest(requestID)
            loadingAssetIdentifier = nil
        }
    }

    private func loadImage() {
        photoLibraryManager.cancelImageRequest(requestID)
        guard let asset else {
            image = nil
            requestID = nil
            loadingAssetIdentifier = nil
            return
        }

        let requestedAssetID = asset.localIdentifier
        loadingAssetIdentifier = requestedAssetID
        image = nil
        requestID = photoLibraryManager.loadFastThumbnail(for: asset, size: CGSize(width: 120, height: 120)) { loadedImage in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            image = loadedImage
            requestID = nil
            loadingAssetIdentifier = nil
        }
    }
}

private struct LocationOrganizeStateCard: View {
    let icon: String
    let title: String
    let message: String
    let showsProgress: Bool
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.secondaryText)

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if showsProgress {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .photoDeleteMinimumTapTarget()
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: PhotoDeleteStyle.controlRadius, style: .continuous)
                        .fill(PhotoDeleteStyle.elevatedSurface)
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .photoDeleteCard()
    }
}
