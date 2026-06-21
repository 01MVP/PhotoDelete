//
//  LocationOrganizeView.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/21/26.
//

import SwiftUI

struct LocationOrganizeView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedFilter: LocationOrganizeFilter = .all
    @State private var showingSupporter = false

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(L10n.string("按拍摄地点查看照片，所有整理都只在本机完成。"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    locationFilterSection

                    if shouldShowPreparingState {
                        OrganizeLoadingCard(
                            title: L10n.string("正在整理地点"),
                            message: L10n.string("读取完成后会显示可按地点整理的照片。"),
                            progress: dataManager.photoLibraryManager.loadingProgress
                        )
                    } else if visibleGroups.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visibleGroups.enumerated()), id: \.element.id) { index, group in
                                NavigationLink(value: SwipeViewDestination.location(group.id)) {
                                    LocationGroupRow(group: group)
                                }
                                .buttonStyle(.plain)

                                if index != visibleGroups.count - 1 {
                                    Divider()
                                        .background(PhotoDeleteStyle.hairline)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .photoDeleteCard()
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
        }
        .onReceive(dataManager.photoLibraryManager.$allPhotos) { _ in
            dataManager.loadLocationGroups()
        }
        .sheet(isPresented: $showingSupporter) {
            SupporterView()
                .environmentObject(purchaseManager)
        }
    }

    @ViewBuilder
    private var locationFilterSection: some View {
        if purchaseManager.isSupporter {
            Picker(L10n.string("地点筛选"), selection: $selectedFilter) {
                ForEach(LocationOrganizeFilter.allCases) { filter in
                    Text(filter.title)
                        .tag(filter)
                }
            }
            .pickerStyle(.segmented)
        } else {
            LocationSupporterTeaserCard {
                showingSupporter = true
            }
        }
    }

    private var visibleGroups: [PhotoLocationGroupInfo] {
        guard purchaseManager.isSupporter else {
            return dataManager.locationGroups
        }

        switch selectedFilter {
        case .all:
            return dataManager.locationGroups
        case .needsReview:
            return dataManager.locationGroups
                .filter { $0.progress < 1 }
                .sorted {
                    remainingCount(for: $0) == remainingCount(for: $1)
                        ? $0.assetCount > $1.assetCount
                        : remainingCount(for: $0) > remainingCount(for: $1)
                }
        case .noLocation:
            return dataManager.locationGroups.filter(\.isNoLocationGroup)
        }
    }

    private var shouldShowPreparingState: Bool {
        dataManager.isPreparingLibrary ||
            dataManager.photoLibraryManager.isLoading ||
            (
                dataManager.photoLibraryManager.hasPhotoLibraryAccess &&
                !dataManager.photoLibraryManager.hasLoadedPhotoLibrary &&
                visibleGroups.isEmpty
            )
    }

    private func remainingCount(for group: PhotoLocationGroupInfo) -> Int {
        max(group.assetCount - group.reviewedCount, 0)
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
}

private enum LocationOrganizeFilter: String, CaseIterable, Identifiable {
    case all
    case needsReview
    case noLocation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return L10n.string("全部地点")
        case .needsReview:
            return L10n.string("未整理优先")
        case .noLocation:
            return L10n.string("无地点照片")
        }
    }
}

private struct LocationSupporterTeaserCard: View {
    let onOpenSupporter: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PhotoDeleteIconTile(icon: "line.3.horizontal.decrease.circle", tint: PhotoDeleteStyle.warning)

            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.string("支持者地点筛选"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Text(L10n.string("基础地点整理免费开放。支持者可以优先查看还没整理完的地点。"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onOpenSupporter) {
                    Text(L10n.string("查看支持者功能"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.accent)
                }
                .buttonStyle(.plain)
                .photoDeleteMinimumTapTarget()
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .photoDeleteCard()
    }
}

private struct LocationGroupRow: View {
    let group: PhotoLocationGroupInfo

    var body: some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(
                icon: group.isNoLocationGroup ? "location.slash" : "location",
                tint: group.isNoLocationGroup ? PhotoDeleteStyle.secondaryText : PhotoDeleteStyle.accent
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(group.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)

                Text(group.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                ProgressView(value: group.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    .frame(height: 4)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        LocationOrganizeView()
            .environmentObject(DataManager())
            .environmentObject(PurchaseManager())
    }
}
