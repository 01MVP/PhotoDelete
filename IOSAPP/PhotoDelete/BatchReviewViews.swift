//
//  BatchReviewViews.swift
//  PhotoDelete
//

import SwiftUI
import AVKit
import CoreLocation
import Photos
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 批量确认视图
struct BatchConfirmView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var previewAsset: CandidatePreviewAsset?
    @State private var completedCelebration: CleanupCelebration?
    @State private var showAchievements = false
    @State private var selectedDeleteIDs: Set<String> = []
    @State private var selectedFavoriteIDs: Set<String> = []
    let albumInfo: AlbumInfo?
    let onComplete: (() -> Void)?

    init(albumInfo: AlbumInfo? = nil, onComplete: (() -> Void)? = nil) {
        self.albumInfo = albumInfo
        self.onComplete = onComplete
    }

    private var hasPendingOperations: Bool {
        !dataManager.deleteCandidates.isEmpty || !dataManager.favoriteCandidates.isEmpty
    }

    private var hasSelectedOperations: Bool {
        !selectedDeleteIDs.isEmpty || !selectedFavoriteIDs.isEmpty
    }

    var body: some View {
        ZStack {
            PhotoDeleteScreenBackground()

            if let completedCelebration {
                BatchCleanupCompletionView(
                    celebration: completedCelebration,
                    onViewAchievements: { showAchievements = true },
                    onContinue: finishCompletedFlow
                )
            } else {
                let deleteAssets = sortedAssets(Array(dataManager.deleteCandidates))
                let favoriteAssets = sortedAssets(Array(dataManager.favoriteCandidates))
                let selectedDeleteAssets = deleteAssets.filter { selectedDeleteIDs.contains($0.localIdentifier) }
                let selectedFavoriteAssets = favoriteAssets.filter { selectedFavoriteIDs.contains($0.localIdentifier) }
                let estimatedSpaceSaved = selectedDeleteAssets.reduce(0) { $0 + dataManager.estimatedSizeMB(for: $1) }

                confirmationContent(
                    deleteAssets: deleteAssets,
                    favoriteAssets: favoriteAssets,
                    selectedDeleteAssets: selectedDeleteAssets,
                    selectedFavoriteAssets: selectedFavoriteAssets,
                    estimatedSpaceSaved: estimatedSpaceSaved
                )
            }
        }
        .onAppear(perform: selectAllPendingCandidates)
        .sheet(item: $previewAsset) { previewAsset in
            CandidatePhotoPreviewView(
                asset: previewAsset.asset,
                photoLibraryManager: dataManager.photoLibraryManager
            )
        }
        .fullScreenCover(isPresented: $showAchievements) {
            NavigationStack {
                CleanupAchievementsView(
                    statsStore: dataManager.cleanupStatsStore,
                    showsDoneButton: true
                )
            }
        }
    }

    private func confirmationContent(
        deleteAssets: [PHAsset],
        favoriteAssets: [PHAsset],
        selectedDeleteAssets: [PHAsset],
        selectedFavoriteAssets: [PHAsset],
        estimatedSpaceSaved: Double
    ) -> some View {
        VStack(spacing: 22) {
            VStack(spacing: 16) {
                Image(systemName: selectedDeleteAssets.isEmpty ? "checkmark.circle.fill" : "trash.circle.fill")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundColor(selectedDeleteAssets.isEmpty ? PhotoDeleteStyle.positive : PhotoDeleteStyle.destructive)

                Text(L10n.string("确认清理"))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                VStack(spacing: 8) {
                    if !deleteAssets.isEmpty {
                        Text(L10n.string("删除 \(selectedDeleteAssets.count) 张照片"))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.destructive)

                        if selectedDeleteAssets.isEmpty {
                            Text(L10n.string("未勾选的项目不会执行。"))
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(PhotoDeleteStyle.secondaryText)
                        } else {
                            Text(L10n.string("预计节省 \(CleanupStatsFormatter.space(estimatedSpaceSaved))"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(PhotoDeleteStyle.positive)
                        }
                    }

                    if !favoriteAssets.isEmpty {
                        Text(L10n.string("收藏 \(selectedFavoriteAssets.count) 张照片"))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.iconTint(for: "favorite"))
                    }

                    if !hasPendingOperations {
                        Text(L10n.string("没有待执行的操作"))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(PhotoDeleteStyle.warning)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }

                if hasPendingOperations {
                    Label(L10n.string("默认已勾选，取消勾选后不会执行。"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .labelStyle(.titleAndIcon)
                }
            }

            if hasPendingOperations {
                ScrollView {
                    VStack(spacing: 18) {
                        if !deleteAssets.isEmpty {
                            CandidatePreviewSection(
                                title: L10n.string("将删除"),
                                assets: deleteAssets,
                                selectedCount: selectedDeleteAssets.count,
                                selectedAssetIDs: selectedDeleteIDs,
                                color: PhotoDeleteStyle.destructive,
                                icon: "trash.fill",
                                photoLibraryManager: dataManager.photoLibraryManager,
                                selectAccessibilityLabel: L10n.string("勾选这张照片"),
                                deselectAccessibilityLabel: L10n.string("取消勾选这张照片"),
                                onPreview: { previewAsset = CandidatePreviewAsset(asset: $0) },
                                onToggleSelection: toggleDeleteSelection
                            )
                        }

                        if !favoriteAssets.isEmpty {
                            CandidatePreviewSection(
                                title: L10n.string("将收藏"),
                                assets: favoriteAssets,
                                selectedCount: selectedFavoriteAssets.count,
                                selectedAssetIDs: selectedFavoriteIDs,
                                color: PhotoDeleteStyle.iconTint(for: "favorite"),
                                icon: "heart.fill",
                                photoLibraryManager: dataManager.photoLibraryManager,
                                selectAccessibilityLabel: L10n.string("勾选这张照片"),
                                deselectAccessibilityLabel: L10n.string("取消勾选这张照片"),
                                onPreview: { previewAsset = CandidatePreviewAsset(asset: $0) },
                                onToggleSelection: toggleFavoriteSelection
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 330)
            }

            VStack(spacing: 12) {
                Button(action: executeBatchOperations) {
                    Text(isProcessing ? L10n.string("正在执行...") : L10n.string("确认执行"))
                }
                .photoDeletePrimaryButton()
                .disabled(isProcessing || !hasSelectedOperations)

                Button(action: cancelOperations) {
                    Text(L10n.string("返回继续整理"))
                }
                .photoDeleteSecondaryButton()
                .disabled(isProcessing)

                Button(role: .destructive, action: cancelAllPendingOperations) {
                    Text(L10n.string("取消所有操作"))
                }
                .photoDeleteDestructiveButton()
                .disabled(isProcessing || !hasPendingOperations)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .photoDeleteCard()
        .frame(maxWidth: 620)
        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
    }

    private func executeBatchOperations() {
        let deletedAssets = sortedAssets(Array(dataManager.deleteCandidates))
            .filter { selectedDeleteIDs.contains($0.localIdentifier) }
        let favoriteAssets = sortedAssets(Array(dataManager.favoriteCandidates))
            .filter { selectedFavoriteIDs.contains($0.localIdentifier) }

        guard !deletedAssets.isEmpty || !favoriteAssets.isEmpty else {
            dismiss()
            return
        }

        isProcessing = true
        errorMessage = nil
        let estimatedSpaceSaved = deletedAssets.reduce(0) { $0 + dataManager.estimatedSizeMB(for: $1) }
        dataManager.executeBatchOperations(
            deleteAssets: deletedAssets,
            favoriteAssets: favoriteAssets
        ) { success, error, celebration in
            DispatchQueue.main.async {
                isProcessing = false
                if success {
                    completedCelebration = celebration ?? CleanupCelebration(
                        deletedPhotos: deletedAssets.count,
                        favoritedPhotos: favoriteAssets.count,
                        organizedPhotos: deletedAssets.count + favoriteAssets.count,
                        estimatedSpaceSavedMB: estimatedSpaceSaved,
                        totalDeletedPhotos: dataManager.cleanupStatsStore.summary.deletedPhotos,
                        totalSpaceSavedMB: dataManager.cleanupStatsStore.summary.estimatedSpaceSavedMB,
                        currentStreakDays: dataManager.cleanupStatsStore.currentStreakDays,
                        nextAchievementProgress: dataManager.cleanupStatsStore.nextAchievementProgress
                    )
                    playCompletionHaptics()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        dataManager.recordDeletedPhotosFromAlbum(
                            albumID: albumInfo?.id,
                            deletedAssets: deletedAssets
                        )
                    }
                } else {
                    errorMessage = error?.localizedDescription ?? L10n.string("操作失败，请稍后重试。")
                }
            }
        }
    }

    private func selectAllPendingCandidates() {
        selectedDeleteIDs = Set(dataManager.deleteCandidates.map(\.localIdentifier))
        selectedFavoriteIDs = Set(dataManager.favoriteCandidates.map(\.localIdentifier))
    }

    private func toggleDeleteSelection(_ asset: PHAsset) {
        HapticManager.impact(.light)
        let id = asset.localIdentifier
        if selectedDeleteIDs.contains(id) {
            selectedDeleteIDs.remove(id)
        } else {
            selectedDeleteIDs.insert(id)
        }
    }

    private func toggleFavoriteSelection(_ asset: PHAsset) {
        HapticManager.impact(.light)
        let id = asset.localIdentifier
        if selectedFavoriteIDs.contains(id) {
            selectedFavoriteIDs.remove(id)
        } else {
            selectedFavoriteIDs.insert(id)
        }
    }

    private func playCompletionHaptics() {
        HapticManager.notify(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            HapticManager.impact(.light)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            HapticManager.impact(.medium)
        }
    }

    private func finishCompletedFlow() {
        dismiss()
        onComplete?()
    }

    private func cancelOperations() {
        dismiss()
    }

    private func cancelAllPendingOperations() {
        selectedDeleteIDs.removeAll()
        selectedFavoriteIDs.removeAll()
        dataManager.cancelAllOperations()
        dismiss()
    }

    private func sortedAssets(_ assets: [PHAsset]) -> [PHAsset] {
        assets.sorted { lhs, rhs in
            let lhsDate = lhs.creationDate ?? .distantPast
            let rhsDate = rhs.creationDate ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.localIdentifier < rhs.localIdentifier
            }
            return lhsDate > rhsDate
        }
    }
}

private struct BatchCleanupCompletionView: View {
    let celebration: CleanupCelebration
    let onViewAchievements: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false
    @State private var progressFill = 0.0
    @State private var celebrationTrigger = 0

    var body: some View {
        ZStack {
            PhotoDeleteStyle.background.opacity(0.72)
                .ignoresSafeArea()

            VStack {
                Spacer(minLength: 24)

                VStack(spacing: 16) {
                    celebrationVisual
                    completionHeader
                    cleanupSummarySection
                    progressSnapshotSection
                    completionActions
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
                .frame(maxWidth: 540)
                .photoDeleteCard()

                Spacer(minLength: 24)
            }
            .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
        }
        .task {
            await startCompletionAnimation()
        }
    }

    @MainActor
    private func startCompletionAnimation() async {
        let targetProgress = min(max(celebration.nextAchievementProgress?.progress ?? 1, 0), 1)
        if reduceMotion {
            animate = true
            progressFill = targetProgress
            return
        }

        animate = false
        progressFill = 0

        try? await Task.sleep(nanoseconds: 80_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
            animate = true
        }
        celebrationTrigger += 1

        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.58)) {
            progressFill = targetProgress
        }
    }

    private var celebrationVisual: some View {
        ZStack {
            Circle()
                .fill(PhotoDeleteStyle.warning.opacity(0.14))
                .frame(width: 84, height: 84)
                .scaleEffect(animate ? 1 : 0.86)

            Circle()
                .stroke(PhotoDeleteStyle.warning.opacity(0.26), lineWidth: 1)
                .frame(width: 70, height: 70)
                .scaleEffect(animate ? 1.04 : 0.9)

            celebrationSymbol
        }
        .frame(height: 108)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: animate)
        .accessibilityHidden(true)
    }

    private var partyPopperSymbol: some View {
        Image(systemName: "party.popper.fill")
            .symbolRenderingMode(.multicolor)
            .font(.system(size: 52, weight: .semibold))
            .scaleEffect(animate ? 1 : 0.86)
            .rotationEffect(.degrees(animate ? 0 : -8))
            .opacity(animate ? 1 : 0.86)
    }

    @ViewBuilder
    private var celebrationSymbol: some View {
        if reduceMotion {
            partyPopperSymbol
        } else if #available(iOS 17.0, *) {
            partyPopperSymbol
                .symbolEffect(.bounce, value: celebrationTrigger)
        } else {
            partyPopperSymbol
        }
    }

    private var completionHeader: some View {
        Text(L10n.string("清理完成"))
            .font(.system(size: 31, weight: .semibold))
            .foregroundColor(PhotoDeleteStyle.primaryText)
    }

    private var cleanupSummarySection: some View {
        HStack(spacing: 0) {
            summaryItem(
                icon: "trash.fill",
                title: L10n.string("本次删除"),
                value: L10n.shortPhotoCount(celebration.deletedPhotos),
                detail: "\(L10n.string("节省")) \(celebration.formattedSpaceSaved)",
                tint: PhotoDeleteStyle.destructive
            )

            Divider()
                .frame(height: 34)
                .background(PhotoDeleteStyle.hairline)
                .padding(.horizontal, 10)

            summaryItem(
                icon: "chart.bar.fill",
                title: L10n.string("累计删除"),
                value: L10n.shortPhotoCount(celebration.totalDeletedPhotos),
                detail: "\(L10n.string("节省")) \(celebration.formattedTotalSpaceSaved)",
                tint: PhotoDeleteStyle.accent
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PhotoDeleteStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PhotoDeleteStyle.cardStroke, lineWidth: 1)
                )
        )
    }

    private func summaryItem(icon: String, title: String, value: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)

                Text(value)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text(detail)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }

            Spacer(minLength: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completionActions: some View {
        VStack(spacing: 10) {
            Button(action: onViewAchievements) {
                Label(L10n.string("查看成就"), systemImage: "seal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundColor(PhotoDeleteStyle.primaryText)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PhotoDeleteStyle.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(PhotoDeleteStyle.cardStroke, lineWidth: 1)
                    )
            )

            Button(action: onContinue) {
                Text(L10n.string("继续整理"))
            }
            .photoDeletePrimaryButton()
        }
    }

    private var progressSnapshotSection: some View {
        VStack(spacing: 0) {
            if let newestAchievement = celebration.newAchievements.first {
                compactStatusRow(
                    icon: newestAchievement.systemImage,
                    tint: newestAchievement.tint.color,
                    title: String(format: L10n.string("新徽章：%@"), newestAchievement.title),
                    subtitle: newestAchievement.subtitle
                )

                Divider()
                    .padding(.leading, 48)
            }

            compactStatusRow(
                icon: "flame.fill",
                tint: PhotoDeleteStyle.warning,
                title: L10n.string("连续整理 \(streakDaysForDisplay) 天"),
                subtitle: L10n.string("保持节奏，相册会越来越轻。")
            )

            Divider()
                .padding(.leading, 48)

            if let nextAchievementProgress = celebration.nextAchievementProgress {
                nextGoalCard(nextAchievementProgress)
            } else {
                compactStatusRow(
                    icon: "checkmark.seal.fill",
                    tint: PhotoDeleteStyle.positive,
                    title: L10n.string("全部徽章已完成"),
                    subtitle: L10n.string("可以在成就页回看完整记录。")
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PhotoDeleteStyle.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(PhotoDeleteStyle.cardStroke, lineWidth: 1)
                )
        )
    }

    private func compactStatusRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(
                icon: icon,
                tint: tint,
                size: 34,
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer()
        }
        .padding(14)
    }

    private var streakDaysForDisplay: Int {
        max(celebration.currentStreakDays, celebration.organizedPhotos > 0 ? 1 : 0)
    }

    private func nextGoalCard(_ progress: CleanupAchievementProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                PhotoDeleteIconTile(
                    icon: progress.achievement.systemImage,
                    tint: progress.achievement.tint.color,
                    size: 34,
                    cornerRadius: 10
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("下一个目标：\(progress.achievement.title)"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PhotoDeleteStyle.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(progress.remainingDescription)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer()

                Text("\(Int((progress.progress * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(progress.achievement.tint.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(progress.achievement.tint.color.opacity(0.12))
                    )
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(PhotoDeleteStyle.hairline)

                    Capsule(style: .continuous)
                        .fill(progress.achievement.tint.color)
                        .frame(width: max(0, proxy.size.width * progressFill))
                }
            }
            .frame(height: 7)
        }
        .padding(14)
    }

}

