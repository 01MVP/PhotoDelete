//
//  AdvancedCompressionModels.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 7/2/26.
//

import CoreGraphics
import Foundation

struct AdvancedImageCompressionJobState: Equatable {
    var isCompressing = false
    var processedCount = 0
    var totalCount = 0
    var currentProgress: Double = 0
    var message: String?
    var errorMessage: String?
    var result: AdvancedImageCompressionResult?

    static func running(totalCount: Int) -> AdvancedImageCompressionJobState {
        AdvancedImageCompressionJobState(
            isCompressing: true,
            processedCount: 0,
            totalCount: totalCount,
            currentProgress: 0,
            message: L10n.string("正在准备压缩"),
            errorMessage: nil,
            result: nil
        )
    }
}

struct AdvancedVideoCompressionJobState: Equatable {
    var isCompressing = false
    var processedCount = 0
    var totalCount = 0
    var currentProgress: Double = 0
    var message: String?
    var errorMessage: String?
    var result: AdvancedVideoCompressionResult?

    static func running(totalCount: Int) -> AdvancedVideoCompressionJobState {
        AdvancedVideoCompressionJobState(
            isCompressing: true,
            processedCount: 0,
            totalCount: totalCount,
            currentProgress: 0,
            message: L10n.string("正在准备压缩"),
            errorMessage: nil,
            result: nil
        )
    }
}

struct AdvancedImageCompressionResultItem: Identifiable, Equatable {
    let originalAssetIdentifier: String
    let createdAssetIdentifier: String?
    let originalSizeMB: Double
    let compressedSizeMB: Double
    let originalDimensions: CGSize
    let outputDimensions: CGSize

    var id: String { originalAssetIdentifier }

    init(result: ImageCompressionResult) {
        self.originalAssetIdentifier = result.originalAssetIdentifier
        self.createdAssetIdentifier = result.createdAssetIdentifier
        self.originalSizeMB = result.originalSizeMB
        self.compressedSizeMB = result.compressedSizeMB
        self.originalDimensions = result.originalDimensions
        self.outputDimensions = result.outputDimensions
    }

    var savedSizeMB: Double {
        max(originalSizeMB - compressedSizeMB, 0)
    }

    var hasMeaningfulSavings: Bool {
        savedSizeMB >= max(0.5, originalSizeMB * 0.03)
    }
}

struct AdvancedImageCompressionResult: Equatable {
    let items: [AdvancedImageCompressionResultItem]
    let failedCount: Int
    let completedAt: Date
    let plan: ImageCompressionPlan

    var successCount: Int {
        items.count
    }

    var originalSizeMB: Double {
        items.reduce(0) { $0 + $1.originalSizeMB }
    }

    var compressedSizeMB: Double {
        items.reduce(0) { $0 + $1.compressedSizeMB }
    }

    var savedSizeMB: Double {
        max(originalSizeMB - compressedSizeMB, 0)
    }

    var hasMeaningfulSavings: Bool {
        savedSizeMB >= max(0.5, originalSizeMB * 0.03)
    }

    var formattedOriginalSize: String {
        CleanupStatsFormatter.space(originalSizeMB)
    }

    var formattedCompressedSize: String {
        CleanupStatsFormatter.space(compressedSizeMB)
    }

    var formattedSavedSize: String {
        CleanupStatsFormatter.space(savedSizeMB)
    }

    var savedRatioText: String {
        guard originalSizeMB > 0 else { return "0%" }
        return "\(max(Int((savedSizeMB / originalSizeMB * 100).rounded()), 0))%"
    }

    var createdCopiesText: String {
        String(format: L10n.string("%lld 张"), Int64(successCount))
    }

    var completionTitle: String {
        failedCount > 0 ? L10n.string("压缩部分完成") : L10n.string("压缩完成")
    }

    var completionSubtitle: String {
        if successCount == 1 {
            return L10n.string("已生成 1 张压缩后图片")
        }
        return String(format: L10n.string("已生成 %lld 张压缩后图片"), Int64(successCount))
    }

    var createdAssetIdentifiers: [String] {
        items.compactMap(\.createdAssetIdentifier)
    }

    var historyItems: [ImageCompressionSessionItem] {
        items.map { item in
            ImageCompressionSessionItem(
                originalAssetIdentifier: item.originalAssetIdentifier,
                createdAssetIdentifier: item.createdAssetIdentifier,
                originalSizeMB: item.originalSizeMB,
                compressedSizeMB: item.compressedSizeMB
            )
        }
    }

    var sizeSummaryText: String {
        guard let firstItem = items.first else { return L10n.string("保持原尺寸") }

        if items.count == 1 {
            let original = AdvancedCompressionDimensions.text(for: firstItem.originalDimensions)
            let output = AdvancedCompressionDimensions.text(for: firstItem.outputDimensions)
            if original == output {
                return String(format: L10n.string("保持 %@"), original)
            }
            return String(format: L10n.string("%@ → %@"), original, output)
        }

        let allKeptOriginalSize = items.allSatisfy { item in
            AdvancedCompressionDimensions.text(for: item.originalDimensions) == AdvancedCompressionDimensions.text(for: item.outputDimensions)
        }
        if allKeptOriginalSize {
            return L10n.string("全部保持原尺寸")
        }

        let outputDimensions = Set(items.map { AdvancedCompressionDimensions.text(for: $0.outputDimensions) })
        if outputDimensions.count == 1, let output = outputDimensions.first {
            return String(format: L10n.string("输出 %@"), output)
        }

        return L10n.string("多种尺寸")
    }
}

