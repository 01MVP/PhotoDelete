//
//  ReviewDiscoveryModels.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 6/21/26.
//

import CoreLocation
import Foundation

enum PhotoRandomReviewScope: String, CaseIterable, Identifiable, Codable, Hashable {
    case memories
    case all
    case screenshots
    case videos
    case livePhotos
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memories:
            return L10n.string("遇见从前")
        case .all:
            return L10n.string("全部照片")
        case .screenshots:
            return L10n.string("截图")
        case .videos:
            return L10n.string("视频")
        case .livePhotos:
            return L10n.string("实况照片")
        case .favorites:
            return L10n.favoritesCategoryTitle
        }
    }

    var subtitle: String {
        switch self {
        case .memories:
            return L10n.string("随机翻出未整理的旧照片")
        case .all:
            return L10n.string("从全部未整理照片里随机")
        case .screenshots:
            return L10n.string("随机处理还没整理的截图")
        case .videos:
            return L10n.string("随机处理还没整理的视频")
        case .livePhotos:
            return L10n.string("随机处理还没整理的实况照片")
        case .favorites:
            return L10n.string("随机回看收藏里的照片")
        }
    }

    var icon: String {
        switch self {
        case .memories:
            return "sparkles"
        case .all:
            return "photo.on.rectangle"
        case .screenshots:
            return "iphone"
        case .videos:
            return "video"
        case .livePhotos:
            return "livephoto"
        case .favorites:
            return "heart"
        }
    }
}

enum PhotoRandomReviewPlanner {
    static let defaultBatchSize = 20
    static let oldPhotoMinimumMonthAge = 6

    static func plannedIdentifiers(
        from candidateIdentifiers: [String],
        excluding excludedIdentifiers: Set<String>,
        seed: String,
        limit: Int
    ) -> [String] {
        guard limit > 0 else { return [] }

        var seen: Set<String> = []
        let eligible = candidateIdentifiers.compactMap { identifier -> String? in
            guard !identifier.isEmpty,
                  !excludedIdentifiers.contains(identifier),
                  seen.insert(identifier).inserted else {
                return nil
            }
            return identifier
        }

        return Array(
            eligible.sorted {
                let lhsHash = stableHash(seed: seed, identifier: $0)
                let rhsHash = stableHash(seed: seed, identifier: $1)
                if lhsHash == rhsHash {
                    return $0 < $1
                }
                return lhsHash < rhsHash
            }
            .prefix(limit)
        )
    }

    static func existingSessionIdentifiers(
        _ identifiers: [String],
        keepingValid validIdentifiers: Set<String>
    ) -> [String] {
        var seen: Set<String> = []
        return identifiers.compactMap { identifier in
            guard validIdentifiers.contains(identifier),
                  seen.insert(identifier).inserted else {
                return nil
            }
            return identifier
        }
    }

    private static func stableHash(seed: String, identifier: String) -> UInt64 {
        let text = "\(seed)|\(identifier)"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

struct PhotoRandomReviewSession: Codable, Equatable {
    let scopeID: String
    let assetIdentifiers: [String]
    let createdAt: Date
}

enum PhotoRandomReviewSessionStore {
    static func load(scopeID: String, defaults: UserDefaults = .standard) -> [String] {
        guard let data = defaults.data(forKey: AppConstants.randomReviewSessionsKey),
              let sessions = try? JSONDecoder().decode([String: PhotoRandomReviewSession].self, from: data) else {
            return []
        }
        return sessions[scopeID]?.assetIdentifiers ?? []
    }

    static func save(
        assetIdentifiers: [String],
        scopeID: String,
        defaults: UserDefaults = .standard,
        date: Date = Date()
    ) {
        var sessions = loadAll(defaults: defaults)
        sessions[scopeID] = PhotoRandomReviewSession(
            scopeID: scopeID,
            assetIdentifiers: assetIdentifiers,
            createdAt: date
        )
        saveAll(sessions, defaults: defaults)
    }

    static func clear(scopeID: String, defaults: UserDefaults = .standard) {
        var sessions = loadAll(defaults: defaults)
        sessions.removeValue(forKey: scopeID)
        saveAll(sessions, defaults: defaults)
    }

    static func clearAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: AppConstants.randomReviewSessionsKey)
    }

    private static func loadAll(defaults: UserDefaults) -> [String: PhotoRandomReviewSession] {
        guard let data = defaults.data(forKey: AppConstants.randomReviewSessionsKey),
              let sessions = try? JSONDecoder().decode([String: PhotoRandomReviewSession].self, from: data) else {
            return [:]
        }
        return sessions
    }

    private static func saveAll(
        _ sessions: [String: PhotoRandomReviewSession],
        defaults: UserDefaults
    ) {
        guard !sessions.isEmpty else {
            defaults.removeObject(forKey: AppConstants.randomReviewSessionsKey)
            return
        }

        if let data = try? JSONEncoder().encode(sessions) {
            defaults.set(data, forKey: AppConstants.randomReviewSessionsKey)
        }
    }
}

