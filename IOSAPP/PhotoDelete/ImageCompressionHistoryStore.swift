//
//  ImageCompressionHistoryStore.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/25/26.
//

import Foundation
import OSLog

private let imageCompressionHistoryLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "PhotoDelete",
    category: "ImageCompressionHistory"
)

struct ImageCompressionSessionItem: Codable, Identifiable, Equatable {
    let originalAssetIdentifier: String
    let createdAssetIdentifier: String?
    let originalSizeMB: Double
    let compressedSizeMB: Double
    let originalDeletedAt: Date?

    init(
        originalAssetIdentifier: String,
        createdAssetIdentifier: String?,
        originalSizeMB: Double,
        compressedSizeMB: Double,
        originalDeletedAt: Date? = nil
    ) {
        self.originalAssetIdentifier = originalAssetIdentifier
        self.createdAssetIdentifier = createdAssetIdentifier
        self.originalSizeMB = max(originalSizeMB, 0)
        self.compressedSizeMB = max(compressedSizeMB, 0)
        self.originalDeletedAt = originalDeletedAt
    }

    var id: String {
        "\(originalAssetIdentifier)-\(createdAssetIdentifier ?? "missing")"
    }

    var isOriginalDeleted: Bool {
        originalDeletedAt != nil
    }

    var savedSizeMB: Double {
        max(originalSizeMB - compressedSizeMB, 0)
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

    func markingOriginalDeleted(at date: Date) -> ImageCompressionSessionItem {
        ImageCompressionSessionItem(
            originalAssetIdentifier: originalAssetIdentifier,
            createdAssetIdentifier: createdAssetIdentifier,
            originalSizeMB: originalSizeMB,
            compressedSizeMB: compressedSizeMB,
            originalDeletedAt: originalDeletedAt ?? date
        )
    }
}

struct ImageCompressionSession: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let imageCount: Int
    let failedCount: Int
    let originalSizeMB: Double
    let compressedSizeMB: Double
    let items: [ImageCompressionSessionItem]

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case imageCount
        case failedCount
        case originalSizeMB
        case compressedSizeMB
        case items
    }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        imageCount: Int,
        failedCount: Int,
        originalSizeMB: Double,
        compressedSizeMB: Double,
        items: [ImageCompressionSessionItem] = []
    ) {
        self.id = id
        self.date = date
        self.imageCount = max(imageCount, 0)
        self.failedCount = max(failedCount, 0)
        self.originalSizeMB = max(originalSizeMB, 0)
        self.compressedSizeMB = max(compressedSizeMB, 0)
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        imageCount = max(try container.decode(Int.self, forKey: .imageCount), 0)
        failedCount = max(try container.decode(Int.self, forKey: .failedCount), 0)
        originalSizeMB = max(try container.decode(Double.self, forKey: .originalSizeMB), 0)
        compressedSizeMB = max(try container.decode(Double.self, forKey: .compressedSizeMB), 0)
        items = try container.decodeIfPresent([ImageCompressionSessionItem].self, forKey: .items) ?? []
    }

    var savedSizeMB: Double {
        max(originalSizeMB - compressedSizeMB, 0)
    }

    var formattedDate: String {
        CleanupStatsFormatter.sessionDate.string(from: date)
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
}

struct ImageCompressionHistorySummary: Equatable {
    let sessions: Int
    let imageCount: Int
    let failedCount: Int
    let originalSizeMB: Double
    let compressedSizeMB: Double

    static let empty = ImageCompressionHistorySummary(
        sessions: 0,
        imageCount: 0,
        failedCount: 0,
        originalSizeMB: 0,
        compressedSizeMB: 0
    )

    var savedSizeMB: Double {
        max(originalSizeMB - compressedSizeMB, 0)
    }

    var formattedSavedSize: String {
        CleanupStatsFormatter.space(savedSizeMB)
    }
}

final class ImageCompressionHistoryStore: ObservableObject {
    @Published private(set) var sessions: [ImageCompressionSession] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    var summary: ImageCompressionHistorySummary {
        sessions.reduce(.empty) { partial, session in
            ImageCompressionHistorySummary(
                sessions: partial.sessions + 1,
                imageCount: partial.imageCount + session.imageCount,
                failedCount: partial.failedCount + session.failedCount,
                originalSizeMB: partial.originalSizeMB + session.originalSizeMB,
                compressedSizeMB: partial.compressedSizeMB + session.compressedSizeMB
            )
        }
    }

    @discardableResult
    func recordSession(
        imageCount: Int,
        failedCount: Int,
        originalSizeMB: Double,
        compressedSizeMB: Double,
        date: Date = Date(),
        items: [ImageCompressionSessionItem] = []
    ) -> ImageCompressionSession? {
        guard imageCount > 0 else { return nil }

        let session = ImageCompressionSession(
            date: date,
            imageCount: imageCount,
            failedCount: failedCount,
            originalSizeMB: originalSizeMB,
            compressedSizeMB: compressedSizeMB,
            items: items
        )
        sessions.insert(session, at: 0)
        save()
        return session
    }

    func clearAll() {
        sessions.removeAll()
        save()
    }

    @discardableResult
    func markOriginalsDeleted(assetIdentifiers: Set<String>, date: Date = Date()) -> Bool {
        guard !assetIdentifiers.isEmpty else { return false }

        var changed = false
        sessions = sessions.map { session in
            var sessionChanged = false
            let updatedItems = session.items.map { item in
                guard assetIdentifiers.contains(item.originalAssetIdentifier),
                      !item.isOriginalDeleted else {
                    return item
                }
                sessionChanged = true
                changed = true
                return item.markingOriginalDeleted(at: date)
            }

            guard sessionChanged else { return session }
            return ImageCompressionSession(
                id: session.id,
                date: session.date,
                imageCount: session.imageCount,
                failedCount: session.failedCount,
                originalSizeMB: session.originalSizeMB,
                compressedSizeMB: session.compressedSizeMB,
                items: updatedItems
            )
        }

        if changed {
            save()
        }
        return changed
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            sessions = try decoder.decode([ImageCompressionSession].self, from: data)
                .sorted { $0.date > $1.date }
        } catch {
            sessions = []
            backupCorruptStoreFile(loadError: error)
        }
    }

    private func backupCorruptStoreFile(loadError: Error) {
        let backupURL = CleanupStatsStore.corruptBackupURL(for: fileURL)

        do {
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            imageCompressionHistoryLogger.error("Failed to load image compression history. Moved corrupt file to \(backupURL.lastPathComponent, privacy: .public): \(loadError.localizedDescription, privacy: .public)")
        } catch {
            imageCompressionHistoryLogger.error("Failed to back up corrupt image compression history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(sessions)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            imageCompressionHistoryLogger.error("Failed to save image compression history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("PhotoDelete", isDirectory: true)
            .appendingPathComponent("image-compression-history.json")
    }
}
