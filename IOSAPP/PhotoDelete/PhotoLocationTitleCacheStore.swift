//
//  PhotoLocationTitleCacheStore.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/24/26.
//

import Foundation
import OSLog

private let photoLocationTitleCacheLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "PhotoDelete",
    category: "PhotoLocationTitleCache"
)

final class PhotoLocationTitleCacheStore {
    private(set) var titlesByGroupID: [String: PhotoLocationResolvedTitle] = [:]

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

    func titleCache(localeIdentifier: String? = nil) -> [String: PhotoLocationResolvedTitle] {
        guard let localeIdentifier else {
            return titlesByGroupID
        }

        var cache: [String: PhotoLocationResolvedTitle] = [:]
        for (storageKey, title) in titlesByGroupID {
            guard let scopedKey = Self.scopedKey(from: storageKey),
                  scopedKey.localeIdentifier == localeIdentifier else {
                continue
            }
            cache[scopedKey.groupID] = title
        }
        return cache
    }

    func merge(_ titles: [String: PhotoLocationResolvedTitle], localeIdentifier: String? = nil) {
        let validTitles = titles.filter { groupID, title in
            !groupID.isEmpty && !trimmed(title.title).isEmpty
        }
        guard !validTitles.isEmpty else { return }

        let scopedTitles: [String: PhotoLocationResolvedTitle]
        if let localeIdentifier {
            scopedTitles = Dictionary(uniqueKeysWithValues: validTitles.map { groupID, title in
                (Self.storageKey(groupID: groupID, localeIdentifier: localeIdentifier), title)
            })
        } else {
            scopedTitles = validTitles
        }

        titlesByGroupID.merge(scopedTitles) { _, new in new }
        save()
    }

    func prune(keeping validGroupIDs: Set<String>, localeIdentifier: String? = nil) {
        let pruned = titlesByGroupID.filter { storageKey, _ in
            guard let localeIdentifier else {
                return validGroupIDs.contains(storageKey)
            }

            guard let scopedKey = Self.scopedKey(from: storageKey) else {
                return false
            }
            guard scopedKey.localeIdentifier == localeIdentifier else {
                return true
            }
            return validGroupIDs.contains(scopedKey.groupID)
        }
        guard pruned.count != titlesByGroupID.count else { return }
        titlesByGroupID = pruned
        save()
    }

    func clear() {
        titlesByGroupID = [:]
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            titlesByGroupID = try decoder.decode([String: PhotoLocationResolvedTitle].self, from: data)
        } catch {
            titlesByGroupID = [:]
            backupCorruptStoreFile(loadError: error)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(titlesByGroupID)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            photoLocationTitleCacheLogger.error("Failed to save location title cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func backupCorruptStoreFile(loadError: Error) {
        let backupURL = Self.corruptBackupURL(for: fileURL)

        do {
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            photoLocationTitleCacheLogger.error("Failed to load location title cache. Moved corrupt file to \(backupURL.lastPathComponent, privacy: .public): \(loadError.localizedDescription, privacy: .public)")
        } catch {
            photoLocationTitleCacheLogger.error("Failed to back up corrupt location title cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("PhotoDelete", isDirectory: true)
            .appendingPathComponent("location-title-cache.json")
    }

    static func corruptBackupURL(
        for fileURL: URL,
        timestamp: Int = Int(Date().timeIntervalSince1970),
        id: UUID = UUID()
    ) -> URL {
        let baseURL = fileURL.deletingPathExtension()
        let fileExtension = fileURL.pathExtension
        let backupName = "\(baseURL.lastPathComponent).corrupt-\(timestamp)-\(id.uuidString)"
        let backupFileName = fileExtension.isEmpty ? backupName : "\(backupName).\(fileExtension)"
        return fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(backupFileName)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func storageKey(groupID: String, localeIdentifier: String) -> String {
        "\(localeIdentifier)|\(groupID)"
    }

    private static func scopedKey(from storageKey: String) -> (localeIdentifier: String, groupID: String)? {
        guard let separatorRange = storageKey.range(of: "|") else { return nil }
        let localeIdentifier = String(storageKey[..<separatorRange.lowerBound])
        let groupID = String(storageKey[separatorRange.upperBound...])
        guard !localeIdentifier.isEmpty, !groupID.isEmpty else { return nil }
        return (localeIdentifier, groupID)
    }
}