private struct CandidatePreviewSection: View {
    let title: String
    let assets: [PHAsset]
    let selectedCount: Int
    let selectedAssetIDs: Set<String>
    let color: Color
    let icon: String
    let photoLibraryManager: PhotoLibraryManager
    let selectAccessibilityLabel: String
    let deselectAccessibilityLabel: String
    let onPreview: (PHAsset) -> Void
    let onToggleSelection: (PHAsset) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 64, maximum: 76), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)

                Text(L10n.string("\(title) \(selectedCount) 张"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)

                Spacer()
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    CandidateThumbnailView(
                        asset: asset,
                        photoLibraryManager: photoLibraryManager,
                        badgeColor: color,
                        badgeIcon: icon,
                        isSelected: selectedAssetIDs.contains(asset.localIdentifier),
                        selectAccessibilityLabel: selectAccessibilityLabel,
                        deselectAccessibilityLabel: deselectAccessibilityLabel,
                        onPreview: { onPreview(asset) },
                        onToggleSelection: { onToggleSelection(asset) }
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PhotoDeleteStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(color.opacity(0.24), lineWidth: 1)
                )
        )
    }
}

private struct CandidateThumbnailView: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    let badgeColor: Color
    let badgeIcon: String
    let isSelected: Bool
    let selectAccessibilityLabel: String
    let deselectAccessibilityLabel: String
    let onPreview: () -> Void
    let onToggleSelection: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var requestID: PHImageRequestID?
    @State private var loadingAssetIdentifier: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: onPreview) {
                thumbnailContent
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("放大查看照片"))

            Image(systemName: badgeIcon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(isSelected ? badgeColor : PhotoDeleteStyle.tertiaryText))
                .overlay(Circle().stroke(PhotoDeleteStyle.background.opacity(0.8), lineWidth: 1.5))
                .offset(x: -53, y: -53)

            Button(action: onToggleSelection) {
                Label(
                    isSelected ? deselectAccessibilityLabel : selectAccessibilityLabel,
                    systemImage: isSelected ? "checkmark.circle.fill" : "circle"
                )
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isSelected ? PhotoDeleteStyle.positive : PhotoDeleteStyle.tertiaryText)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(PhotoDeleteStyle.background.opacity(0.92)))
                    .overlay(Circle().stroke(PhotoDeleteStyle.primaryText.opacity(isSelected ? 0.18 : 0.12), lineWidth: 1))
                    .photoDeleteMinimumTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.string("取消勾选后不会执行这项操作"))
            .offset(x: 3, y: 3)
        }
        .frame(width: 76, height: 76)
        .onAppear(perform: loadImage)
        .onDisappear {
            photoLibraryManager.cancelImageRequest(requestID)
            loadingAssetIdentifier = nil
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .saturation(isSelected ? 1 : 0.18)
                .opacity(isSelected ? 1 : 0.42)
        } else {
            Rectangle()
                .fill(PhotoDeleteStyle.elevatedSurface)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                            .scaleEffect(0.72)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                    }
                }
        }
    }

    private func loadImage() {
        photoLibraryManager.cancelImageRequest(requestID)
        let requestedAssetID = asset.localIdentifier
        loadingAssetIdentifier = requestedAssetID
        image = nil
        isLoading = true

        requestID = photoLibraryManager.loadFastThumbnail(for: asset, size: CGSize(width: 150, height: 150)) { loadedImage in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            image = loadedImage
            isLoading = false
            requestID = nil
            loadingAssetIdentifier = nil
        }
    }
}

