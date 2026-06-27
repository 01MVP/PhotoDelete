//
//  LocationOrganizeView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/21/26.
//

import MapKit
import Photos
import SwiftUI
import UIKit

struct LocationOrganizeView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var mapRegion = LocationMapRegionResolver.defaultRegion
    @State private var selectedGroupID: String?
    @State private var mapRegionSignature: String?

    var body: some View {
        ZStack {
            Map(coordinateRegion: $mapRegion, interactionModes: .all, annotationItems: locationAnnotations) { annotation in
                MapAnnotation(coordinate: annotation.coordinate, anchorPoint: CGPoint(x: 0.5, y: 1)) {
                    LocationMapPhotoMarkerView(
                        annotation: annotation,
                        isSelected: annotation.id == selectedGroupID
                    ) {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                            selectedGroupID = annotation.id
                        }
                    }
                }
            }
            .ignoresSafeArea()

            LocationMapTopChrome(
                photoCount: mapPhotoCount,
                onDismiss: { dismiss() }
            )

            LocationMapControls {
                recenterMap()
            }

            if shouldShowPreparingState {
                LocationMapOverlayCard {
                    OrganizeLoadingCard(
                        title: L10n.string("正在整理地点"),
                        message: L10n.string("读取完成后会显示可按地点整理的照片。"),
                        progress: dataManager.photoLibraryManager.loadingProgress
                    )
                }
            } else if locationAnnotations.isEmpty {
                LocationMapOverlayCard {
                    if noLocationGroup == nil {
                        emptyState
                    } else {
                        mapEmptyState
                    }
                }
            }

            VStack {
                Spacer()
                bottomPanel
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .background(PhotoDeleteStyle.background.ignoresSafeArea())
        .navigationTitle(L10n.string("地点"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            dataManager.loadLocationGroups()
            refreshMapStateIfNeeded()
        }
        .onReceive(dataManager.photoLibraryManager.$allPhotos) { _ in
            dataManager.loadLocationGroups(force: true)
        }
        .onChange(of: dataManager.locationGroupsRevision) { _ in
            refreshMapStateIfNeeded()
        }
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if selectedAnnotation != nil || noLocationGroup != nil {
            VStack(spacing: 10) {
                if let selectedAnnotation {
                    NavigationLink(value: SwipeViewDestination.location(selectedAnnotation.group.id)) {
                        LocationMapSelectedGroupPanel(
                            annotation: selectedAnnotation,
                            thumbnailAsset: selectedThumbnailAsset,
                            photoLibraryManager: dataManager.photoLibraryManager
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let noLocationGroup {
                    NavigationLink(value: SwipeViewDestination.location(noLocationGroup.id)) {
                        LocationMapNoLocationChip(group: noLocationGroup)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, bottomPanelHorizontalPadding)
            .padding(.bottom, 22)
        }
    }

    private var mapEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "map")
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.secondaryText)

            Text(L10n.string("地图上暂无可显示的地点"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            Text(L10n.string("带地点信息的照片会显示在地图上。"))
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "location.slash")
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.secondaryText)

            Text(L10n.string("还没有可按地点整理的照片"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            Text(L10n.string("当前授权范围内没有带地点信息的照片。"))
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var locationAnnotations: [LocationMapAnnotation] {
        mapGroups.enumerated().compactMap { index, group in
            guard let coordinate = dataManager.locationGroupCoordinatesByGroupID[group.id] else {
                return nil
            }
            return LocationMapAnnotation(
                group: group,
                coordinate: coordinate,
                displayIndex: index + 1
            )
        }
    }

    private var mapGroups: [PhotoLocationGroupInfo] {
        dataManager.locationGroups.filter { !$0.isNoLocationGroup }
    }

    private var noLocationGroup: PhotoLocationGroupInfo? {
        dataManager.locationGroups.first(where: \.isNoLocationGroup)
    }

    private var selectedAnnotation: LocationMapAnnotation? {
        guard let selectedGroupID else { return nil }
        return locationAnnotations.first { $0.id == selectedGroupID }
    }

    private var mapPhotoCount: Int {
        mapGroups.reduce(0) { $0 + $1.assetCount }
    }

    private var selectedThumbnailAsset: PHAsset? {
        guard let selectedGroupID else { return nil }
        return dataManager.getPhotosForLocationGroup(selectedGroupID).first
    }

    private var bottomPanelHorizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 28 : 16
    }

    private var shouldShowPreparingState: Bool {
        dataManager.locationGroups.isEmpty &&
            (
                dataManager.isPreparingLibrary ||
                dataManager.isLoadingLocationGroups ||
                (
                    dataManager.photoLibraryManager.hasPhotoLibraryAccess &&
                    dataManager.photoLibraryManager.isLoading &&
                    !dataManager.photoLibraryManager.hasLoadedPhotoLibrary
                )
            )
    }

    private func refreshMapStateIfNeeded() {
        let annotations = locationAnnotations
        let signature = annotations
            .map { annotation in
                "\(annotation.id):\(annotation.coordinate.latitude):\(annotation.coordinate.longitude):\(annotation.group.assetCount):\(annotation.group.reviewedCount)"
            }
            .joined(separator: "|")

        guard signature != mapRegionSignature else { return }
        mapRegionSignature = signature

        if annotations.isEmpty {
            selectedGroupID = nil
            return
        }

        if selectedGroupID == nil || annotations.contains(where: { $0.id == selectedGroupID }) == false {
            selectedGroupID = annotations.first?.id
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            mapRegion = LocationMapRegionResolver.region(for: annotations)
        }
    }

    private func recenterMap() {
        guard !locationAnnotations.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.24)) {
            mapRegion = LocationMapRegionResolver.region(for: locationAnnotations)
        }
    }
}

private struct LocationMapAnnotation: Identifiable {
    let group: PhotoLocationGroupInfo
    let coordinate: CLLocationCoordinate2D
    let displayIndex: Int

    var id: String { group.id }

    var title: String {
        group.title
    }
}

private struct LocationMapTopChrome: View {
    let photoCount: Int
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .frame(width: 54, height: 54)
                        .background(.regularMaterial, in: Circle())
                        .overlay(
                            Circle()
                                .stroke(PhotoDeleteStyle.primaryText.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("返回"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("地点"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)

                    Text(L10n.shortPhotoCount(photoCount))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(PhotoDeleteStyle.primaryText.opacity(0.08), lineWidth: 1)
                )

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Spacer()
        }
    }
}

private struct LocationMapControls: View {
    let onRecenter: () -> Void

    var body: some View {
        VStack {
            Spacer()
                .frame(height: 126)

            HStack {
                Spacer()

                VStack(spacing: 10) {
                    Button(action: onRecenter) {
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(PhotoDeleteStyle.accent)
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("回到全部地点"))
                }
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(PhotoDeleteStyle.primaryText.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 6)
                .padding(.trailing, 16)
            }

            Spacer()
        }
    }
}

private struct LocationMapOverlayCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack {
            Spacer()

            content
                .padding(16)
                .frame(maxWidth: 360)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(PhotoDeleteStyle.primaryText.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)

            Spacer()
        }
        .padding(.horizontal, 22)
    }
}

private struct LocationMapPhotoMarkerView: View {
    let annotation: LocationMapAnnotation
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isSelected ? PhotoDeleteStyle.accent : PhotoDeleteStyle.surface)

                    VStack(spacing: 2) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: isSelected ? 20 : 17, weight: .semibold))
                            .foregroundColor(isSelected ? .white : PhotoDeleteStyle.accent)

                        Text(L10n.shortPhotoCount(annotation.group.assetCount))
                            .font(.system(size: isSelected ? 12 : 11, weight: .bold))
                            .foregroundColor(isSelected ? .white : PhotoDeleteStyle.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .padding(.horizontal, 5)
                }
                .frame(width: markerSize, height: markerSize)
                .overlay(
                    Circle()
                        .stroke(.white, lineWidth: isSelected ? 4 : 3)
                )
                .shadow(color: .black.opacity(isSelected ? 0.22 : 0.12), radius: isSelected ? 12 : 7, x: 0, y: 5)

                Triangle()
                    .fill(isSelected ? PhotoDeleteStyle.accent : PhotoDeleteStyle.surface)
                    .frame(width: 14, height: 8)
                    .shadow(color: .black.opacity(0.10), radius: 2, x: 0, y: 1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.08 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isSelected)
        .accessibilityLabel("\(annotation.title), \(L10n.shortPhotoCount(annotation.group.assetCount))")
    }

    private var markerSize: CGFloat {
        isSelected ? 62 : 52
    }
}

