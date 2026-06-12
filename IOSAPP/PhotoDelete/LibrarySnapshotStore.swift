import Foundation
import OSLog

private let snapshotStoreLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "PhotoDelete",
    category: "SnapshotStore"
)

struct PhotoLibrarySnapshot: Codable {
    let createdAt: Date
    let allPhotoIDs: [String]
    let videoIDs: [String]
    let screenshotIDs: [String]
    let livePhotoIDs: [String]
    let favoriteIDs: [String]

    init(
        createdAt: Date,
        allPhotoIDs: [String],
        videoIDs: [String],
        screenshotIDs: [String],
        livePhotoIDs: [String] = [],
        favoriteIDs: [String]
    ) {
        self.createdAt = createdAt
        self.allPhotoIDs = allPhotoIDs
        self.videoIDs = videoIDs
        self.screenshotIDs = screenshotIDs
        self.livePhotoIDs = livePhotoIDs
        self.favoriteIDs = favoriteIDs
    }

    private enum CodingKeys: String, CodingKey {
        case createdAt
        case allPhotoIDs
        case videoIDs
        case screenshotIDs
        case livePhotoIDs
        case favoriteIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        allPhotoIDs = try container.decode([String].self, forKey: .allPhotoIDs)
        videoIDs = try container.decode([String].self, forKey: .videoIDs)
        screenshotIDs = try container.decode([String].self, forKey: .screenshotIDs)
        livePhotoIDs = try container.decodeIfPresent([String].self, forKey: .livePhotoIDs) ?? []
        favoriteIDs = try container.decode([String].self, forKey: .favoriteIDs)
    }
}

struct CachedAlbumRecord: Codable {
    let id: String
    let title: String
    let typeRawValue: String
    let photosCount: Int
    let thumbnailAssetID: String?
}

struct AlbumListSnapshot: Codable {
    let createdAt: Date
    let systemAlbums: [CachedAlbumRecord]
    let userAlbums: [CachedAlbumRecord]
}

final class PhotoLibrarySnapshotStore {
    private static let writeQueue = DispatchQueue(label: "com.01mvp.photodelete.photo-library-snapshot")
    private let fileURL: URL

    init(filename: String = "photo-library-snapshot.json") {
        self.fileURL = Self.applicationSupportDirectory().appendingPathComponent(filename)
    }

    var hasSnapshot: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func load() -> PhotoLibrarySnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PhotoLibrarySnapshot.self, from: data)
    }

    func save(_ snapshot: PhotoLibrarySnapshot) {
        Self.writeQueue.sync {
            if let currentSnapshot = load(), currentSnapshot.createdAt > snapshot.createdAt {
                return
            }

            do {
                try Self.ensureDirectoryExists(for: fileURL)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                snapshotStoreLogger.error("Failed to save photo library snapshot: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func applicationSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("PhotoDelete", isDirectory: true)
    }

    private static func ensureDirectoryExists(for fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}

final class AlbumListSnapshotStore {
    private static let writeQueue = DispatchQueue(label: "com.01mvp.photodelete.album-list-snapshot")
    private let fileURL: URL

    init(filename: String = "album-list-snapshot.json") {
        self.fileURL = Self.applicationSupportDirectory().appendingPathComponent(filename)
    }

    func load() -> AlbumListSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AlbumListSnapshot.self, from: data)
    }

    func save(_ snapshot: AlbumListSnapshot) {
        Self.writeQueue.sync {
            if let currentSnapshot = load(), currentSnapshot.createdAt > snapshot.createdAt {
                return
            }

            do {
                try Self.ensureDirectoryExists(for: fileURL)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                snapshotStoreLogger.error("Failed to save album list snapshot: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func applicationSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("PhotoDelete", isDirectory: true)
    }

    private static func ensureDirectoryExists(for fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