struct CandidatePreviewAsset: Identifiable {
    let asset: PHAsset

    var id: String {
        asset.localIdentifier
    }
}

func photoPreviewTargetSize(for asset: PHAsset, viewport: CGSize, displayScale: CGFloat) -> CGSize {
    let pixelWidth = max(CGFloat(asset.pixelWidth), 1)
    let pixelHeight = max(CGFloat(asset.pixelHeight), 1)
    let assetLongEdge = max(pixelWidth, pixelHeight)
    let viewportLongEdge = max(viewport.width, viewport.height) * displayScale
    let requestedLongEdge = min(max(viewportLongEdge * 3, 2_400), min(assetLongEdge, 6_000))
    let ratio = requestedLongEdge / assetLongEdge

    return CGSize(
        width: max(pixelWidth * ratio, viewport.width * displayScale),
        height: max(pixelHeight * ratio, viewport.height * displayScale)
    )
}

struct ZoomablePhotoPreview: UIViewRepresentable {
    let image: UIImage
    var maximumZoomScale: CGFloat = 5

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = maximumZoomScale
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = context.coordinator

        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        scrollView.maximumZoomScale = maximumZoomScale
        if context.coordinator.image !== image {
            context.coordinator.image = image
            context.coordinator.imageView.image = image
            scrollView.setZoomScale(1, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?
        weak var image: UIImage?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let targetScale = min(max(scrollView.minimumZoomScale * 3, 2.5), scrollView.maximumZoomScale)
            let point = recognizer.location(in: imageView)
            let size = CGSize(
                width: scrollView.bounds.width / targetScale,
                height: scrollView.bounds.height / targetScale
            )
            let rect = CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            scrollView.zoom(to: rect, animated: true)
        }
    }
}

