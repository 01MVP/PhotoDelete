//
//  CleanupStatsStore.swift
//  PhotoDel
//
//  Created by PhotoDel Team on 11/7/25.
//

import Foundation
import Combine

struct CleanupSession: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let deletedPhotos: Int
    let favoritedPhotos: Int
    let organizedPhotos: Int
    let estimatedSpaceSavedMB: Double

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        deletedPhotos: Int,
        favoritedPhotos: Int,
        organizedPhotos: Int,
        estimatedSpaceSavedMB: Double
    ) {
        self.id = id
        self.date = date
        self.deletedPhotos = deletedPhotos
        self.favoritedPhotos = favoritedPhotos
        self.organizedPhotos = organizedPhotos
        self.estimatedSpaceSavedMB = estimatedSpaceSavedMB
    }

    var monthKey: String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    var formattedDate: String {
        CleanupStatsFormatter.sessionDate.string(from: date)
    }

    var formattedSpaceSaved: String {
        CleanupStatsFormatter.space(estimatedSpaceSavedMB)
    }
}

struct CleanupMonthlySummary: Identifiable, Equatable {
    let monthKey: String
    let sessions: Int
    let deletedPhotos: Int
    let favoritedPhotos: Int
    let organizedPhotos: Int
    let estimatedSpaceSavedMB: Double

    var id: String { monthKey }

    var title: String {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2 else { return monthKey }
        var components = DateComponents()
        components.year = Int(parts[0])
        components.month = Int(parts[1])
        guard let date = Calendar.current.date(from: components) else { return monthKey }
        return CleanupStatsFormatter.month.string(from: date)
    }

    var formattedSpaceSaved: String {
        CleanupStatsFormatter.space(estimatedSpaceSavedMB)
    }
}

struct CleanupStatsSummary: Equatable {
    let sessions: Int
    let deletedPhotos: Int
    let favoritedPhotos: Int
    let organizedPhotos: Int
    let estimatedSpaceSavedMB: Double

    static let empty = CleanupStatsSummary(
        sessions: 0,
        deletedPhotos: 0,
        favoritedPhotos: 0,
        organizedPhotos: 0,
        estimatedSpaceSavedMB: 0
    )

    var formattedSpaceSaved: String {
        CleanupStatsFormatter.space(estimatedSpaceSavedMB)
    }
}

final class CleanupStatsStore: ObservableObject {
    @Published private(set) var sessions: [CleanupSession] = []

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

    var summary: CleanupStatsSummary {
        sessions.reduce(.empty) { partial, session in
            CleanupStatsSummary(
                sessions: partial.sessions + 1,
                deletedPhotos: partial.deletedPhotos + session.deletedPhotos,
                favoritedPhotos: partial.favoritedPhotos + session.favoritedPhotos,
                organizedPhotos: partial.organizedPhotos + session.organizedPhotos,
                estimatedSpaceSavedMB: partial.estimatedSpaceSavedMB + session.estimatedSpaceSavedMB
            )
        }
    }

    var monthlySummaries: [CleanupMonthlySummary] {
        let grouped = Dictionary(grouping: sessions, by: \.monthKey)
        return grouped.map { monthKey, sessions in
            CleanupMonthlySummary(
                monthKey: monthKey,
                sessions: sessions.count,
                deletedPhotos: sessions.reduce(0) { $0 + $1.deletedPhotos },
                favoritedPhotos: sessions.reduce(0) { $0 + $1.favoritedPhotos },
                organizedPhotos: sessions.reduce(0) { $0 + $1.organizedPhotos },
                estimatedSpaceSavedMB: sessions.reduce(0) { $0 + $1.estimatedSpaceSavedMB }
            )
        }
        .sorted { $0.monthKey > $1.monthKey }
    }

    func recordSession(
        deletedPhotos: Int,
        favoritedPhotos: Int,
        organizedPhotos: Int,
        estimatedSpaceSavedMB: Double,
        date: Date = Date()
    ) {
        guard deletedPhotos > 0 || favoritedPhotos > 0 || organizedPhotos > 0 else { return }

        let session = CleanupSession(
            date: date,
            deletedPhotos: max(deletedPhotos, 0),
            favoritedPhotos: max(favoritedPhotos, 0),
            organizedPhotos: max(organizedPhotos, 0),
            estimatedSpaceSavedMB: max(estimatedSpaceSavedMB, 0)
        )
        sessions.insert(session, at: 0)
        save()
    }

    func clearAll() {
        sessions.removeAll()
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            sessions = try decoder.decode([CleanupSession].self, from: data)
                .sorted { $0.date > $1.date }
        } catch {
            sessions = []
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
            print("保存清理统计失败: \(error.localizedDescription)")
        }
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("PhotoDel", isDirectory: true)
            .appendingPathComponent("cleanup-history.json")
    }
}

enum CleanupStatsFormatter {
    static let sessionDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter
    }()

    static func space(_ megabytes: Double) -> String {
        if megabytes < 1000 {
            return String(format: "%.1f MB", megabytes)
        }
        return String(format: "%.1f GB", megabytes / 1000)
    }
}
