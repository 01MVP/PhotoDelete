//
//  LocationOrganizeView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/21/26.
//

import MapKit
import SwiftUI

struct LocationOrganizeView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var mapRegion = LocationMapRegionResolver.defaultRegion
    @State private var selectedGroupID: String?
    @State private var mapRegionSignature: String?

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(L10n.string("按地图查看拍摄地点，点选一个地点后继续整理。"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if shouldShowPreparingState {
                        OrganizeLoadingCard(
                            title: L10n.string("正在整理地点"),
                            message: L10n.string("读取完成后会显示可按地点整理的照片。"),
                            progress: dataManager.photoLibraryManager.loadingProgress
                        )
                    } else {
                        if locationAnnotations.isEmpty {
                            if noLocationGroup == nil {
                                emptyState
                            } else {
                                mapEmptyState
                            }
                        } else {
                            mapSection
                            selectedLocationSection
                        }

                        if let noLocationGroup {
                            noLocationSection(group: noLocationGroup)
                        }
                    }
                }
                .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                .padding(.top, PhotoDeleteStyle.rootContentTopSpacing)
                .padding(.bottom, 96)
                .frame(maxWidth: PhotoDeleteAdaptiveLayout.readableContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L10n.string("地点"))
        .navigationBarTitleDisplayMode(.large)
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

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(L10n.string("地图"), systemImage: "map")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Spacer()

                Text(L10n.shortPhotoCount(mapPhotoCount))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            Text(L10n.string("点选地图上的地点后继续整理。"))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Map(coordinateRegion: $mapRegion, annotationItems: locationAnnotations) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    LocationMapPinView(
                        annotation: annotation,
                        isSelected: annotation.id == selectedGroupID
                    ) {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                            selectedGroupID = annotation.id
                        }
                    }
                }
            }
            .frame(height: mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PhotoDeleteStyle.hairline, lineWidth: 1)
            )
        }
        .padding(14)
        .photoDeleteCard()
    }

    @ViewBuilder
    private var selectedLocationSection: some View {
        if let selectedAnnotation {
            NavigationLink(value: SwipeViewDestination.location(selectedAnnotation.group.id)) {
                LocationMapSelectedGroupCard(annotation: selectedAnnotation)
            }
            .buttonStyle(.plain)
        } else {
            LocationMapPromptCard()
        }
    }

    private func noLocationSection(group: PhotoLocationGroupInfo) -> some View {
        NavigationLink(value: SwipeViewDestination.location(group.id)) {
            HStack(spacing: 12) {
                PhotoDeleteIconTile(icon: "location.slash", tint: PhotoDeleteStyle.secondaryText)

                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .lineLimit(1)

                    Text(group.subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .lineLimit(2)

                    ProgressView(value: group.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                        .frame(height: 4)
                        .clipShape(Capsule(style: .continuous))
                }

                Spacer(minLength: 8)

                Text(L10n.string("查看这些照片"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.tertiaryText)
            }
            .padding(16)
            .contentShape(Rectangle())
            .photoDeleteCard()
        }
        .buttonStyle(.plain)
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
        .photoDeleteCard()
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
        .photoDeleteCard()
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
        locationAnnotations.reduce(0) { $0 + $1.group.assetCount }
    }

    private var mapHeight: CGFloat {
        horizontalSizeClass == .regular ? 420 : 310
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
}

private struct LocationMapAnnotation: Identifiable {
    let group: PhotoLocationGroupInfo
    let coordinate: CLLocationCoordinate2D
    let displayIndex: Int

    var id: String { group.id }

    var title: String {
        String(format: L10n.string("附近地点 %lld"), Int64(displayIndex))
    }
}

private struct LocationMapPinView: View {
    let annotation: LocationMapAnnotation
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isSelected ? PhotoDeleteStyle.accent : PhotoDeleteStyle.elevatedSurface)
                        .frame(width: isSelected ? 40 : 34, height: isSelected ? 40 : 34)
                        .shadow(color: .black.opacity(isSelected ? 0.16 : 0.08), radius: isSelected ? 10 : 5, x: 0, y: 3)

                    Image(systemName: "mappin")
                        .font(.system(size: isSelected ? 19 : 16, weight: .bold))
                        .foregroundColor(isSelected ? PhotoDeleteStyle.primaryButtonText : PhotoDeleteStyle.accent)
                }

                Text(L10n.shortPhotoCount(annotation.group.assetCount))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(PhotoDeleteStyle.elevatedSurface.opacity(0.94))
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(annotation.title), \(L10n.shortPhotoCount(annotation.group.assetCount))")
    }
}

private struct LocationMapSelectedGroupCard: View {
    let annotation: LocationMapAnnotation

    var body: some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(icon: "mappin.and.ellipse", tint: PhotoDeleteStyle.accent)

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

            Text(L10n.string("查看这个地点"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.accent)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.tertiaryText)
        }
        .padding(16)
        .contentShape(Rectangle())
        .photoDeleteCard()
        .accessibilityElement(children: .combine)
    }
}

private struct LocationMapPromptCard: View {
    var body: some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(icon: "hand.tap", tint: PhotoDeleteStyle.accent)

            Text(L10n.string("点选地图上的地点"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PhotoDeleteStyle.primaryText)

            Spacer()
        }
        .padding(16)
        .photoDeleteCard()
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