struct PhotoLocationAssetRecord: Equatable {
    let identifier: String
    let latitude: Double?
    let longitude: Double?
    let isReviewed: Bool

    init(identifier: String, location: CLLocation?, isReviewed: Bool) {
        self.identifier = identifier
        self.latitude = location?.coordinate.latitude
        self.longitude = location?.coordinate.longitude
        self.isReviewed = isReviewed
    }

    init(identifier: String, latitude: Double?, longitude: Double?, isReviewed: Bool) {
        self.identifier = identifier
        self.latitude = latitude
        self.longitude = longitude
        self.isReviewed = isReviewed
    }
}

struct PhotoLocationGroupInfo: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let assetCount: Int
    let reviewedCount: Int
    let isNoLocationGroup: Bool

    var progress: Double {
        guard assetCount > 0 else { return 0 }
        return min(Double(reviewedCount) / Double(assetCount), 1)
    }
}

enum PhotoLocationGrouping {
    static let noLocationID = "location:none"
    static let defaultMaximumGroups = 30
    private static let coordinateBucketSize = 0.25

    struct Result {
        let groups: [PhotoLocationGroupInfo]
        let identifiersByGroupID: [String: [String]]
    }

    static func buildGroups(
        from records: [PhotoLocationAssetRecord],
        maximumGroups: Int = defaultMaximumGroups
    ) -> Result {
        guard maximumGroups > 0 else {
            return Result(groups: [], identifiersByGroupID: [:])
        }

        var buckets: [String: [PhotoLocationAssetRecord]] = [:]
        for record in records {
            let id = groupID(latitude: record.latitude, longitude: record.longitude)
            buckets[id, default: []].append(record)
        }

        let noLocationRecords = buckets.removeValue(forKey: noLocationID) ?? []
        let sortedLocationBuckets = buckets
            .map { id, records in (id: id, records: records) }
            .sorted {
                if $0.records.count == $1.records.count {
                    return $0.id < $1.id
                }
                return $0.records.count > $1.records.count
            }
            .prefix(maximumGroups)

        var groups: [PhotoLocationGroupInfo] = []
        var cache: [String: [String]] = [:]

        for (index, bucket) in sortedLocationBuckets.enumerated() {
            groups.append(
                PhotoLocationGroupInfo(
                    id: bucket.id,
                    title: String(format: L10n.string("附近地点 %lld"), Int64(index + 1)),
                    subtitle: locationSubtitle(for: bucket.records),
                    assetCount: bucket.records.count,
                    reviewedCount: bucket.records.filter(\.isReviewed).count,
                    isNoLocationGroup: false
                )
            )
            cache[bucket.id] = bucket.records.map(\.identifier)
        }

        if !noLocationRecords.isEmpty {
            groups.append(
                PhotoLocationGroupInfo(
                    id: noLocationID,
                    title: L10n.string("无地点信息"),
                    subtitle: L10n.string("这些照片没有保存拍摄地点"),
                    assetCount: noLocationRecords.count,
                    reviewedCount: noLocationRecords.filter(\.isReviewed).count,
                    isNoLocationGroup: true
                )
            )
            cache[noLocationID] = noLocationRecords.map(\.identifier)
        }

        return Result(groups: groups, identifiersByGroupID: cache)
    }

    static func groupID(latitude: Double?, longitude: Double?) -> String {
        guard let latitude, let longitude,
              latitude >= -90, latitude <= 90,
              longitude >= -180, longitude <= 180 else {
            return noLocationID
        }

        let latBucket = Int((latitude / coordinateBucketSize).rounded(.toNearestOrAwayFromZero))
        let lonBucket = Int((longitude / coordinateBucketSize).rounded(.toNearestOrAwayFromZero))
        return "location:\(latBucket):\(lonBucket)"
    }

    private static func locationSubtitle(for records: [PhotoLocationAssetRecord]) -> String {
        if records.isEmpty {
            return L10n.shortPhotoCount(0)
        }

        let reviewedCount = records.filter(\.isReviewed).count
        return String(
            format: L10n.string("%lld 张 · 已整理 %lld 张"),
            Int64(records.count),
            Int64(reviewedCount)
        )
    }
}

enum PhotoMemoryCaptionFormatter {
    static func relativeTitle(
        for date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else {
            return L10n.string("拍摄时间未知")
        }

        if calendar.isDate(date, inSameDayAs: now) {
            return L10n.string("今天")
        }

        let components = calendar.dateComponents([.year, .month, .day], from: date, to: now)
        if let years = components.year, years > 0 {
            return String(format: L10n.string("%lld 年前"), Int64(years))
        }
        if let months = components.month, months > 0 {
            return String(format: L10n.string("%lld 个月前"), Int64(months))
        }
        if let days = components.day, days > 0 {
            return String(format: L10n.string("%lld 天前"), Int64(days))
        }
        return L10n.string("刚刚")
    }

    static func dateSubtitle(for date: Date?) -> String? {
        guard let date else { return nil }
        return AppDateFormatter.string(from: date, template: "yMMMd")
    }
}

struct PhotoMemoryCaption: Equatable {
    let title: String
    let subtitle: String?
}
