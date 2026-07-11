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
    @State private var completedDeletedIDs: Set<String> = []
    let albumInfo: AlbumInfo?
    let onComplete: ((Set<String>) -> Void)?

    init(albumInfo: AlbumInfo? = nil, onComplete: ((Set<String>) -> Void)? = nil) {
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
                    completedDeletedIDs = Set(deletedAssets.map(\.localIdentifier))
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
        onComplete?(completedDeletedIDs)
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
    let requestedLongEdge = min(max(viewportLongEdge * 2, 1_600), min(assetLongEdge, 3_200))
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
    var allowsPlayerInteraction = false
    var allowsSurfaceTapToRevealControls = true
    var playbackControlsRevealToken: UUID?
    var onScrubbingChanged: (Bool) -> Void = { _ in }

    @State private var player: AVPlayer?
    @State private var requestID: PHImageRequestID?
    @State private var isLoading = true
    @State private var didFail = false
    @State private var loadingAssetIdentifier: String?
    @State private var playbackProgress: Double = 0
    @State private var timeObserverToken: Any?
    @State private var isScrubbingPlayback = false
    @State private var wasPlayingBeforeScrub = false
    @State private var isPlaying = false
    @State private var playbackEndObserver: NSObjectProtocol?
    @State private var showsPlaybackControls = false
    @State private var playbackControlsHideWorkItem: DispatchWorkItem?
    @State private var scrubResumeWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(edges: ignoresSafeArea ? .all : [])

            if let player {
                ZStack {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: ignoresSafeArea ? .all : [])
                        .allowsHitTesting(allowsPlayerInteraction)

                    if allowsSurfaceTapToRevealControls {
                        VStack(spacing: 0) {
                            VideoPlaybackTapRevealArea {
                                revealPlaybackControls()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Color.clear
                                .frame(height: VideoPlaybackControlLayout.progressHitHeight)
                                .allowsHitTesting(false)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if shouldShowPlaybackButton && !isScrubbingPlayback {
                        VideoPlaybackPlayPauseButton(isPlaying: isPlaying) {
                            togglePlayback(for: player)
                        }
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.16), value: isScrubbingPlayback)
                    }
                }
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    VideoPlaybackProgressBar(
                        progress: playbackProgress,
                        onScrub: seekToProgress,
                        onScrubbingChanged: handlePlaybackScrubbingChanged
                    )
                    .zIndex(2)
                    .allowsHitTesting(true)
                }
                .onAppear {
                    if autoPlay {
                        startPlayback(for: player)
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
        .onAppear(perform: loadPlayer)
        .onChange(of: isMuted) { muted in
            player?.isMuted = muted
        }
        .onChange(of: playbackControlsRevealToken) { token in
            guard token != nil else { return }
            revealPlaybackControls()
        }
        .onDisappear(perform: cleanup)
    }

    private func loadPlayer() {
        guard player == nil, requestID == nil else { return }

        let requestedAssetID = asset.localIdentifier
        loadingAssetIdentifier = requestedAssetID
        isLoading = true
        didFail = false
        playbackProgress = 0
        showsPlaybackControls = false
        cancelPlaybackControlsAutoHide()

        requestID = photoLibraryManager.loadPlayerItem(for: asset) { playerItem in
            guard loadingAssetIdentifier == requestedAssetID else { return }
            requestID = nil
            isLoading = false

            guard let playerItem else {
                didFail = true
                playbackProgress = 0
                return
            }

            let loadedPlayer = AVPlayer(playerItem: playerItem)
            loadedPlayer.isMuted = isMuted
            player = loadedPlayer
            installPlaybackProgressObserver(for: loadedPlayer)
            installPlaybackEndObserver(for: playerItem)
            if autoPlay {
                startPlayback(for: loadedPlayer)
            }
        }
    }

    private func startPlayback(for player: AVPlayer) {
        player.isMuted = isMuted
        player.play()
        isPlaying = true
        schedulePlaybackControlsAutoHideIfNeeded()
    }

    private func pausePlayback(for player: AVPlayer) {
        player.pause()
        isPlaying = false
        setPlaybackControlsVisible(true, autoHide: false)
    }

    private func togglePlayback(for player: AVPlayer) {
        if isPlaying || player.timeControlStatus == .playing {
            pausePlayback(for: player)
            return
        }

        if playbackProgress >= 0.995 {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            playbackProgress = 0
        }
        startPlayback(for: player)
    }

    private var shouldShowPlaybackButton: Bool {
        VideoPlaybackControlVisibility.shouldShowButton(
            isPlaying: isPlaying,
            controlsVisible: showsPlaybackControls,
            playbackProgress: playbackProgress
        )
    }

    private func revealPlaybackControls() {
        setPlaybackControlsVisible(true, autoHide: isPlaying)
    }

    private func setPlaybackControlsVisible(_ isVisible: Bool, autoHide: Bool) {
        withAnimation(.easeInOut(duration: 0.16)) {
            showsPlaybackControls = isVisible
        }

        if autoHide {
            schedulePlaybackControlsAutoHideIfNeeded()
        } else {
            cancelPlaybackControlsAutoHide()
        }
    }

    private func schedulePlaybackControlsAutoHideIfNeeded(after delay: TimeInterval = 2.0) {
        cancelPlaybackControlsAutoHide()
        guard VideoPlaybackControlVisibility.shouldAutoHideControls(
            isPlaying: isPlaying,
            controlsVisible: showsPlaybackControls
        ) else {
            return
        }

        let workItem = DispatchWorkItem {
            guard isPlaying else { return }
            guard !isScrubbingPlayback else {
                schedulePlaybackControlsAutoHideIfNeeded(after: VideoPlaybackScrubTiming.controlHideRetryDelay)
                return
            }
            withAnimation(.easeInOut(duration: 0.16)) {
                showsPlaybackControls = false
            }
        }
        playbackControlsHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPlaybackControlsAutoHide() {
        playbackControlsHideWorkItem?.cancel()
        playbackControlsHideWorkItem = nil
    }

    private func installPlaybackProgressObserver(for loadedPlayer: AVPlayer) {
        removePlaybackProgressObserver()
        playbackProgress = 0
        timeObserverToken = loadedPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak loadedPlayer] time in
            guard let currentPlayer = loadedPlayer else { return }
            guard !isScrubbingPlayback else { return }
            guard let duration = VideoPlaybackDurationResolver.playableDuration(
                playerItemDuration: currentPlayer.currentItem?.duration.seconds,
                assetDuration: asset.duration
            ),
                  time.seconds.isFinite else {
                playbackProgress = 0
                return
            }
            playbackProgress = min(max(time.seconds / duration, 0), 1)
        }
    }

    private func removePlaybackProgressObserver() {
        guard let timeObserverToken else { return }
        player?.removeTimeObserver(timeObserverToken)
        self.timeObserverToken = nil
    }

    private func installPlaybackEndObserver(for playerItem: AVPlayerItem) {
        removePlaybackEndObserver()
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            playbackProgress = 1
            isPlaying = false
            setPlaybackControlsVisible(true, autoHide: false)
        }
    }

    private func removePlaybackEndObserver() {
        guard let playbackEndObserver else { return }
        NotificationCenter.default.removeObserver(playbackEndObserver)
        self.playbackEndObserver = nil
    }

    private func handlePlaybackScrubbingChanged(_ isScrubbing: Bool) {
        guard isScrubbingPlayback != isScrubbing else { return }
        isScrubbingPlayback = isScrubbing
        onScrubbingChanged(isScrubbing)

        if isScrubbing {
            cancelScrubResume()
            setPlaybackControlsVisible(true, autoHide: false)
            wasPlayingBeforeScrub = VideoPlaybackScrubResumePolicy.shouldResumeAfterScrub(
                wasPlayingState: isPlaying,
                playerWasPlaying: player?.timeControlStatus == .playing,
                autoPlayEnabled: autoPlay,
                playbackProgress: playbackProgress
            )
            player?.pause()
            isPlaying = false
        } else if VideoPlaybackScrubResumePolicy.shouldResumeAfterScrub(
            wasPlayingState: wasPlayingBeforeScrub,
            playerWasPlaying: player?.timeControlStatus == .playing,
            autoPlayEnabled: autoPlay,
            playbackProgress: playbackProgress
        ) {
            if let player {
                cancelScrubResume()
                startPlayback(for: player)
                schedulePlaybackControlsAutoHideIfNeeded(after: VideoPlaybackScrubTiming.controlHideAfterResumeDelay)
            }
            wasPlayingBeforeScrub = false
        } else {
            isPlaying = player?.timeControlStatus == .playing
            setPlaybackControlsVisible(true, autoHide: isPlaying)
        }
    }

    private func seekToProgress(_ progress: Double) {
        guard let player,
              let duration = VideoPlaybackDurationResolver.playableDuration(
                playerItemDuration: player.currentItem?.duration.seconds,
                assetDuration: asset.duration
              ) else {
            return
        }

        let clampedProgress = VideoPlaybackProgressMapper.clamped(progress)
        playbackProgress = clampedProgress
        player.seek(
            to: CMTime(seconds: duration * clampedProgress, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        schedulePlaybackResumeAfterScrubSeek()
    }

    private func schedulePlaybackResumeAfterScrubSeek() {
        guard autoPlay, playbackProgress < 0.995 else { return }
        scrubResumeWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard autoPlay,
                  playbackProgress < 0.995,
                  let player else {
                return
            }
            if isScrubbingPlayback {
                isScrubbingPlayback = false
                onScrubbingChanged(false)
            }
            wasPlayingBeforeScrub = false
            startPlayback(for: player)
            schedulePlaybackControlsAutoHideIfNeeded(after: VideoPlaybackScrubTiming.controlHideAfterResumeDelay)
            scrubResumeWorkItem = nil
        }
        scrubResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + VideoPlaybackScrubTiming.resumeAfterLastScrubDelay,
            execute: workItem
        )
    }

    private func cancelScrubResume() {
        scrubResumeWorkItem?.cancel()
        scrubResumeWorkItem = nil
    }

    private func cleanup() {
        photoLibraryManager.cancelImageRequest(requestID)
        requestID = nil
        loadingAssetIdentifier = nil
        removePlaybackProgressObserver()
        removePlaybackEndObserver()
        cancelPlaybackControlsAutoHide()
        cancelScrubResume()
        player?.pause()
        player = nil
        playbackProgress = 0
        isPlaying = false
        showsPlaybackControls = false
        if isScrubbingPlayback {
            onScrubbingChanged(false)
        }
        isScrubbingPlayback = false
        wasPlayingBeforeScrub = false
    }
}

