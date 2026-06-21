//
//  PhotoDeleteTests.swift
//  PhotoDeleteTests
//
//  Created by jackie xiao on 11/7/25.
//

import Testing
import Foundation
import Photos
@testable import PhotoDelete

struct PhotoDeleteTests {

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

    @Test func localizedMarkdownHelperReturnsReadableText() async throws {
        let text = L10n.attributedMarkdown("喜欢旅行和探索世界，也用 AI 做一些有趣的小产品。博客和作品集在 [makerjackie.com](https://makerjackie.com)。")
        let plainText = String(text.characters)

        #expect(plainText.contains("makerjackie.com"))
        #expect(!plainText.contains("https://makerjackie.com"))
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

    @Test func swipeGestureMigrationMovesPreviousDefaultToLeftDelete() async throws {
        let suiteName = "PhotoDeleteGestureMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(SwipeGestureAction.keep.rawValue, forKey: AppConstants.leftSwipeActionKey)
        defaults.set(SwipeGestureAction.delete.rawValue, forKey: AppConstants.rightSwipeActionKey)
        defaults.set(SwipeGestureAction.favorite.rawValue, forKey: AppConstants.upSwipeActionKey)

        SwipeGesturePreferences.migrateStoredDefaultsIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: AppConstants.leftSwipeActionKey) == SwipeGestureAction.delete.rawValue)
        #expect(defaults.string(forKey: AppConstants.rightSwipeActionKey) == SwipeGestureAction.keep.rawValue)
        #expect(defaults.string(forKey: AppConstants.upSwipeActionKey) == SwipeGestureAction.favorite.rawValue)
    }

    @Test func swipeGestureMigrationDoesNotOverwriteCustomLayout() async throws {
        let suiteName = "PhotoDeleteGestureMigrationCustom-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(SwipeGestureAction.favorite.rawValue, forKey: AppConstants.leftSwipeActionKey)
        defaults.set(SwipeGestureAction.delete.rawValue, forKey: AppConstants.rightSwipeActionKey)
        defaults.set(SwipeGestureAction.keep.rawValue, forKey: AppConstants.upSwipeActionKey)

        SwipeGesturePreferences.migrateStoredDefaultsIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: AppConstants.leftSwipeActionKey) == SwipeGestureAction.favorite.rawValue)
        #expect(defaults.string(forKey: AppConstants.rightSwipeActionKey) == SwipeGestureAction.delete.rawValue)
        #expect(defaults.string(forKey: AppConstants.upSwipeActionKey) == SwipeGestureAction.keep.rawValue)
    }

    @Test func photoReviewModeNormalizesStoredValues() async throws {
        #expect(PhotoReviewMode.normalized("browser") == .browser)
        #expect(PhotoReviewMode.normalized("card") == .card)
        #expect(PhotoReviewMode.normalized("unknown") == .card)
        #expect(PhotoReviewMode.normalized(nil) == .card)
        #expect(PhotoReviewMode.card.toggled == .browser)
        #expect(PhotoReviewMode.browser.toggled == .card)
    }

    @Test func photoCategoryIncludesLivePhotosQuickEntry() async throws {
        #expect(PhotoCategory.allCases == [.all, .videos, .screenshots, .livePhotos, .favorites])
        #expect(PhotoCategory.livePhotos.icon == "livephoto")
    }

    @Test func appLanguageSupportsMainLocalizedLanguages() async throws {
        #expect(AppLanguage.allCases.map(\.rawValue) == ["system", "zh-Hans", "zh-Hant", "en"])
        #expect(AppLanguage.zhHans.showsSimplifiedChineseOnlyContent)
        #expect(!AppLanguage.zhHant.showsSimplifiedChineseOnlyContent)
        #expect(!AppLanguage.en.showsSimplifiedChineseOnlyContent)
    }

    @Test func supporterEntitlementStateOnlyUnlocksVerifiedOrCachedOffline() async throws {
        #expect(!SupporterEntitlementState.unknown.allowsSupporterAccess)
        #expect(!SupporterEntitlementState.verifying.allowsSupporterAccess)
        #expect(SupporterEntitlementState.verified.allowsSupporterAccess)
        #expect(SupporterEntitlementState.cachedOffline.allowsSupporterAccess)
        #expect(!SupporterEntitlementState.locked.allowsSupporterAccess)
    }

    @Test func supporterEntitlementCacheDoesNotStartAsVerified() async throws {
        let initialState = SupporterEntitlementState.initial(hasCachedEntitlement: true)

        #expect(initialState == .cachedOffline)
        #expect(initialState != .verified)
        #expect(initialState.allowsSupporterAccess)
    }

    @Test func supporterEntitlementStartsLockedWithoutCache() async throws {
        let initialState = SupporterEntitlementState.initial(hasCachedEntitlement: false)

        #expect(initialState == .locked)
        #expect(!initialState.allowsSupporterAccess)
    }

    @Test func supporterEntitlementVerificationStateKeepsCacheExplicit() async throws {
        #expect(SupporterEntitlementState.verificationStarted(hasCachedEntitlement: true) == .cachedOffline)
        #expect(SupporterEntitlementState.verificationStarted(hasCachedEntitlement: false) == .verifying)
    }

    @MainActor
    @Test func supporterTrialDoesNotStartAutomaticallyForNewUsers() async throws {
        let suiteName = "PhotoDeleteSupporterTrial-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let manager = PurchaseManager(
            userDefaults: defaults,
            nowProvider: { now },
            startsStoreKitTasks: false
        )

        #expect(manager.supporterTrialStartDate == nil)
        #expect(defaults.object(forKey: AppConstants.supporterTrialStartDateKey) == nil)
        #expect(!manager.hasPaidSupporterAccess)
        #expect(!manager.isUsingTrialSupporterAccess)
        #expect(!manager.isSupporter)
        #expect(manager.canStartSupporterTrial)
    }

    @MainActor
    @Test func supporterTrialStartsWhenUserChoosesTrial() async throws {
        let suiteName = "PhotoDeleteSupporterTrialStart-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let manager = PurchaseManager(
            userDefaults: defaults,
            nowProvider: { now },
            startsStoreKitTasks: false
        )

        manager.startSupporterTrial()

        #expect(manager.supporterTrialStartDate == now)
        #expect(defaults.object(forKey: AppConstants.supporterTrialStartDateKey) as? Date == now)
        #expect(!manager.hasPaidSupporterAccess)
        #expect(manager.isUsingTrialSupporterAccess)
        #expect(manager.isSupporter)
        #expect(manager.supporterTrialDaysRemaining == 3)
        #expect(!manager.canStartSupporterTrial)
    }

    @MainActor
    @Test func supporterTrialExpiresAfterThreeDays() async throws {
        let suiteName = "PhotoDeleteSupporterTrialExpired-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(startDate, forKey: AppConstants.supporterTrialStartDateKey)

        let afterTrial = startDate.addingTimeInterval((3 * 24 * 60 * 60) + 1)
        let manager = PurchaseManager(
            userDefaults: defaults,
            nowProvider: { afterTrial },
            startsStoreKitTasks: false
        )

        #expect(!manager.hasPaidSupporterAccess)
        #expect(!manager.isUsingTrialSupporterAccess)
        #expect(!manager.isSupporter)
        #expect(manager.isSupporterTrialExpired)
        #expect(manager.supporterTrialDaysRemaining == 0)
        #expect(!manager.canStartSupporterTrial)
    }

    @MainActor
    @Test func cachedPaidSupporterDoesNotStartTrial() async throws {
        let suiteName = "PhotoDeletePaidSupporterTrial-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: AppConstants.supporterEntitlementKey)

        let manager = PurchaseManager(
            userDefaults: defaults,
            nowProvider: { Date(timeIntervalSince1970: 1_800_000_000) },
            startsStoreKitTasks: false
        )

        #expect(manager.hasPaidSupporterAccess)
        #expect(manager.isSupporter)
        #expect(!manager.isUsingTrialSupporterAccess)
        #expect(manager.supporterTrialStartDate == nil)
        #expect(!manager.canStartSupporterTrial)
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

    @Test func cleanupStatsStoreBacksUpCorruptHistoryFile() async throws {
        let directoryURL = temporaryDirectoryURL()
        let fileURL = directoryURL.appendingPathComponent("cleanup-history.json")
        let corruptData = Data("{not valid json".utf8)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try corruptData.write(to: fileURL)

        let store = CleanupStatsStore(fileURL: fileURL)
        let backupURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix("cleanup-history.corrupt-") }

        #expect(store.sessions.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(backupURLs.count == 1)
        #expect((try? Data(contentsOf: backupURLs[0])) == corruptData)
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

    @Test func cleanupStatsStoreReturnsNewAchievementsForReachedMilestones() async throws {
        let fileURL = temporaryStatsURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = CleanupStatsStore(fileURL: fileURL)
        let achievements = store.recordSession(
            deletedPhotos: 10,
            favoritedPhotos: 0,
            organizedPhotos: 10,
            estimatedSpaceSavedMB: 120
        )
        let achievementIDs = Set(achievements.map(\.id))

        #expect(achievementIDs.contains("first_cleanup"))
        #expect(achievementIDs.contains("delete_10"))
        #expect(achievementIDs.contains("save_100mb"))
    }

    @Test func cleanupStatsStoreComputesConsecutiveCleanupStreaks() async throws {
        let fileURL = temporaryStatsURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let store = CleanupStatsStore(fileURL: fileURL)
        store.recordSession(
            deletedPhotos: 1,
            favoritedPhotos: 0,
            organizedPhotos: 1,
            estimatedSpaceSavedMB: 1,
            date: makeDate(year: 2026, month: 6, day: 10, calendar: calendar)
        )
        store.recordSession(
            deletedPhotos: 1,
            favoritedPhotos: 0,
            organizedPhotos: 1,
            estimatedSpaceSavedMB: 1,
            date: makeDate(year: 2026, month: 6, day: 11, calendar: calendar)
        )
        let achievements = store.recordSession(
            deletedPhotos: 1,
            favoritedPhotos: 0,
            organizedPhotos: 1,
            estimatedSpaceSavedMB: 1,
            date: makeDate(year: 2026, month: 6, day: 12, calendar: calendar)
        )

        #expect(store.streakDays(referenceDate: makeDate(year: 2026, month: 6, day: 12, calendar: calendar), calendar: calendar) == 3)
        #expect(achievements.map(\.id).contains("streak_3"))
    }

    @Test func cleanupAchievementEvaluatorReportsAllProgress() async throws {
        let summary = CleanupStatsSummary(
            sessions: 1,
            deletedPhotos: 8,
            favoritedPhotos: 0,
            organizedPhotos: 8,
            estimatedSpaceSavedMB: 80
        )

        let progress = CleanupAchievementEvaluator.allProgress(summary: summary, streakDays: 2)
        let firstCleanup = try #require(progress.first { $0.achievement.id == "first_cleanup" })
        let delete10 = try #require(progress.first { $0.achievement.id == "delete_10" })

        #expect(progress.count == 8)
        #expect(firstCleanup.isUnlocked)
        #expect(delete10.progress == 0.8)
        #expect(delete10.remainingValue == 2)
    }

    @Test func cleanupAchievementEvaluatorReturnsClosestLockedGoals() async throws {
        let summary = CleanupStatsSummary(
            sessions: 1,
            deletedPhotos: 8,
            favoritedPhotos: 0,
            organizedPhotos: 8,
            estimatedSpaceSavedMB: 80
        )

        let closeProgress = CleanupAchievementEvaluator.closeProgress(
            summary: summary,
            streakDays: 2,
            limit: 3
        )

        #expect(closeProgress.map(\.achievement.id) == ["delete_10", "save_100mb", "streak_3"])
        #expect(closeProgress.allSatisfy { !$0.isUnlocked })
    }

    // MARK: - VideoCompressionHistoryStore tests

    @Test func videoCompressionHistoryStoreRecordsAndPersistsSessions() async throws {
        let fileURL = temporaryStatsURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = VideoCompressionHistoryStore(fileURL: fileURL)
        let date = makeDate(year: 2026, month: 6, day: 15, calendar: Calendar(identifier: .gregorian))
        let item = VideoCompressionSessionItem(
            originalAssetIdentifier: "original-video",
            createdAssetIdentifier: "compressed-copy",
            originalSizeMB: 70,
            compressedSizeMB: 42
        )
        store.recordSession(
            videoCount: 2,
            failedCount: 1,
            originalSizeMB: 100,
            compressedSizeMB: 62,
            date: date,
            items: [item]
        )

        #expect(store.sessions.count == 1)
        #expect(store.summary.videoCount == 2)
        #expect(store.summary.failedCount == 1)
        #expect(store.summary.savedSizeMB == 38)
        #expect(store.sessions[0].formattedSavedSize == "38.0 MB")
        #expect(store.sessions[0].items == [item])

        let reloadedStore = VideoCompressionHistoryStore(fileURL: fileURL)
        #expect(reloadedStore.sessions.count == 1)
        #expect(reloadedStore.summary.compressedSizeMB == 62)
        #expect(reloadedStore.sessions[0].items.first?.createdAssetIdentifier == "compressed-copy")
    }

    @Test func dataManagerRecordsVideoCompressionHistoryAndUpdatesRevision() async throws {
        let statsURL = temporaryStatsURL()
        let historyURL = temporaryStatsURL()
        defer {
            try? FileManager.default.removeItem(at: statsURL)
            try? FileManager.default.removeItem(at: historyURL)
        }

        let historyStore = VideoCompressionHistoryStore(fileURL: historyURL)
        let dm = DataManager(
            cleanupStatsStore: CleanupStatsStore(fileURL: statsURL),
            videoCompressionHistoryStore: historyStore
        )
        let initialRevision = dm.videoCompressionHistoryRevision

        dm.recordVideoCompressionSession(
            videoCount: 1,
            failedCount: 0,
            originalSizeMB: 40,
            compressedSizeMB: 22
        )

        #expect(dm.videoCompressionHistoryRevision != initialRevision)
        #expect(historyStore.sessions.count == 1)
        #expect(historyStore.summary.savedSizeMB == 18)
    }

    @Test func videoCompressionResolutionDownscalesWithoutUpscaling() async throws {
        let fourK = CGSize(width: 3_840, height: 2_160)
        let fullHD = CGSize(width: 1_920, height: 1_080)

        #expect(VideoCompressionResolution.original.targetDisplaySize(for: fourK) == fourK)
        #expect(VideoCompressionResolution.automatic.targetDisplaySize(for: fourK) == fullHD)
        #expect(VideoCompressionResolution.p1080.targetDisplaySize(for: fourK) == fullHD)
        #expect(VideoCompressionResolution.p720.targetDisplaySize(for: fourK) == CGSize(width: 1_280, height: 720))
        #expect(VideoCompressionResolution.automatic.targetDisplaySize(for: fullHD) == fullHD)
        #expect(VideoCompressionResolution.p1080.targetDisplaySize(for: CGSize(width: 1_280, height: 720)) == CGSize(width: 1_280, height: 720))
    }

    @Test func videoCompressionQualityRatiosAreOrdered() async throws {
        #expect(VideoCompressionQuality.high.targetVideoBitrateMultiplier > VideoCompressionQuality.balanced.targetVideoBitrateMultiplier)
        #expect(VideoCompressionQuality.balanced.targetVideoBitrateMultiplier > VideoCompressionQuality.spaceSaving.targetVideoBitrateMultiplier)
        #expect(VideoCompressionQuality.high.estimatedSavingsRatio < VideoCompressionQuality.balanced.estimatedSavingsRatio)
        #expect(VideoCompressionQuality.balanced.estimatedSavingsRatio < VideoCompressionQuality.spaceSaving.estimatedSavingsRatio)
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

    @Test func defaultPhotoDeleteThemeIsSage() async throws {
        #expect(PhotoDeleteTheme.defaultTheme == .sage)
    }

    @Test func appLanguageIncludesTraditionalChinese() async throws {
        #expect(AppLanguage.allCases.contains(.zhHant))
        #expect(AppLanguage.zhHant.rawValue == "zh-Hant")
    }

    @Test func appDateFormatterUsesRequestedLocale() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = makeDate(year: 2026, month: 6, day: 11, calendar: calendar)

        let englishMonth = AppDateFormatter.string(
            from: date,
            template: "MMM",
            locale: Locale(identifier: "en")
        )
        let traditionalMonth = AppDateFormatter.string(
            from: date,
            template: "MMM",
            locale: Locale(identifier: "zh-Hant")
        )

        #expect(englishMonth.localizedCaseInsensitiveContains("jun"))
        #expect(!englishMonth.contains("月"))
        #expect(traditionalMonth.contains("6"))
        #expect(traditionalMonth.contains("月"))
    }

    @Test func homeLibraryStateDoesNotShowEmptyBeforeInitialLoadCompletes() async throws {
        #expect(HomeLibraryContentState.resolve(
            hasPhotoLibraryAccess: true,
            isPreparingLibrary: false,
            isLoadingPhotoLibrary: false,
            hasLoadedPhotoLibrary: false,
            totalPhotosCount: 0
        ) == .preparing)

        #expect(HomeLibraryContentState.resolve(
            hasPhotoLibraryAccess: true,
            isPreparingLibrary: false,
            isLoadingPhotoLibrary: true,
            hasLoadedPhotoLibrary: false,
            totalPhotosCount: 0
        ) == .preparing)
    }

    @Test func homeLibraryStateOnlyShowsEmptyAfterLoadedEmptyLibrary() async throws {
        #expect(HomeLibraryContentState.resolve(
            hasPhotoLibraryAccess: true,
            isPreparingLibrary: false,
            isLoadingPhotoLibrary: false,
            hasLoadedPhotoLibrary: true,
            totalPhotosCount: 0
        ) == .empty)

        #expect(HomeLibraryContentState.resolve(
            hasPhotoLibraryAccess: true,
            isPreparingLibrary: false,
            isLoadingPhotoLibrary: true,
            hasLoadedPhotoLibrary: true,
            totalPhotosCount: 12
        ) == .available)

        #expect(HomeLibraryContentState.resolve(
            hasPhotoLibraryAccess: false,
            isPreparingLibrary: false,
            isLoadingPhotoLibrary: false,
            hasLoadedPhotoLibrary: false,
            totalPhotosCount: 0
        ) == .needsAuthorization)
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
        #expect(AlbumType.fromStoredValue("实况照片") == .livePhotos)
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

    @Test func albumNavigationDestinationUsesStableAlbumIdentifier() async throws {
        let first = AlbumInfo(id: "album-1", title: "旅行", assetCollection: nil, type: .userCreated, photosCount: 8)
        let renamed = AlbumInfo(id: "album-1", title: "旅行精选", assetCollection: nil, type: .userCreated, photosCount: 12)

        let firstDestination = AlbumNavigationDestination.swipeAlbum(first)
        let renamedDestination = AlbumNavigationDestination.swipeAlbum(renamed)

        #expect(firstDestination == renamedDestination)
        #expect(Set([firstDestination, renamedDestination]).count == 1)
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

    @Test func candidateIdentifiersKeepUnselectedItemsAfterPartialCommit() async throws {
        let remaining = DataManager.remainingCandidateIdentifiers(
            deleteIDs: ["delete-a", "delete-b"],
            favoriteIDs: ["favorite-a", "favorite-b"],
            committedDeleteIDs: ["delete-a"],
            committedFavoriteIDs: ["favorite-a"]
        )

        #expect(remaining.deleteIDs == ["delete-b"])
        #expect(remaining.favoriteIDs == ["favorite-b"])
    }

    @Test func candidateIdentifiersDropFavoriteWhenAssetWasDeleted() async throws {
        let remaining = DataManager.remainingCandidateIdentifiers(
            deleteIDs: ["asset-a"],
            favoriteIDs: ["asset-a", "asset-b"],
            committedDeleteIDs: ["asset-a"],
            committedFavoriteIDs: []
        )

        #expect(remaining.deleteIDs.isEmpty)
        #expect(remaining.favoriteIDs == ["asset-b"])
    }

    @Test func candidateIdentifiersPruneUnavailableAssets() async throws {
        let pruned = DataManager.candidateIdentifiers(
            deleteIDs: ["asset-a", "asset-b"],
            favoriteIDs: ["asset-c", "asset-d"],
            keepingValidIDs: ["asset-b", "asset-d", "asset-e"]
        )

        #expect(pruned.deleteIDs == ["asset-b"])
        #expect(pruned.favoriteIDs == ["asset-d"])
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

    // MARK: - Review discovery tests

    @Test func randomReviewPlannerExcludesReviewedAndDeduplicates() async throws {
        let planned = PhotoRandomReviewPlanner.plannedIdentifiers(
            from: ["a", "b", "a", "c", "d"],
            excluding: ["b"],
            seed: "seed",
            limit: 10
        )

        #expect(Set(planned) == ["a", "c", "d"])
        #expect(planned.count == 3)
        #expect(!planned.contains("b"))
    }

    @Test func randomReviewPlannerIsStableForSameSeed() async throws {
        let identifiers = ["a", "b", "c", "d", "e"]
        let first = PhotoRandomReviewPlanner.plannedIdentifiers(
            from: identifiers,
            excluding: [],
            seed: "stable",
            limit: 3
        )
        let second = PhotoRandomReviewPlanner.plannedIdentifiers(
            from: identifiers,
            excluding: [],
            seed: "stable",
            limit: 3
        )

        #expect(first == second)
        #expect(first.count == 3)
    }

    @Test func randomReviewPlannerPrunesExistingSessionToValidIdentifiers() async throws {
        let existing = PhotoRandomReviewPlanner.existingSessionIdentifiers(
            ["a", "missing", "a", "b"],
            keepingValid: ["a", "b"]
        )

        #expect(existing == ["a", "b"])
    }

    @Test func randomReviewSessionStoreRoundTripsAndClearsScope() async throws {
        let suiteName = "PhotoDeleteRandomSession-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PhotoRandomReviewSessionStore.save(
            assetIdentifiers: ["asset-1", "asset-2"],
            scopeID: "random:memories",
            defaults: defaults
        )

        #expect(PhotoRandomReviewSessionStore.load(scopeID: "random:memories", defaults: defaults) == ["asset-1", "asset-2"])
        #expect(PhotoRandomReviewSessionStore.load(scopeID: "random:all", defaults: defaults).isEmpty)

        PhotoRandomReviewSessionStore.clear(scopeID: "random:memories", defaults: defaults)
        #expect(PhotoRandomReviewSessionStore.load(scopeID: "random:memories", defaults: defaults).isEmpty)
    }

    @Test func locationGroupingSeparatesNoLocationAndCountsReviewed() async throws {
        let records = [
            PhotoLocationAssetRecord(identifier: "sh-1", latitude: 31.23, longitude: 121.47, isReviewed: true),
            PhotoLocationAssetRecord(identifier: "sh-2", latitude: 31.24, longitude: 121.48, isReviewed: false),
            PhotoLocationAssetRecord(identifier: "unknown", latitude: nil, longitude: nil, isReviewed: false)
        ]

        let result = PhotoLocationGrouping.buildGroups(from: records)
        let noLocation = try #require(result.groups.first { $0.id == PhotoLocationGrouping.noLocationID })
        let locationGroup = try #require(result.groups.first { !$0.isNoLocationGroup })

        #expect(noLocation.assetCount == 1)
        #expect(noLocation.reviewedCount == 0)
        #expect(locationGroup.assetCount == 2)
        #expect(locationGroup.reviewedCount == 1)
        #expect(Set(result.identifiersByGroupID[locationGroup.id] ?? []) == ["sh-1", "sh-2"])
    }

    @Test func locationGroupingLimitsVisibleLocationBuckets() async throws {
        let records = (0..<8).map { index in
            PhotoLocationAssetRecord(
                identifier: "asset-\(index)",
                latitude: Double(index),
                longitude: Double(index),
                isReviewed: false
            )
        }

        let result = PhotoLocationGrouping.buildGroups(from: records, maximumGroups: 3)
        #expect(result.groups.count == 3)
        #expect(result.groups.allSatisfy { !$0.isNoLocationGroup })
    }

    @Test func memoryCaptionFormatterHandlesUnknownTodayAndPastDates() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = makeDate(year: 2026, month: 6, day: 21, calendar: calendar)
        let threeYearsAgo = makeDate(year: 2023, month: 6, day: 21, calendar: calendar)

        #expect(PhotoMemoryCaptionFormatter.relativeTitle(for: nil, now: now, calendar: calendar) == L10n.string("拍摄时间未知"))
        #expect(PhotoMemoryCaptionFormatter.relativeTitle(for: now, now: now, calendar: calendar) == L10n.string("今天"))
        #expect(PhotoMemoryCaptionFormatter.relativeTitle(for: threeYearsAgo, now: now, calendar: calendar) == String(format: L10n.string("%lld 年前"), Int64(3)))
        #expect(PhotoMemoryCaptionFormatter.dateSubtitle(for: threeYearsAgo) != nil)
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
            .appendingPathComponent("photodelete-tests-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("photodelete-tests-\(UUID().uuidString)", isDirectory: true)
    }

}
