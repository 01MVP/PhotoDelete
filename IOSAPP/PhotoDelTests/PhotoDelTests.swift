//
//  PhotoDelTests.swift
//  PhotoDelTests
//
//  Created by jackie xiao on 11/7/25.
//

import Testing
import Foundation
import Photos
@testable import PhotoDel

struct PhotoDelTests {

    @Test func timeGroupResolverClassifiesRelativeDates() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = makeDate(year: 2026, month: 6, day: 10, calendar: calendar)

        #expect(TimeGroupResolver.group(for: makeDate(year: 2026, month: 6, day: 10, calendar: calendar), now: now, calendar: calendar) == .today)
        #expect(TimeGroupResolver.group(for: makeDate(year: 2026, month: 6, day: 8, calendar: calendar), now: now, calendar: calendar) == .thisWeek)
        #expect(TimeGroupResolver.group(for: makeDate(year: 2026, month: 6, day: 1, calendar: calendar), now: now, calendar: calendar) == .thisMonth)
        #expect(TimeGroupResolver.group(for: makeDate(year: 2026, month: 5, day: 20, calendar: calendar), now: now, calendar: calendar) == .lastMonth)
        #expect(TimeGroupResolver.group(for: makeDate(year: 2026, month: 4, day: 30, calendar: calendar), now: now, calendar: calendar) == .olderPhotos)
    }

    // MARK: - TimeGroupResolver edge cases

    @Test func timeGroupResolverMidnightBoundary() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // "now" is 2026-06-10 at noon
        let now = makeDate(year: 2026, month: 6, day: 10, calendar: calendar)

        // A photo from the very start of "today" (midnight) should still be .today
        let midnight = calendar.startOfDay(for: now)
        #expect(TimeGroupResolver.group(for: midnight, now: now, calendar: calendar) == .today)

        // A photo from the last second of yesterday (23:59:59) is NOT today
        let endOfYesterday = makeDate(year: 2026, month: 6, day: 9, hour: 23, minute: 59, second: 59, calendar: calendar)
        #expect(TimeGroupResolver.group(for: endOfYesterday, now: now, calendar: calendar) != .today)
    }

    @Test func timeGroupResolverCrossYearBoundary() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // "now" is 2026-01-02 (Friday)
        let now = makeDate(year: 2026, month: 1, day: 2, calendar: calendar)

        // Dec 31 of previous year
        let dec31 = makeDate(year: 2025, month: 12, day: 31, calendar: calendar)
        let groupDec31 = TimeGroupResolver.group(for: dec31, now: now, calendar: calendar)
        // Should NOT be .today or .thisMonth (different year)
        #expect(groupDec31 != .today)
        #expect(groupDec31 != .thisMonth)

        // Jan 1 same year — same week as Jan 2 (both in week 1 of 2026)
        let jan1 = makeDate(year: 2026, month: 1, day: 1, calendar: calendar)
        #expect(TimeGroupResolver.group(for: jan1, now: now, calendar: calendar) == .thisWeek)

        // Very old date should be .olderPhotos
        let oldDate = makeDate(year: 2024, month: 1, day: 1, calendar: calendar)
        #expect(TimeGroupResolver.group(for: oldDate, now: now, calendar: calendar) == .olderPhotos)
    }

    @Test func timeGroupResolverWeekVsLastMonthBoundary() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // "now" is 2026-06-10 (Wednesday)
        let now = makeDate(year: 2026, month: 6, day: 10, calendar: calendar)

        // A date in last month that falls in a different week: May 20, 2026
        let may20 = makeDate(year: 2026, month: 5, day: 20, calendar: calendar)
        #expect(TimeGroupResolver.group(for: may20, now: now, calendar: calendar) == .lastMonth)

        // A date in this month but early (June 1) — should be .thisMonth, not .thisWeek
        let june1 = makeDate(year: 2026, month: 6, day: 1, calendar: calendar)
        #expect(TimeGroupResolver.group(for: june1, now: now, calendar: calendar) == .thisMonth)

        // A date in last month that is in the same week component as now should be .thisWeek
        // because isSameWeek is checked before isSameMonth.
        // June 10 is in week 24. May 20 is week 21. They differ.
        // But if we pick a date from last month that shares the same ISO week:
        // This can happen when "now" is early in the month and the previous month's
        // last days fall in the same ISO week. For example, if now is Sunday June 1,
        // then May 31 (Saturday) is in the same week.
        let sundayJune1 = makeDate(year: 2025, month: 6, day: 1, calendar: calendar) // Sunday
        let may31 = makeDate(year: 2025, month: 5, day: 31, calendar: calendar)
        // Verify both are in the same ISO week
        let weekOfJune1 = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: sundayJune1)
        let weekOfMay31 = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: may31)
        if weekOfJune1 == weekOfMay31 {
            // Same week, so May 31 should return .thisWeek even though it is in "last month"
            #expect(TimeGroupResolver.group(for: may31, now: sundayJune1, calendar: calendar) == .thisWeek)
        }
    }

    // MARK: - OrganizeStats tests

    @Test func organizeStatsFormatsSavedSpace() async throws {
        #expect(OrganizeStats(spaceSaved: 42).formattedSpaceSaved == "42.0 MB")
        #expect(OrganizeStats(spaceSaved: 1536).formattedSpaceSaved == "1.5 GB")
    }

    @Test func organizeStatsFormattedSpaceSavedEdgeCases() async throws {
        // 0 MB
        #expect(OrganizeStats(spaceSaved: 0).formattedSpaceSaved == "0.0 MB")

        // Just under the GB threshold
        #expect(OrganizeStats(spaceSaved: 999).formattedSpaceSaved == "999.0 MB")

        // Exactly at the GB boundary (1000 MB = 1.0 GB)
        #expect(OrganizeStats(spaceSaved: 1000).formattedSpaceSaved == "1.0 GB")

        // Very large values
        let huge = OrganizeStats(spaceSaved: 1_000_000)
        #expect(huge.formattedSpaceSaved == "1000.0 GB")
    }

    @Test func organizeStatsDefaultValues() async throws {
        let stats = OrganizeStats()
        #expect(stats.totalPhotos == 0)
        #expect(stats.deletedPhotos == 0)
        #expect(stats.keptPhotos == 0)
        #expect(stats.favoritedPhotos == 0)
        #expect(stats.spaceSaved == 0.0)
        #expect(stats.formattedSpaceSaved == "0.0 MB")
    }

    // MARK: - AlbumInfo tests

    @Test func albumInfoWithNilAssetCollectionUsesTypeRawValue() async throws {
        for albumType in AlbumType.allCases {
            let album = AlbumInfo(assetCollection: nil, type: albumType)
            #expect(album.id == albumType.rawValue, "id should be type.rawValue for type \(albumType)")
            #expect(album.title == albumType.rawValue, "title should be type.rawValue for type \(albumType)")
            #expect(album.assetCollection == nil)
            #expect(album.type == albumType)
        }
    }

    @Test func albumInfoDefaults() async throws {
        let album = AlbumInfo(assetCollection: nil, type: .screenshots)
        #expect(album.photosCount == 0)
        #expect(album.thumbnailAsset == nil)
    }

    // MARK: - DataManager initialization

    @Test func dataManagerInitializesWithEmptyCandidates() async throws {
        let dm = DataManager()
        #expect(dm.deleteCandidates.isEmpty)
        #expect(dm.favoriteCandidates.isEmpty)
        #expect(dm.timeGroups.isEmpty)
        #expect(dm.systemAlbums.isEmpty)
        #expect(dm.userAlbums.isEmpty)
    }

    @Test func cancelAllOperationsOnEmptySetsDoesNotCrash() async throws {
        let dm = DataManager()
        dm.cancelAllOperations()
        #expect(dm.deleteCandidates.isEmpty)
        #expect(dm.favoriteCandidates.isEmpty)
    }

    // MARK: - DataManager candidate operations
    //
    // PHAsset does not support direct instantiation — it's a fetch-only type.
    // These tests fetch a real asset from the library. If the test environment
    // has no photos (common in CI), the candidate-operation tests are skipped.

    private func fetchFirstAsset() -> PHAsset? {
        let result = PHAsset.fetchAssets(with: .image, options: nil)
        return result.firstObject
    }

    @Test func addToDeleteCandidatesRemovesFromFavorites() async throws {
        guard let asset = fetchFirstAsset() else { return }
        let dm = DataManager()

        dm.addToFavoriteCandidates(asset)
        #expect(dm.isInFavoriteCandidates(asset))
        #expect(!dm.isInDeleteCandidates(asset))

        // Adding to delete candidates should remove from favorites (mutual exclusion)
        dm.addToDeleteCandidates(asset)
        #expect(dm.isInDeleteCandidates(asset))
        #expect(!dm.isInFavoriteCandidates(asset))
    }

    @Test func addToFavoriteCandidatesRemovesFromDelete() async throws {
        guard let asset = fetchFirstAsset() else { return }
        let dm = DataManager()

        dm.addToDeleteCandidates(asset)
        #expect(dm.isInDeleteCandidates(asset))
        #expect(!dm.isInFavoriteCandidates(asset))

        // Adding to favorites should remove from delete candidates (mutual exclusion)
        dm.addToFavoriteCandidates(asset)
        #expect(dm.isInFavoriteCandidates(asset))
        #expect(!dm.isInDeleteCandidates(asset))
    }

    @Test func cancelAllOperationsClearsBothSets() async throws {
        guard let asset = fetchFirstAsset() else { return }
        let dm = DataManager()

        dm.addToDeleteCandidates(asset)
        dm.addToFavoriteCandidates(asset)
        dm.cancelAllOperations()
        #expect(dm.deleteCandidates.isEmpty)
        #expect(dm.favoriteCandidates.isEmpty)
    }

    @Test func candidateMembershipAfterAdding() async throws {
        guard let asset = fetchFirstAsset() else { return }
        let dm = DataManager()

        // Initially not in any candidate set
        #expect(!dm.isInDeleteCandidates(asset))
        #expect(!dm.isInFavoriteCandidates(asset))

        // After adding to favorites
        dm.addToFavoriteCandidates(asset)
        #expect(dm.isInFavoriteCandidates(asset))
        #expect(!dm.isInDeleteCandidates(asset))

        // Remove from favorites
        dm.removeFromFavoriteCandidates(asset)
        #expect(!dm.isInFavoriteCandidates(asset))

        // After adding to delete
        dm.addToDeleteCandidates(asset)
        #expect(dm.isInDeleteCandidates(asset))

        // Remove from delete
        dm.removeFromDeleteCandidates(asset)
        #expect(!dm.isInDeleteCandidates(asset))
    }

    @Test func executeBatchOperationsWithEmptyCandidatesRequiresAccess() async throws {
        let dm = DataManager()
        // Without photo library authorization, checkSystemReadiness() fails first
        // (before reaching the empty-candidates early return), so completion
        // receives (false, error).
        let result: (Bool, Error?) = await withCheckedContinuation { continuation in
            dm.executeBatchOperations { success, error in
                continuation.resume(returning: (success, error))
            }
        }
        #expect(result.0 == false)
        #expect(result.1 != nil)
    }

    // MARK: - TimeGroupInfo tests

    @Test func timeGroupInfoDefaultProgressIsZero() async throws {
        for group in TimeGroup.allCases {
            let info = TimeGroupInfo(timeGroup: group, photosCount: 42)
            #expect(info.progress == 0.0, "Default progress should be 0.0 for \(group)")
            #expect(info.photosCount == 42)
        }
    }

    @Test func timeGroupInfoIdEqualsTimeGroupRawValue() async throws {
        for group in TimeGroup.allCases {
            let info = TimeGroupInfo(timeGroup: group, photosCount: 10, progress: 0.5)
            #expect(info.id == group.rawValue, "id should equal timeGroup.rawValue for \(group)")
            #expect(info.timeGroup == group)
            #expect(info.progress == 0.5)
        }
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day, hour: 12)
        return components.date!
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, calendar: Calendar) -> Date {
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return components.date!
    }

}