struct PhotoAssetVideoPlayerView: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    var autoPlay = true
    var isMuted = true
    var ignoresSafeArea = true

    @State private var player: AVPlayer?
    @State private var requestID: PHImageRequestID?
    @State private var isLoading = true
    @State private var didFail = false
    @State private var loadingAssetIdentifier: String?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(edges: ignoresSafeArea ? .all : [])

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: ignoresSafeArea ? .all : [])
                    .onAppear {
                        if autoPlay {
                            player.isMuted = isMuted
                player.play()
            }
                    }
            } else {
                VStack(spacing: 14) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
                    } else {
                        Image(systemName: "play.slash")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundColor(PhotoDeleteStyle.secondaryText)
                    }

                    Text(isLoading ? L10n.string("正在读取视频") : L10n.string("无法播放这个视频"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(PhotoDeleteStyle.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
        .accessibilityLabel(didFail ? L10n.string("无法播放这个视频") : L10n.string("视频预览"))
        .onAppear(perform: loadPlayer)
        .onChange(of: isMuted) { muted in
            player?.isMuted = muted
        }
        .onDisappear(perform: cleanup)
    }

    private func loadPlayer() {
        guard player == nil, requestID == nil else { return }

        let requestedAssetID = asset.localIdentifier
        loadingAssetIdentifier = requestedAssetID
        isLoading = true
        didFail = false

        requestID = photoLibraryManager.loadPlayerItem(for: asset) { playerItem in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            requestID = nil
            isLoading = false

            guard let playerItem else {
                didFail = true
                return
            }

            let loadedPlayer = AVPlayer(playerItem: playerItem)
            loadedPlayer.isMuted = isMuted
            player = loadedPlayer
            if autoPlay {
                loadedPlayer.play()
            }
        }
    }

    private func cleanup() {
        photoLibraryManager.cancelImageRequest(requestID)
        requestID = nil
        loadingAssetIdentifier = nil
        player?.pause()
        player = nil
    }
}

struct CandidatePhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    var locationTitle: String? = nil

    @State private var image: UIImage?
    @State private var livePhoto: PHLivePhoto?
    @State private var isLoading = true
    @State private var requestID: PHImageRequestID?
    @State private var failedToLoadLivePhoto = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        previewMedia(in: geometry.size)
                            .frame(height: previewMediaHeight(in: geometry.size))

                        PhotoAssetDetailsPanel(
                            asset: asset,
                            photoLibraryManager: photoLibraryManager,
                            locationTitle: locationTitle
                        )
                        .padding(.horizontal, PhotoDeleteStyle.screenHorizontalPadding)
                        .padding(.top, 18)
                        .padding(.bottom, 32)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .background(PhotoDeleteStyle.background.ignoresSafeArea())
                .onAppear {
                    if isLivePhotoAsset {
                        loadLivePhoto(in: geometry.size)
                    } else if asset.mediaType != .video {
                        loadImage(in: geometry.size)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("关闭")) {
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            photoLibraryManager.cancelImageRequest(requestID)
        }
    }

    @ViewBuilder
    private func previewMedia(in size: CGSize) -> some View {
        ZStack {
            PhotoDeleteStyle.background

            if asset.mediaType == .video {
                PhotoAssetVideoPlayerView(
                    asset: asset,
                    photoLibraryManager: photoLibraryManager,
                    ignoresSafeArea: false
                )
            } else if isLivePhotoAsset {
                if let livePhoto {
                    LivePhotoPreviewRepresentable(livePhoto: livePhoto)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(L10n.string("实况照片"))
                } else {
                    loadingContent
                }
            } else if let image {
                ZoomablePhotoPreview(image: image)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(L10n.string("放大的照片"))
            } else {
                loadingContent
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(asset.mediaType == .video ? 1 : 0.08))
    }

    private func previewMediaHeight(in size: CGSize) -> CGFloat {
        min(max(size.height * 0.58, 320), size.height * 0.68)
    }

    private var isLivePhotoAsset: Bool {
        photoLibraryManager.isLivePhoto(asset)
    }

    private var navigationTitle: String {
        if asset.mediaType == .video {
            return L10n.string("视频预览")
        }
        if isLivePhotoAsset {
            return L10n.string("实况照片")
        }
        return L10n.string("照片预览")
    }

    private var loadingContent: some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: PhotoDeleteStyle.accent))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.secondaryText)
            }

            Text(isLoading ? L10n.string("正在读取照片") : L10n.string("无法读取这张照片"))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(PhotoDeleteStyle.secondaryText)
        }
    }

    private func loadLivePhoto(in size: CGSize) {
        guard requestID == nil, livePhoto == nil, !failedToLoadLivePhoto else { return }
        isLoading = true
        let targetSize = photoPreviewTargetSize(for: asset, viewport: size, displayScale: displayScale)

        requestID = photoLibraryManager.loadLivePhotoResult(for: asset, size: targetSize) { result in
            if let loadedLivePhoto = result.livePhoto {
                livePhoto = loadedLivePhoto
                isLoading = false
            } else if result.isFinal {
                failedToLoadLivePhoto = true
                isLoading = false
            }

            if result.isFinal {
                requestID = nil
            }
        }
    }

    private func loadImage(in size: CGSize) {
        guard requestID == nil, image == nil else { return }
        isLoading = true
        let targetSize = photoPreviewTargetSize(for: asset, viewport: size, displayScale: displayScale)

        requestID = photoLibraryManager.loadHighQualityPreview(
            for: asset,
            size: targetSize,
            networkAccessAllowed: true
        ) { loadedImage in
            image = loadedImage
            isLoading = false
            requestID = nil
        }
    }
}