struct AdvancedVideoCompressionResultItem: Identifiable, Equatable {
    let originalAssetIdentifier: String
    let createdAssetIdentifier: String?
    let originalSizeMB: Double
    let compressedSizeMB: Double
    let originalDimensions: CGSize
    let outputDimensions: CGSize

    var id: String { originalAssetIdentifier }

    init(result: VideoCompressionResult) {
        self.originalAssetIdentifier = result.originalAssetIdentifier
        self.createdAssetIdentifier = result.createdAssetIdentifier
        self.originalSizeMB = result.originalSizeMB
        self.compressedSizeMB = result.compressedSizeMB
        self.originalDimensions = result.originalDimensions
        self.outputDimensions = result.outputDimensions
    }

    var savedSizeMB: Double {
        max(originalSizeMB - compressedSizeMB, 0)
    }

    var hasMeaningfulSavings: Bool {
        savedSizeMB >= max(1, originalSizeMB * 0.02)
    }
}

struct AdvancedVideoCompressionResult: Equatable {
    let items: [AdvancedVideoCompressionResultItem]
    let failedCount: Int
    let completedAt: Date
    let plan: VideoCompressionPlan

    var successCount: Int {
        items.count
    }

    var originalSizeMB: Double {
        items.reduce(0) { $0 + $1.originalSizeMB }
    }

    var compressedSizeMB: Double {
        items.reduce(0) { $0 + $1.compressedSizeMB }
    }

    var savedSizeMB: Double {
        max(originalSizeMB - compressedSizeMB, 0)
    }

    var hasMeaningfulSavings: Bool {
        savedSizeMB >= max(1, originalSizeMB * 0.02)
    }

    var formattedOriginalSize: String {
        CleanupStatsFormatter.space(originalSizeMB)
    }

    var formattedCompressedSize: String {
        CleanupStatsFormatter.space(compressedSizeMB)
    }

    var formattedSavedSize: String {
        CleanupStatsFormatter.space(savedSizeMB)
    }

    var savedRatioPercent: Int {
        guard originalSizeMB > 0 else { return 0 }
        return max(Int((savedSizeMB / originalSizeMB * 100).rounded()), 0)
    }

    var savedRatioText: String {
        "\(savedRatioPercent)%"
    }

    var createdCopiesText: String {
        String(format: L10n.string("%lld 个"), Int64(successCount))
    }

    var completionTitle: String {
        failedCount > 0 ? L10n.string("压缩部分完成") : L10n.string("压缩完成")
    }

    var completionSubtitle: String {
        if successCount == 1 {
            return L10n.string("已生成 1 个压缩后视频")
        }
        return String(format: L10n.string("已生成 %lld 个压缩后视频"), Int64(successCount))
    }

    var createdAssetIdentifiers: [String] {
        items.compactMap(\.createdAssetIdentifier)
    }

    var historyItems: [VideoCompressionSessionItem] {
        items.map { item in
            VideoCompressionSessionItem(
                originalAssetIdentifier: item.originalAssetIdentifier,
                createdAssetIdentifier: item.createdAssetIdentifier,
                originalSizeMB: item.originalSizeMB,
                compressedSizeMB: item.compressedSizeMB
            )
        }
    }

    var keptResolutionText: String {
        guard let firstItem = items.first else { return L10n.string("保持原分辨率") }
        let original = AdvancedCompressionDimensions.text(for: firstItem.originalDimensions)
        let output = AdvancedCompressionDimensions.text(for: firstItem.outputDimensions)
        if original == output {
            return String(format: L10n.string("分辨率保持 %@"), original)
        }
        return String(format: L10n.string("分辨率 %@ → %@"), original, output)
    }

    var resolutionSummaryText: String {
        guard let firstItem = items.first else { return L10n.string("保持原分辨率") }

        if items.count == 1 {
            let original = AdvancedCompressionDimensions.text(for: firstItem.originalDimensions)
            let output = AdvancedCompressionDimensions.text(for: firstItem.outputDimensions)
            if original == output {
                return String(format: L10n.string("保持 %@"), original)
            }
            return String(format: L10n.string("%@ → %@"), original, output)
        }

        let allKeptOriginalResolution = items.allSatisfy { item in
            AdvancedCompressionDimensions.text(for: item.originalDimensions) == AdvancedCompressionDimensions.text(for: item.outputDimensions)
        }
        if allKeptOriginalResolution {
            return L10n.string("全部保持原分辨率")
        }

        let outputDimensions = Set(items.map { AdvancedCompressionDimensions.text(for: $0.outputDimensions) })
        if outputDimensions.count == 1, let output = outputDimensions.first {
            return String(format: L10n.string("输出 %@"), output)
        }

        return L10n.string("多种分辨率")
    }
}

private enum AdvancedCompressionDimensions {
    static func text(for size: CGSize) -> String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return L10n.string("未知") }
        return "\(width)×\(height)"
    }
}