enum VideoPlaybackProgressMapper {
    static func clamped(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    static func progress(locationX: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return clamped(Double(locationX / width))
    }
}

enum VideoPlaybackDurationResolver {
    static func playableDuration(playerItemDuration: Double?, assetDuration: TimeInterval) -> Double? {
        if let playerItemDuration,
           playerItemDuration.isFinite,
           playerItemDuration > 0 {
            return playerItemDuration
        }

        guard assetDuration.isFinite, assetDuration > 0 else { return nil }
        return assetDuration
    }
}

enum VideoPlaybackControlLayout {
    static let progressHitHeight: CGFloat = 54
    static let progressHorizontalPadding: CGFloat = 14

    static func isInProgressHitRegion(point: CGPoint, containerSize: CGSize) -> Bool {
        guard containerSize.width > 0,
              containerSize.height > 0,
              progressHitHeight > 0 else {
            return false
        }

        let progressTop = max(containerSize.height - progressHitHeight, 0)
        return point.x >= 0 &&
            point.x <= containerSize.width &&
            point.y >= progressTop &&
            point.y <= containerSize.height
    }
}

enum VideoPlaybackScrubResumePolicy {
    static func shouldResumeAfterScrub(
        wasPlayingState: Bool,
        playerWasPlaying: Bool,
        autoPlayEnabled: Bool = false,
        playbackProgress: Double = 0
    ) -> Bool {
        wasPlayingState || playerWasPlaying || (autoPlayEnabled && playbackProgress < 0.995)
    }
}

enum VideoPlaybackScrubTiming {
    static let endFallbackDelay: TimeInterval = 0.18
    static let resumeAfterLastScrubDelay: TimeInterval = 0.24
    static let controlHideRetryDelay: TimeInterval = 0.25
    static let controlHideAfterResumeDelay: TimeInterval = 0.45
}

enum VideoPlaybackControlVisibility {
    static func shouldShowButton(isPlaying: Bool, controlsVisible: Bool, playbackProgress: Double) -> Bool {
        controlsVisible || !isPlaying || playbackProgress >= 0.995
    }