private struct PhotoAssetDetailsPanel: View {
    let asset: PHAsset
    let photoLibraryManager: PhotoLibraryManager
    var locationTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.accent)

                Text(L10n.string("照片信息"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
            }

            VStack(spacing: 0) {
                detailRow(label: L10n.string("拍摄时间"), value: captureDateText, icon: "calendar")
                Divider().background(PhotoDeleteStyle.hairline).padding(.leading, 44)
                detailRow(label: L10n.string("地点"), value: locationText, icon: "location")
                Divider().background(PhotoDeleteStyle.hairline).padding(.leading, 44)
                detailRow(label: L10n.string("类型"), value: mediaTypeText, icon: mediaTypeIcon)
                Divider().background(PhotoDeleteStyle.hairline).padding(.leading, 44)
                detailRow(label: L10n.string("尺寸"), value: pixelSizeText, icon: "aspectratio")

                if asset.mediaType == .video {
                    Divider().background(PhotoDeleteStyle.hairline).padding(.leading, 44)
                    detailRow(label: L10n.string("时长"), value: durationText, icon: "clock")
                }

                if asset.isFavorite {
                    Divider().background(PhotoDeleteStyle.hairline).padding(.leading, 44)
                    detailRow(label: L10n.string("状态"), value: L10n.string("已收藏"), icon: "heart.fill")
                }
            }
            .photoDeleteCard()
        }
        .accessibilityElement(children: .contain)
    }

    private func detailRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            PhotoDeleteIconTile(icon: icon, tint: PhotoDeleteStyle.accent, size: 32, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PhotoDeleteStyle.tertiaryText)

                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PhotoDeleteStyle.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureDateText: String {
        PhotoAssetMetadataFormatter.detailCaptureDate(for: asset.creationDate)
    }

    private var locationText: String {
        PhotoAssetMetadataFormatter.locationText(
            locationTitle: locationTitle,
            coordinate: asset.location?.coordinate
        )
    }

    private var mediaTypeText: String {
        if asset.mediaType == .video {
            return L10n.string("视频")
        }
        if photoLibraryManager.isLivePhoto(asset) {
            return L10n.string("实况照片")
        }
        if photoLibraryManager.isScreenshot(asset) {
            return L10n.string("截图")
        }
        return L10n.string("照片")
    }

    private var mediaTypeIcon: String {
        if asset.mediaType == .video { return "video" }
        if photoLibraryManager.isLivePhoto(asset) { return "livephoto" }
        if photoLibraryManager.isScreenshot(asset) { return "camera.viewfinder" }
        return "photo"
    }

    private var pixelSizeText: String {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else {
            return L10n.string("未知")
        }
        return "\(asset.pixelWidth) × \(asset.pixelHeight)"
    }

    private var durationText: String {
        let totalSeconds = max(Int(asset.duration.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct LivePhotoPreviewRepresentable: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    var autoPlay = true
    var isMuted = true
    var playbackStyle: PHLivePhotoViewPlaybackStyle = .full
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeCoordinator() -> Coordinator {
        Coordinator(autoPlay: autoPlay, playbackStyle: playbackStyle)
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = contentMode
        view.isMuted = isMuted
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        context.coordinator.autoPlay = autoPlay
        context.coordinator.playbackStyle = playbackStyle
        context.coordinator.isDismantled = false
        uiView.contentMode = contentMode
        uiView.isMuted = isMuted

        if context.coordinator.displayedLivePhoto !== livePhoto {
            context.coordinator.displayedLivePhoto = livePhoto
            uiView.livePhoto = livePhoto
            context.coordinator.startPlayback(in: uiView, delay: 0.12)
        } else if autoPlay, !context.coordinator.isPlaying {
            context.coordinator.startPlayback(in: uiView, delay: 0.12)
        }
    }

    static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        uiView.delegate = nil
        uiView.stopPlayback()
        uiView.livePhoto = nil
        coordinator.displayedLivePhoto = nil
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        weak var displayedLivePhoto: PHLivePhoto?
        var autoPlay: Bool
        var playbackStyle: PHLivePhotoViewPlaybackStyle
        var isPlaying = false
        var isDismantled = false

        init(autoPlay: Bool, playbackStyle: PHLivePhotoViewPlaybackStyle) {
            self.autoPlay = autoPlay
            self.playbackStyle = playbackStyle
        }

        func startPlayback(in view: PHLivePhotoView, delay: TimeInterval) {
            guard autoPlay else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak view] in
                guard let self,
                      let view,
                      self.autoPlay,
                      !self.isDismantled,
                      view.livePhoto != nil else { return }
                view.stopPlayback()
                view.startPlayback(with: self.playbackStyle)
                self.isPlaying = true
            }
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            isPlaying = true
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            isPlaying = false
            startPlayback(in: livePhotoView, delay: 0.75)
        }
    }
}
