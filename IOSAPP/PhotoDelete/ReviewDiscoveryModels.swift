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
            return L10n.string("随机浏览")
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
            return L10n.string("随机浏览未整理的旧照片")
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
        keepingValid validIdentifiers: Set<String>,
        excluding excludedIdentifiers: Set<String> = [],
        limit: Int = Int.max
    ) -> [String] {
        guard limit > 0 else { return [] }

        var seen: Set<String> = []
        var result: [String] = []
        for identifier in identifiers {
            guard validIdentifiers.contains(identifier),
                  !excludedIdentifiers.contains(identifier),
                  seen.insert(identifier).inserted else {
                continue
            }
            result.append(identifier)
            if result.count >= limit {
                break
            }
        }
        return result
    }

    static func resolvedSessionIdentifiers(
        existingSessionIDs: [String],
        candidateIdentifiers: [String],
        fallbackCandidateIdentifiers: [String] = [],
        validIdentifiers: Set<String>,
        excludedIdentifiers: Set<String>,
        seed: String,
        limit: Int,
        preservesExistingSessionIdentifiers: Bool = false
    ) -> [String] {
        guard limit > 0 else { return [] }

        var resolved = existingSessionIdentifiers(
            existingSessionIDs,
            keepingValid: validIdentifiers,
            excluding: preservesExistingSessionIdentifiers ? [] : excludedIdentifiers,
            limit: limit
        )
        guard resolved.count < limit else { return resolved }

        var selectedIDs = Set(resolved)
        let primaryFill = plannedIdentifiers(
            from: candidateIdentifiers,
            excluding: excludedIdentifiers.union(selectedIDs),
            seed: seed,
            limit: limit - resolved.count
        )
        resolved.append(contentsOf: primaryFill)
        selectedIDs.formUnion(primaryFill)

        guard resolved.count < limit else { return resolved }

        let fallbackFill = plannedIdentifiers(
            from: fallbackCandidateIdentifiers,
            excluding: excludedIdentifiers.union(selectedIDs),
            seed: seed,
            limit: limit - resolved.count
        )
        resolved.append(contentsOf: fallbackFill)
        return resolved
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

enum PhotoReviewSessionPaginator {
    static let defaultInitialPageSize = 80
    static let defaultPageSize = 80
    static let preloadThreshold = 12

    static func initialTargetIndex(
        assetIdentifiers: [String],
        reviewedAssetIdentifiers: Set<String>,
        savedAssetIdentifier: String?,
        prefersFirstUnreviewedBeforeSavedProgress: Bool = false
    ) -> Int {
        guard !assetIdentifiers.isEmpty else { return 0 }

        let firstUnreviewedIndex = assetIdentifiers.firstIndex { assetID in
            !reviewedAssetIdentifiers.contains(assetID)
        }

        guard let savedAssetIdentifier,
              let restoredIndex = assetIdentifiers.firstIndex(of: savedAssetIdentifier) else {
            return firstUnreviewedIndex ?? 0
        }

        if prefersFirstUnreviewedBeforeSavedProgress,
           let firstUnreviewedIndex,
           firstUnreviewedIndex <= restoredIndex {
            return firstUnreviewedIndex
        }

        let trailingUnreviewedIndex = assetIdentifiers[restoredIndex...].firstIndex { assetID in
            !reviewedAssetIdentifiers.contains(assetID)
        }

        return trailingUnreviewedIndex ?? firstUnreviewedIndex ?? restoredIndex
    }

    static func initialLoadedCount(totalCount: Int, initialPageSize: Int = defaultInitialPageSize) -> Int {
        min(max(totalCount, 0), max(initialPageSize, 0))
    }

    static func expandedLoadedCount(
        totalCount: Int,
        currentLoadedCount: Int,
        currentIndex: Int,
        pageSize: Int = defaultPageSize,
        threshold: Int = preloadThreshold
    ) -> Int {
        let clampedTotal = max(totalCount, 0)
        let clampedLoaded = min(max(currentLoadedCount, 0), clampedTotal)
        guard clampedTotal > clampedLoaded else { return clampedLoaded }
        guard currentIndex >= max(clampedLoaded - max(threshold, 0), 0) else {
            return clampedLoaded
        }
        return min(clampedTotal, clampedLoaded + max(pageSize, 0))
    }
}

enum VisibleListPagination {
    static func filteredItems<T>(_ items: [T], include: (T) -> Bool) -> [T] {
        items.filter(include)
    }

    static func visibleItems<T>(_ items: [T], limit: Int) -> [T] {
        Array(items.prefix(max(limit, 0)))
    }

    static func hasMore(totalCount: Int, limit: Int) -> Bool {
        totalCount > max(limit, 0)
    }

    static func advancedLimit(totalCount: Int, currentLimit: Int, step: Int) -> Int {
        min(max(totalCount, 0), max(currentLimit, 0) + max(step, 0))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        self?.nilIfBlank
    }
}

private extension Array where Element == String {
    func uniquedPreservingOrder() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
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

struct PhotoAssetMetadataSummary: Equatable {
    let captureDateText: String
    let locationText: String?
}

enum PhotoAssetMetadataFormatter {
    static func shortCaptureDate(for date: Date?) -> String {
        guard let date else {
            return L10n.string("拍摄时间未知")
        }
        return AppDateFormatter.string(from: date, template: "MMMd HH:mm")
    }

    static func detailCaptureDate(for date: Date?) -> String {
        guard let date else {
            return L10n.string("未保存拍摄时间")
        }
        return AppDateFormatter.string(from: date, dateStyle: .medium, timeStyle: .short)
    }

    static func locationText(locationTitle: String?, coordinate: CLLocationCoordinate2D?) -> String {
        optionalLocationText(locationTitle: locationTitle, coordinate: coordinate) ?? L10n.string("无地点信息")
    }

    static func optionalLocationText(locationTitle: String?, coordinate: CLLocationCoordinate2D?) -> String? {
        if let locationTitle = locationTitle?.nilIfBlank {
            return locationTitle
        }

        guard let coordinate else {
            return nil
        }

        return coordinateText(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    static func coordinateText(latitude: Double, longitude: Double) -> String {
        let latitudeText = latitude.formatted(.number.precision(.fractionLength(4)))
        let longitudeText = longitude.formatted(.number.precision(.fractionLength(4)))
        return "\(latitudeText), \(longitudeText)"
    }
}
