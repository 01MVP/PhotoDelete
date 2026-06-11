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
        #expect(stats.spaceSaved == 0.0)
        #expect(stats.formattedSpaceSaved == "0.0 MB")
    }

    @Test func feedbackEmailBodyDoesNotDuplicateSystemMailSignature() async throws {
        let body = FeedbackDiagnostics.emailBody()
        #expect(body.contains("Anonymous User ID:"))
        #expect(!body.contains("发自我的 iPhone"))
        #expect(!body.contains("Sent from my iPhone"))
    }

    // MARK: - Gesture settings tests

    @Test func swipeGestureStandardPresetMatchesDefaultActions() async throws {
        #expect(SwipeGesturePreferences.defaultAction(for: .left) == .delete)
        #expect(SwipeGesturePreferences.defaultAction(for: .right) == .keep)
        #expect(SwipeGesturePreferences.defaultAction(for: .up) == .favorite)
    }

    @Test func swipeGesturePresetsCoverRequestedLayouts() async throws {
        #expect(SwipeGesturePreset.standard.leftAction == .delete)
        #expect(SwipeGesturePreset.standard.rightAction == .keep)

        #expect(SwipeGesturePreset.reversed.leftAction == .keep)
        #expect(SwipeGesturePreset.reversed.rightAction == .delete)

        #expect(SwipeGesturePreset.verticalDelete.upAction == .delete)
        #expect(SwipeGesturePreset.verticalDelete.leftAction == .keep)
    }

    @Test func swipeGestureActionNormalizationFallsBackForUnknownValues() async throws {
        #expect(SwipeGesturePreferences.normalizedAction("favorite", fallback: .delete) == .favorite)
        #expect(SwipeGesturePreferences.normalizedAction("unknown", fallback: .keep) == .keep)
    }

    @Test func photoReviewModeNormalizesStoredValues() async throws {
        #expect(PhotoReviewMode.normalized("browser") == .browser)
        #expect(PhotoReviewMode.normalized("card") == .card)
        #expect(PhotoReviewMode.normalized("unknown") == .card)
        #expect(PhotoReviewMode.normalized(nil) == .card)
        #expect(PhotoReviewMode.card.toggled == .browser)
        #expect(PhotoReviewMode.browser.toggled == .card)
    }

    // MARK: - CleanupStatsStore tests

    @Test func cleanupStatsStoreRecordsAndPersistsSessions() async throws {
        let fileURL = temporaryStatsURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = CleanupStatsStore(fileURL: fileURL)
        let date = makeDate(year: 2026, month: 6, day: 11, calendar: Calendar(identifier: .gregorian))
        store.recordSession(
            deletedPhotos: 3,
            favoritedPhotos: 2,
            organizedPhotos: 5,
            estimatedSpaceSavedMB: 9,
            date: date
        )

        #expect(store.sessions.count == 1)
        #expect(store.summary.deletedPhotos == 3)
        #expect(store.summary.favoritedPhotos == 2)
        #expect(store.summary.organizedPhotos == 5)
        #expect(store.summary.formattedSpaceSaved == "9.0 MB")

        let reloadedStore = CleanupStatsStore(fileURL: fileURL)
        #expect(reloadedStore.sessions.count == 1)
        #expect(reloadedStore.summary.organizedPhotos == 5)
    }

    @Test func cleanupStatsStoreBuildsMonthlySummariesNewestFirst() async throws {
        let fileURL = temporaryStatsURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let store = CleanupStatsStore(fileURL: fileURL)
        store.recordSession(
            deletedPhotos: 1,
            favoritedPhotos: 1,
            organizedPhotos: 2,
            estimatedSpaceSavedMB: 3,
            date: makeDate(year: 2026, month: 5, day: 20, calendar: calendar)
        )
        store.recordSession(
            deletedPhotos: 4,
            favoritedPhotos: 0,
            organizedPhotos: 4,
            estimatedSpaceSavedMB: 12,
            date: makeDate(year: 2026, month: 6, day: 11, calendar: calendar)
        )

        let summaries = store.monthlySummaries
        #expect(summaries.count == 2)
        #expect(summaries[0].monthKey == "2026-06")
        #expect(summaries[0].deletedPhotos == 4)
        #expect(summaries[1].monthKey == "2026-05")
        #expect(summaries[1].organizedPhotos == 2)
    }

    @Test func cleanupStatsStoreSkipsEmptySessionsAndCanClear() async throws {
        let fileURL = temporaryStatsURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = CleanupStatsStore(fileURL: fileURL)
        store.recordSession(deletedPhotos: 0, favoritedPhotos: 0, organizedPhotos: 0, estimatedSpaceSavedMB: 0)
        #expect(store.sessions.isEmpty)

        store.recordSession(deletedPhotos: 1, favoritedPhotos: 0, organizedPhotos: 1, estimatedSpaceSavedMB: 3)
        #expect(store.sessions.count == 1)

        store.clearAll()
        #expect(store.sessions.isEmpty)
    }

    // MARK: - Advanced feature models

    @Test func deviceStorageSnapshotFormatsAndClampsUsage() async throws {
        let snapshot = DeviceStorageSnapshot(
            totalBytes: 256 * 1_073_741_824,
            freeBytes: 64 * 1_073_741_824
        )

        #expect(snapshot.formattedUsed == "192 GB")
        #expect(snapshot.formattedFree == "64.0 GB")
        #expect(snapshot.formattedTotal == "256 GB")
        #expect(snapshot.usedFraction == 0.75)
    }

    @Test func photoDaySummaryProgressClampsToOne() async throws {
        let summary = PhotoDaySummary(
            date: Date(),
            photoCount: 10,
            screenshotCount: 2,
            videoCount: 1,
            reviewedCount: 14,
            estimatedSizeMB: 42
        )

        #expect(summary.progress == 1)
        #expect(summary.formattedEstimatedSize == "42.0 MB")
    }

    @Test func photoPeriodSummaryProgressAndRemainingClamp() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = makeDate(year: 2026, month: 6, day: 1, calendar: calendar)
        let end = makeDate(year: 2026, month: 7, day: 1, calendar: calendar)
        let summary = PhotoPeriodSummary(
            scope: .month,
            intervalStart: start,
            intervalEnd: end,
            assetCount: 10,
            screenshotCount: 2,
            videoCount: 1,
            reviewedCount: 14,
            estimatedSizeMB: 128
        )

        #expect(summary.progress == 1)
        #expect(summary.remainingCount == 0)
        #expect(summary.formattedEstimatedSize == "128.0 MB")
    }

    @Test func advancedTimeScopeDateIntervalsCoverExpectedRanges() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = makeDate(year: 2026, month: 6, day: 11, hour: 12, minute: 0, second: 0, calendar: calendar)

        let day = calendar.dateInterval(for: .day, containing: date)
        #expect(day.start == makeDate(year: 2026, month: 6, day: 11, hour: 0, minute: 0, second: 0, calendar: calendar))
        #expect(day.end == makeDate(year: 2026, month: 6, day: 12, hour: 0, minute: 0, second: 0, calendar: calendar))

        let month = calendar.dateInterval(for: .month, containing: date)
        #expect(month.start == makeDate(year: 2026, month: 6, day: 1, hour: 0, minute: 0, second: 0, calendar: calendar))
        #expect(month.end == makeDate(year: 2026, month: 7, day: 1, hour: 0, minute: 0, second: 0, calendar: calendar))

        let year = calendar.dateInterval(for: .year, containing: date)
        #expect(year.start == makeDate(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0, calendar: calendar))
        #expect(year.end == makeDate(year: 2027, month: 1, day: 1, hour: 0, minute: 0, second: 0, calendar: calendar))
    }

    @Test func appAppearanceExposesExpectedColorSchemes() async throws {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
        #expect(AppAppearance.allCases.map(\.rawValue) == ["system", "light", "dark"])
    }

    @Test func advancedDemoSnapshotIncludesCalendarAndCleanupQueues() async throws {
        let snapshot = AdvancedLibrarySnapshot.demo(
            referenceDate: makeDate(year: 2026, month: 6, day: 11, calendar: Calendar(identifier: .gregorian)),
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(snapshot.stats.totalAssets > 0)
        #expect(snapshot.monthSummaries.isEmpty == false)
        #expect(snapshot.monthSummaries[0].assetCount > 0)
        #expect(snapshot.monthSummaries[0].progress > 0)
        #expect(snapshot.daySummaries.isEmpty == false)
        #expect(snapshot.cleanupQueues.map(\.kind) == AdvancedCleanupKind.allCases)
    }

    // MARK: - AlbumInfo tests

    @Test func albumInfoWithNilAssetCollectionUsesTypeRawValue() async throws {
        for albumType in AlbumType.allCases {
            let album = AlbumInfo(assetCollection: nil, type: albumType)
            #expect(album.id == albumType.rawValue, "id should be type.rawValue for type \(albumType)")
            #expect(album.title == albumType.title, "title should use localized title for type \(albumType)")
            #expect(album.assetCollection == nil)
            #expect(album.type == albumType)
        }
    }

    @Test func albumTypeRestoresLegacyChineseRawValues() async throws {
        #expect(AlbumType.fromStoredValue("全部照片") == .all)
        #expect(AlbumType.fromStoredValue("最近项目") == .recents)
        #expect(AlbumType.fromStoredValue("用户相册") == .userCreated)
        #expect(AlbumType.fromStoredValue("favorites") == .favorites)
    }

    @Test func timeGroupRestoresLegacyChineseIdentifiers() async throws {
        #expect(TimeGroup.fromIdentifier("今天的照片") == .today)
        #expect(TimeGroup.fromIdentifier("本周的照片") == .thisWeek)
        #expect(TimeGroup.fromIdentifier("olderPhotos") == .olderPhotos)
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

    @Test func settingsStatsSummaryUsesPersistedCleanupStats() async throws {
        let fileURL = temporaryStatsURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = CleanupStatsStore(fileURL: fileURL)
        store.recordSession(
            deletedPhotos: 2,
            favoritedPhotos: 1,
            organizedPhotos: 4,
            estimatedSpaceSavedMB: 6
        )

        let dm = DataManager(cleanupStatsStore: store)
        let summary = dm.makeSettingsStatsSummary()

        #expect(summary.deletedAssets == 2)
        #expect(summary.organizedAssets == 4)
        #expect(summary.estimatedSpaceSavedMB == 6)
        #expect(summary.formattedSpaceSaved == "6.0 MB")
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

    @Test func reviewedStateCanBeRestored() async throws {
        guard let asset = fetchFirstAsset() else { return }
        UserDefaults.standard.removeObject(forKey: AppConstants.reviewedAssetIDsKey)
        let dm = DataManager()

        let wasReviewed = dm.markReviewed(asset)
        #expect(wasReviewed == false)
        #expect(dm.isReviewed(asset))

        dm.restoreReviewedState(asset, wasReviewed: wasReviewed)
        #expect(!dm.isReviewed(asset))
    }

    @Test func clearLocalOrganizeDataClearsCandidatesAndReviewedState() async throws {
        guard let asset = fetchFirstAsset() else { return }
        UserDefaults.standard.removeObject(forKey: AppConstants.reviewedAssetIDsKey)
        let dm = DataManager()

        dm.addToDeleteCandidates(asset)
        dm.markReviewed(asset)
        dm.clearLocalOrganizeData()

        #expect(dm.deleteCandidates.isEmpty)
        #expect(dm.favoriteCandidates.isEmpty)
        #expect(!dm.isReviewed(asset))
    }

    @Test func executeBatchOperationsWithEmptyCandidatesCompletesWithoutWork() async throws {
        let dm = DataManager()
        let result: (Bool, Error?) = await withCheckedContinuation { continuation in
            dm.executeBatchOperations { success, error in
                continuation.resume(returning: (success, error))
            }
        }
        #expect(result.0 == true)
        #expect(result.1 == nil)
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

    private func temporaryStatsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("photodel-tests-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

}