    static func shouldAutoHideControls(isPlaying: Bool, controlsVisible: Bool) -> Bool {
        isPlaying && controlsVisible
    }
}

private struct VideoPlaybackPlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                L10n.string(isPlaying ? "暂停视频" : "播放视频"),
                systemImage: isPlaying ? "pause.fill" : "play.fill"
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 50, height: 50)
            .background(Circle().fill(Color.black.opacity(0.62)))
            .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .photoDeleteMinimumTapTarget()
        .accessibilityIdentifier("video-playback-toggle-button")
        .accessibilityLabel(L10n.string(isPlaying ? "暂停视频" : "播放视频"))
    }
}

private struct VideoPlaybackTapRevealArea: View {
    let action: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { action() }, including: .gesture)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("photo-asset-video-player")
            .accessibilityLabel(L10n.string("视频预览"))
            .accessibilityAddTraits(.isButton)
    }
}

private struct VideoPlaybackProgressBar: View {
    let progress: Double
    let onScrub: (Double) -> Void
    let onScrubbingChanged: (Bool) -> Void

    @State private var scrubbingProgress: Double?

    private var displayedProgress: Double {
        VideoPlaybackProgressMapper.clamped(scrubbingProgress ?? progress)
    }

    var body: some View {
        VideoPlaybackSlider(
            progress: displayedProgress,
            onScrub: updateScrubProgress,
            onScrubbingChanged: handleSliderEditingChanged
        )
        .frame(height: VideoPlaybackControlLayout.progressHitHeight)
        .padding(.horizontal, VideoPlaybackControlLayout.progressHorizontalPadding)
        .background(
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.46)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("视频预览"))
        .accessibilityValue(L10n.percent(Int(displayedProgress * 100)))
        .accessibilityIdentifier("video-playback-progress-bar")
    }

    private func updateScrubProgress(_ progress: Double) {
        let clampedProgress = VideoPlaybackProgressMapper.clamped(progress)
        if scrubbingProgress == nil {
            onScrubbingChanged(true)
        }
        scrubbingProgress = clampedProgress
        onScrub(clampedProgress)
    }

    private func handleSliderEditingChanged(_ isEditing: Bool) {
        if isEditing {
            if scrubbingProgress == nil {
                onScrubbingChanged(true)
            }
            return
        }

        if let scrubbingProgress {
            onScrub(scrubbingProgress)
        }
        scrubbingProgress = nil
        onScrubbingChanged(false)
    }
}