private struct LocationMapThumbnailView: View {
    let asset: PHAsset?
    let photoLibraryManager: PhotoLibraryManager
    let size: CGFloat

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(PhotoDeleteStyle.elevatedSurface)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: size * 0.30, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .onAppear(perform: loadThumbnail)
        .onChange(of: asset?.localIdentifier) { _ in
            loadThumbnail()
        }
        .onDisappear {
            photoLibraryManager.cancelImageRequest(requestID)
            requestID = nil
        }
    }

    private func loadThumbnail() {
        photoLibraryManager.cancelImageRequest(requestID)
        requestID = nil
        image = nil

        guard let asset else { return }
        requestID = photoLibraryManager.loadGridThumbnail(
            for: asset,
            size: CGSize(width: size * 2, height: size * 2)
        ) { loadedImage in
            image = loadedImage
            requestID = nil
        }
    }
}

private struct LocationMapSelectedGroupPanel: View {
    let annotation: LocationMapAnnotation
    let thumbnailAsset: PHAsset?
    let photoLibraryManager: PhotoLibraryManager

    var body: some View {
        HStack(spacing: 12) {
            LocationMapThumbnailView(
                asset: thumbnailAsset,
                photoLibraryManager: photoLibraryManager,
                size: 58
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(annotation.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)

                Text(annotation.group.subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)

                ProgressView(value: annotation.group.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    .frame(height: 4)
                    .clipShape(Capsule(style: .continuous))
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
        }
        .padding(16)
        .contentShape(Rectangle())
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PhotoDeleteStyle.primaryText.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }
}

private struct LocationMapNoLocationChip: View {
    let group: PhotoLocationGroupInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .frame(width: 30, height: 30)
                .background(PhotoDeleteStyle.elevatedSurface, in: Circle())

            Text(group.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)
                .lineLimit(1)

            Spacer()

            Text(L10n.shortPhotoCount(group.assetCount))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.secondaryText)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(PhotoDeleteStyle.primaryText.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private enum LocationMapRegionResolver {
    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 160)
    )

    static func region(for annotations: [LocationMapAnnotation]) -> MKCoordinateRegion {
        let coordinates = annotations.map(\.coordinate)
        guard let first = coordinates.first else { return defaultRegion }
        guard coordinates.count > 1 else {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
            )
        }

        let minLatitude = coordinates.map(\.latitude).min() ?? first.latitude
        let maxLatitude = coordinates.map(\.latitude).max() ?? first.latitude
        let minLongitude = coordinates.map(\.longitude).min() ?? first.longitude
        let maxLongitude = coordinates.map(\.longitude).max() ?? first.longitude
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = min(max((maxLatitude - minLatitude) * 1.55, 0.12), 140)
        let longitudeDelta = min(max((maxLongitude - minLongitude) * 1.55, 0.12), 320)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}

#Preview {
    NavigationStack {
        LocationOrganizeView()
            .environmentObject(DataManager())
            .environmentObject(PurchaseManager())
    }
}
