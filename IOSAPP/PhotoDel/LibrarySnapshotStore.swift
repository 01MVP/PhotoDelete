import Foundation

struct PhotoLibrarySnapshot: Codable {
    let createdAt: Date
    let allPhotoIDs: [String]
    let videoIDs: [String]
    let screenshotIDs: [String]
    let favoriteIDs: [String]
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
        do {
            try Self.ensureDirectoryExists(for: fileURL)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("保存照片索引缓存失败: \(error.localizedDescription)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func applicationSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("PhotoDel", isDirectory: true)
    }

    private static func ensureDirectoryExists(for fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}

final class AlbumListSnapshotStore {
    private let fileURL: URL

    init(filename: String = "album-list-snapshot.json") {
        self.fileURL = Self.applicationSupportDirectory().appendingPathComponent(filename)
    }

    func load() -> AlbumListSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AlbumListSnapshot.self, from: data)
    }

    func save(_ snapshot: AlbumListSnapshot) {
        do {
            try Self.ensureDirectoryExists(for: fileURL)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("保存相册缓存失败: \(error.localizedDescription)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func applicationSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("PhotoDel", isDirectory: true)
    }

    private static func ensureDirectoryExists(for fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