#if canImport(UIKit)
private struct VideoPlaybackSlider: UIViewRepresentable {
    let progress: Double
    let onScrub: (Double) -> Void
    let onScrubbingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> UISlider {
        let slider = ScrubbableSlider(frame: .zero)
        slider.accessibilityIdentifier = "video-playback-slider"
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.isContinuous = true
        slider.minimumTrackTintColor = UIColor(PhotoDeleteStyle.accent)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.28)
        slider.setThumbImage(Self.thumbImage(diameter: 20), for: .normal)
        slider.setThumbImage(Self.thumbImage(diameter: 24), for: .highlighted)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchDown(_:)), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchEnded(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )

        slider.value = Float(VideoPlaybackProgressMapper.clamped(progress))
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        slider.minimumTrackTintColor = UIColor(PhotoDeleteStyle.accent)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.28)

        guard !slider.isTracking else { return }
        slider.value = Float(VideoPlaybackProgressMapper.clamped(progress))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleUIView(_ slider: UISlider, coordinator: Coordinator) {
        coordinator.forceEndScrubbing()
    }

    private static func thumbImage(diameter: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 4,
                color: UIColor.black.withAlphaComponent(0.28).cgColor
            )
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: rect.insetBy(dx: 2, dy: 2))
        }
    }

    private final class ScrubbableSlider: UISlider {
        private let minimumTouchHeight: CGFloat = 54

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            let verticalInset = max(0, (minimumTouchHeight - bounds.height) / 2)
            return bounds.insetBy(dx: 0, dy: -verticalInset).contains(point)
        }

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            updateValue(for: touch)
            sendActions(for: .touchDown)
            sendActions(for: .valueChanged)
            return true
        }

        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            updateValue(for: touch)
            sendActions(for: .valueChanged)
            return true
        }

        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            if let touch {
                updateValue(for: touch)
                sendActions(for: .valueChanged)
            }
            sendActions(for: .touchUpInside)
            super.endTracking(touch, with: event)
        }

        override func cancelTracking(with event: UIEvent?) {
            sendActions(for: .touchCancel)
            super.cancelTracking(with: event)
        }

        private func updateValue(for touch: UITouch) {
            let progress = VideoPlaybackProgressMapper.progress(
                locationX: touch.location(in: self).x,
                width: bounds.width
            )
            value = Float(progress)
        }
    }

    final class Coordinator: NSObject {
        var parent: VideoPlaybackSlider
        private var isScrubbing = false
        private var scrubEndFallbackWorkItem: DispatchWorkItem?

        init(parent: VideoPlaybackSlider) {
            self.parent = parent
        }

        @objc func touchDown(_ slider: UISlider) {
            beginScrubbing()
            parent.onScrub(Double(slider.value))
        }

        @objc func valueChanged(_ slider: UISlider) {
            beginScrubbing()
            scheduleScrubEndFallback()
            parent.onScrub(Double(slider.value))
        }

        @objc func touchEnded(_ slider: UISlider) {
            parent.onScrub(Double(slider.value))
            endScrubbing()
        }

        private func beginScrubbing() {
            guard !isScrubbing else { return }
            isScrubbing = true
            parent.onScrubbingChanged(true)
        }

        private func endScrubbing() {
            scrubEndFallbackWorkItem?.cancel()
            scrubEndFallbackWorkItem = nil
            guard isScrubbing else { return }
            isScrubbing = false
            parent.onScrubbingChanged(false)
        }

        func forceEndScrubbing() {
            endScrubbing()
        }

        private func scheduleScrubEndFallback() {
            scrubEndFallbackWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.endScrubbing()
            }
            scrubEndFallbackWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + VideoPlaybackScrubTiming.endFallbackDelay, execute: workItem)
        }
    }
}
#endif

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
    @State private var sharePayload: PhotoSharePayload?
    @State private var sharePreparationTask: Task<Void, Never>?
    @State private var isPreparingShare = false
    @State private var showShareError = false

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
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: prepareShare) {
                        Group {
                            if isPreparingShare {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .disabled(isPreparingShare)
                    .accessibilityLabel(L10n.string("分享"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("关闭")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $sharePayload, onDismiss: cleanupSharePayload) { payload in
            SystemShareSheet(activityItems: [payload.fileURL])
        }
        .alert(L10n.string("操作失败，请稍后重试。"), isPresented: $showShareError) {
            Button(L10n.string("知道了"), role: .cancel) {}
        }
        .onDisappear {
            photoLibraryManager.cancelImageRequest(requestID)
            sharePreparationTask?.cancel()
            sharePreparationTask = nil
            isPreparingShare = false
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
                    LivePhotoPreviewRepresentable(
                        livePhoto: livePhoto,
                        contentIdentifier: asset.localIdentifier
                    )
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
        min(max(size.height * 0.82, 420), size.height * 0.88)
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

    private func prepareShare() {
        guard !isPreparingShare else { return }

        isPreparingShare = true
        sharePreparationTask?.cancel()
        sharePreparationTask = Task {
            do {
                let payload = try await photoLibraryManager.prepareSharePayload(for: asset)
                guard !Task.isCancelled else {
                    payload.cleanup()
                    return
                }
                await MainActor.run {
                    sharePayload = payload
                    isPreparingShare = false
                    sharePreparationTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    isPreparingShare = false
                    sharePreparationTask = nil
                }
            } catch {
                await MainActor.run {
                    isPreparingShare = false
                    sharePreparationTask = nil
                    showShareError = true
                }
            }
        }
    }

    private func cleanupSharePayload() {
        sharePayload?.cleanup()
        sharePayload = nil
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
                if let locationText {
                    detailDivider
                    detailRow(label: L10n.string("地点"), value: locationText, icon: "location")
                }
                if let modificationDateText {
                    detailDivider
                    detailRow(label: L10n.string("修改时间"), value: modificationDateText, icon: "clock.arrow.circlepath")
                }
                Divider().background(PhotoDeleteStyle.hairline).padding(.leading, 44)
                detailRow(label: L10n.string("类型"), value: mediaTypeText, icon: mediaTypeIcon)
                Divider().background(PhotoDeleteStyle.hairline).padding(.leading, 44)
                detailRow(label: L10n.string("尺寸"), value: pixelSizeText, icon: "aspectratio")
                Divider().background(PhotoDeleteStyle.hairline).padding(.leading, 44)
                detailRow(label: L10n.string("方向"), value: orientationText, icon: "rectangle")

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

    private var detailDivider: some View {
        Divider().background(PhotoDeleteStyle.hairline).padding(.leading, 44)
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

    private var locationText: String? {
        PhotoAssetMetadataFormatter.optionalLocationText(
            locationTitle: locationTitle,
            coordinate: asset.location?.coordinate
        )
    }

    private var modificationDateText: String? {
        guard let modificationDate = asset.modificationDate else { return nil }
        return AppDateFormatter.string(from: modificationDate, dateStyle: .medium, timeStyle: .short)
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

    private var orientationText: String {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else {
            return L10n.string("未知")
        }
        if asset.pixelWidth > asset.pixelHeight {
            return L10n.string("横向")
        }
        if asset.pixelHeight > asset.pixelWidth {
            return L10n.string("竖向")
        }
        return L10n.string("方形")
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
    let contentIdentifier: String
    var autoPlay = true
    var isMuted = true
    var playbackStyle: PHLivePhotoViewPlaybackStyle = .full
    var playbackTrigger = 0
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = contentMode
        view.isMuted = isMuted
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        let shouldStartPlayback = context.coordinator.playbackRequestState.shouldStartPlayback(
            contentIdentifier: contentIdentifier,
            autoPlay: autoPlay,
            playbackTrigger: playbackTrigger
        )
        context.coordinator.autoPlay = autoPlay
        context.coordinator.playbackStyle = playbackStyle
        context.coordinator.isDismantled = false
        uiView.contentMode = contentMode
        uiView.isMuted = isMuted

        if !autoPlay {
            context.coordinator.stopPlayback(in: uiView)
        }

        if context.coordinator.displayedLivePhoto !== livePhoto {
            context.coordinator.displayedLivePhoto = livePhoto
            uiView.livePhoto = livePhoto
        }

        if shouldStartPlayback {
            context.coordinator.startPlayback(in: uiView, delay: 0.12)
        }
    }

    static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        coordinator.cancelPendingPlayback()
        uiView.delegate = nil
        uiView.stopPlayback()
        uiView.livePhoto = nil
        coordinator.displayedLivePhoto = nil
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        weak var displayedLivePhoto: PHLivePhoto?
        var autoPlay = false
        var playbackStyle: PHLivePhotoViewPlaybackStyle = .full
        var playbackRequestState = LivePhotoPlaybackRequestState()
        var isPlaying = false
        var isDismantled = false
        private var pendingPlaybackToken: UUID?

        func startPlayback(in view: PHLivePhotoView, delay: TimeInterval) {
            guard autoPlay else { return }
            let playbackToken = UUID()
            pendingPlaybackToken = playbackToken
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak view] in
                guard let self,
                      let view,
                      self.pendingPlaybackToken == playbackToken,
                      self.autoPlay,
                      !self.isDismantled,
                      view.livePhoto != nil else { return }
                self.pendingPlaybackToken = nil
                view.stopPlayback()
                view.startPlayback(with: self.playbackStyle)
                self.isPlaying = true
            }
        }

        func cancelPendingPlayback() {
            pendingPlaybackToken = nil
        }

        func stopPlayback(in view: PHLivePhotoView) {
            cancelPendingPlayback()
            view.stopPlayback()
            isPlaying = false
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            isPlaying = true
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            isPlaying = false
        }
    }
}
