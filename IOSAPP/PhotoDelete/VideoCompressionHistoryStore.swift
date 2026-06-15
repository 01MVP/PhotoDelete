//
//  VideoCompressionHistoryStore.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/15/26.
//

import Foundation
import OSLog

private let videoCompressionHistoryLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "PhotoDelete",
    category: "VideoCompressionHistory"
)

struct VideoCompressionSession: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let videoCount: Int
    let failedCount: Int
    let originalSizeMB: Double
    let compressedSizeMB: Double

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        videoCount: Int,
        failedCount: Int,
        originalSizeMB: Double,
        compressedSizeMB: Double
    ) {
        self.id = id
        self.date = date
        self.videoCount = max(videoCount, 0)
        self.failedCount = max(failedCount, 0)
        self.originalSizeMB = max(originalSizeMB, 0)
        self.compressedSizeMB = max(compressedSizeMB, 0)
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

struct VideoCompressionHistorySummary: Equatable {
    let sessions: Int
    let videoCount: Int
    let failedCount: Int
    let originalSizeMB: Double
    let compressedSizeMB: Double

    static let empty = VideoCompressionHistorySummary(
        sessions: 0,
        videoCount: 0,
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

final class VideoCompressionHistoryStore: ObservableObject {
    @Published private(set) var sessions: [VideoCompressionSession] = []

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

    var summary: VideoCompressionHistorySummary {
        sessions.reduce(.empty) { partial, session in
            VideoCompressionHistorySummary(
                sessions: partial.sessions + 1,
                videoCount: partial.videoCount + session.videoCount,
                failedCount: partial.failedCount + session.failedCount,
                originalSizeMB: partial.originalSizeMB + session.originalSizeMB,
                compressedSizeMB: partial.compressedSizeMB + session.compressedSizeMB
            )
        }
    }

    @discardableResult
    func recordSession(
        videoCount: Int,
        failedCount: Int,
        originalSizeMB: Double,
        compressedSizeMB: Double,
        date: Date = Date()
    ) -> VideoCompressionSession? {
        guard videoCount > 0 else { return nil }

        let session = VideoCompressionSession(
            date: date,
            videoCount: videoCount,
            failedCount: failedCount,
            originalSizeMB: originalSizeMB,
            compressedSizeMB: compressedSizeMB
        )
        sessions.insert(session, at: 0)
        save()
        return session
    }

    func clearAll() {
        sessions.removeAll()
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            sessions = try decoder.decode([VideoCompressionSession].self, from: data)
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
            videoCompressionHistoryLogger.error("Failed to load video compression history. Moved corrupt file to \(backupURL.lastPathComponent, privacy: .public): \(loadError.localizedDescription, privacy: .public)")
        } catch {
            videoCompressionHistoryLogger.error("Failed to back up corrupt video compression history: \(error.localizedDescription, privacy: .public)")
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
            videoCompressionHistoryLogger.error("Failed to save video compression history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("PhotoDelete", isDirectory: true)
            .appendingPathComponent("video-compression-history.json")
    }
}
