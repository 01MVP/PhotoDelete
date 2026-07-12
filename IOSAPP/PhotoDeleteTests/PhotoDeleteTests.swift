//
//  PhotoDeleteTests.swift
//  PhotoDeleteTests
//
//  Created by jackie xiao on 11/7/25.
//

import Testing
import Foundation
import CoreLocation
import Photos
@testable import PhotoDelete

@Suite(.serialized)
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

    @Test func historicalTodayResolverMatchesPastSameMonthDayOnly() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = makeDate(year: 2026, month: 6, day: 22, calendar: calendar)

        #expect(HistoricalTodayResolver.isHistoricalToday(makeDate(year: 2025, month: 6, day: 22, calendar: calendar), now: now, calendar: calendar))
        #expect(HistoricalTodayResolver.isHistoricalToday(makeDate(year: 2022, month: 6, day: 22, calendar: calendar), now: now, calendar: calendar))
        #expect(!HistoricalTodayResolver.isHistoricalToday(makeDate(year: 2026, month: 6, day: 22, calendar: calendar), now: now, calendar: calendar))
        #expect(!HistoricalTodayResolver.isHistoricalToday(makeDate(year: 2025, month: 6, day: 21, calendar: calendar), now: now, calendar: calendar))
        #expect(!HistoricalTodayResolver.isHistoricalToday(makeDate(year: 2027, month: 6, day: 22, calendar: calendar), now: now, calendar: calendar))
    }

    @Test func historicalTodayResolverHandlesLeapDayStrictly() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let leapDay = makeDate(year: 2028, month: 2, day: 29, calendar: calendar)

        #expect(HistoricalTodayResolver.isHistoricalToday(makeDate(year: 2024, month: 2, day: 29, calendar: calendar), now: leapDay, calendar: calendar))
        #expect(!HistoricalTodayResolver.isHistoricalToday(makeDate(year: 2027, month: 2, day: 28, calendar: calendar), now: leapDay, calendar: calendar))
        #expect(!HistoricalTodayResolver.isHistoricalToday(makeDate(year: 2027, month: 3, day: 1, calendar: calendar), now: leapDay, calendar: calendar))
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
        #expect(SwipeGesturePreset.standard.upAction == .favorite)

        #expect(SwipeGesturePreset.browse.leftAction == .next)
        #expect(SwipeGesturePreset.browse.rightAction == .previous)
        #expect(SwipeGesturePreset.browse.upAction == .delete)

        #expect(SwipeGesturePreset.leftKeepRightDelete.leftAction == .keep)
        #expect(SwipeGesturePreset.leftKeepRightDelete.rightAction == .delete)
        #expect(SwipeGesturePreset.leftKeepRightDelete.upAction == .favorite)
    }

    @Test func swipeGestureActionNormalizationFallsBackForUnknownValues() async throws {
        #expect(SwipeGesturePreferences.normalizedAction("favorite", fallback: .delete) == .favorite)
        #expect(SwipeGesturePreferences.normalizedAction("unknown", fallback: .keep) == .keep)
    }

    @Test func swipeGestureMigrationMovesLegacyDefaultToLeftDelete() async throws {
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
        #expect(defaults.bool(forKey: AppConstants.gestureUpdateNoticePendingKey) == false)
    }

    @Test func swipeGestureMigrationMovesPreviousBrowseDefaultToLeftDelete() async throws {
        let suiteName = "PhotoDeleteGestureMigrationPreviousBrowse-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(SwipeGestureAction.next.rawValue, forKey: AppConstants.leftSwipeActionKey)
        defaults.set(SwipeGestureAction.previous.rawValue, forKey: AppConstants.rightSwipeActionKey)
        defaults.set(SwipeGestureAction.delete.rawValue, forKey: AppConstants.upSwipeActionKey)

        SwipeGesturePreferences.migrateStoredDefaultsIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: AppConstants.leftSwipeActionKey) == SwipeGestureAction.delete.rawValue)
        #expect(defaults.string(forKey: AppConstants.rightSwipeActionKey) == SwipeGestureAction.keep.rawValue)
        #expect(defaults.string(forKey: AppConstants.upSwipeActionKey) == SwipeGestureAction.favorite.rawValue)
        #expect(defaults.bool(forKey: AppConstants.gestureUpdateNoticePendingKey) == false)
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
        #expect(defaults.bool(forKey: AppConstants.gestureUpdateNoticePendingKey) == false)
    }

    @Test func swipeGestureMigrationDoesNotShowNoticeForExistingImplicitLegacyDefault() async throws {
        let suiteName = "PhotoDeleteGestureMigrationImplicit-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: AppConstants.hasCompletedOnboardingKey)

        SwipeGesturePreferences.migrateStoredDefaultsIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: AppConstants.leftSwipeActionKey) == SwipeGestureAction.delete.rawValue)
        #expect(defaults.string(forKey: AppConstants.rightSwipeActionKey) == SwipeGestureAction.keep.rawValue)
        #expect(defaults.string(forKey: AppConstants.upSwipeActionKey) == SwipeGestureAction.favorite.rawValue)
        #expect(defaults.bool(forKey: AppConstants.gestureUpdateNoticePendingKey) == false)
    }

    @Test func swipeGestureMigrationDoesNotShowNoticeForFreshInstall() async throws {
        let suiteName = "PhotoDeleteGestureMigrationFresh-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SwipeGesturePreferences.migrateStoredDefaultsIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: AppConstants.leftSwipeActionKey) == nil)
        #expect(defaults.string(forKey: AppConstants.rightSwipeActionKey) == nil)
        #expect(defaults.string(forKey: AppConstants.upSwipeActionKey) == nil)
        #expect(defaults.bool(forKey: AppConstants.gestureUpdateNoticePendingKey) == false)
    }

    @Test func reviewPlaybackLaunchDefaultsInitializeButDoNotOverrideVideoMute() async throws {
        let suiteName = "PhotoDeletePlaybackDefaults-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ReviewPlaybackPreferences.applyLaunchDefaults(defaults: defaults)
        #expect(defaults.bool(forKey: AppConstants.reviewVideoMutedKey))
        #expect(defaults.object(forKey: AppConstants.reviewLivePhotoAutoPlayKey) != nil)
        #expect(!defaults.bool(forKey: AppConstants.reviewLivePhotoAutoPlayKey))

        defaults.set(false, forKey: AppConstants.reviewVideoMutedKey)
        defaults.set(true, forKey: AppConstants.reviewLivePhotoAutoPlayKey)
        ReviewPlaybackPreferences.applyLaunchDefaults(defaults: defaults)

        #expect(!defaults.bool(forKey: AppConstants.reviewVideoMutedKey))
        #expect(defaults.bool(forKey: AppConstants.reviewLivePhotoAutoPlayKey))
    }

    @Test func livePhotoPlaybackDefaultsKeepMotionOffUnlessEnabled() async throws {
        #expect(!LivePhotoPlaybackDefaultPolicy.initialMotionEnabled(isLivePhoto: false, autoPlayPreference: true))
        #expect(!LivePhotoPlaybackDefaultPolicy.initialMotionEnabled(isLivePhoto: true, autoPlayPreference: false))
        #expect(LivePhotoPlaybackDefaultPolicy.initialMotionEnabled(isLivePhoto: true, autoPlayPreference: true))
        #expect(LivePhotoPlaybackDefaultPolicy.toggledMotionEnabled(current: false))
        #expect(!LivePhotoPlaybackDefaultPolicy.toggledMotionEnabled(current: true))
    }

    @Test func livePhotoPlaybackStartsOncePerAssetUnlessExplicitlyTriggered() async throws {
        var state = LivePhotoPlaybackRequestState()

        let initialPlayback = state.shouldStartPlayback(
            contentIdentifier: "photo-1",
            autoPlay: true,
            playbackTrigger: 0
        )
        let duplicatePlayback = state.shouldStartPlayback(
            contentIdentifier: "photo-1",
            autoPlay: true,
            playbackTrigger: 0
        )
        let explicitReplay = state.shouldStartPlayback(
            contentIdentifier: "photo-1",
            autoPlay: true,
            playbackTrigger: 1
        )
        let duplicateReplay = state.shouldStartPlayback(
            contentIdentifier: "photo-1",
            autoPlay: true,
            playbackTrigger: 1
        )
        let nextPhotoPlayback = state.shouldStartPlayback(
            contentIdentifier: "photo-2",
            autoPlay: true,
            playbackTrigger: 1
        )

        #expect(initialPlayback)
        #expect(!duplicatePlayback)
        #expect(explicitReplay)
        #expect(!duplicateReplay)
        #expect(nextPhotoPlayback)
    }

    @Test func photoAssetMetadataFormatterUsesReadableFallbacks() async throws {
        #expect(PhotoAssetMetadataFormatter.shortCaptureDate(for: nil) == L10n.string("拍摄时间未知"))
        #expect(PhotoAssetMetadataFormatter.detailCaptureDate(for: nil) == L10n.string("未保存拍摄时间"))
        #expect(PhotoAssetMetadataFormatter.locationText(locationTitle: nil, coordinate: nil) == L10n.string("无地点信息"))
        #expect(PhotoAssetMetadataFormatter.optionalLocationText(locationTitle: nil, coordinate: nil) == nil)
        #expect(
            PhotoAssetMetadataFormatter.locationText(
                locationTitle: "31.2304, 121.4737",
                coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
            ) == L10n.string("无地点信息")
        )
        #expect(
            PhotoAssetMetadataFormatter.optionalLocationText(
                locationTitle: "31.2304, 121.4737",
                coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
            ) == nil
        )
        #expect(
            PhotoAssetMetadataFormatter.locationText(
                locationTitle: "上海 · 徐汇",
                coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
            ) == "上海 · 徐汇"
        )
        #expect(
            PhotoAssetMetadataFormatter.optionalLocationText(
                locationTitle: nil,
                coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
            ) == nil
        )
    }

    @Test func photoLocationGroupingOnlyShowsResolvedPlaceNames() async throws {
        let shanghaiID = PhotoLocationGrouping.groupID(latitude: 31.2304, longitude: 121.4737)
        let beijingID = PhotoLocationGrouping.groupID(latitude: 39.9042, longitude: 116.4074)
        let records = [
            PhotoLocationAssetRecord(identifier: "sh-1", latitude: 31.2304, longitude: 121.4737, isReviewed: true),
            PhotoLocationAssetRecord(identifier: "sh-2", latitude: 31.2310, longitude: 121.4730, isReviewed: false),
            PhotoLocationAssetRecord(identifier: "bj-1", latitude: 39.9042, longitude: 116.4074, isReviewed: false),
            PhotoLocationAssetRecord(identifier: "none-1", latitude: nil, longitude: nil, isReviewed: false)
        ]

        let result = PhotoLocationGrouping.buildGroups(
            from: records,
            titleCache: [
                shanghaiID: PhotoLocationResolvedTitle(title: "上海 · 徐汇"),
                beijingID: PhotoLocationResolvedTitle(title: "39.9042, 116.4074")
            ]
        )

        #expect(result.groups.map(\.id) == [shanghaiID])
        #expect(result.groups.first?.title == "上海 · 徐汇")
        #expect(result.groups.first?.reviewedCount == 1)
        #expect(result.identifiersByGroupID[shanghaiID] == ["sh-1", "sh-2"])
        #expect(result.unresolvedCoordinatesByGroupID[beijingID] != nil)
        #expect(result.identifiersByGroupID[PhotoLocationGrouping.noLocationID] == nil)
        #expect(result.locatedAssetCount == 3)
    }

    @Test func photoLocationGroupingMergesDuplicateReadableTitles() async throws {
        let firstID = PhotoLocationGrouping.groupID(latitude: 22.5400, longitude: 113.9400)
        let secondID = PhotoLocationGrouping.groupID(latitude: 22.5900, longitude: 113.9400)
        let thirdID = PhotoLocationGrouping.groupID(latitude: 22.6500, longitude: 113.9900)
        #expect(Set([firstID, secondID, thirdID]).count == 3)

        let records = [
            PhotoLocationAssetRecord(identifier: "sz-1", latitude: 22.5400, longitude: 113.9400, isReviewed: true),
            PhotoLocationAssetRecord(identifier: "sz-2", latitude: 22.5900, longitude: 113.9400, isReviewed: false),
            PhotoLocationAssetRecord(identifier: "sz-3", latitude: 22.6500, longitude: 113.9900, isReviewed: true)
        ]
        let title = "深圳市 · 南山区"

        let result = PhotoLocationGrouping.buildGroups(
            from: records,
            titleCache: [
                firstID: PhotoLocationResolvedTitle(title: title),
                secondID: PhotoLocationResolvedTitle(title: "  \(title)  "),
                thirdID: PhotoLocationResolvedTitle(title: "\n\(title)\t")
            ]
        )

        let group = try #require(result.groups.first)
        #expect(result.groups.count == 1)
        #expect(group.id == firstID)
        #expect(group.title == title)
        #expect(group.assetCount == 3)
        #expect(group.reviewedCount == 2)
        #expect(result.identifiersByGroupID[firstID] == ["sz-1", "sz-2", "sz-3"])
        #expect(result.resolvedGroupIDs == Set([firstID, secondID, thirdID]))
    }

    @Test func photoLocationGroupingCountsAllLocatedAssetsWhenGroupsAreLimited() async throws {
        let records = (0..<5).map { index in
            PhotoLocationAssetRecord(
                identifier: "asset-\(index)",
                latitude: 20 + Double(index) * 0.1,
                longitude: 110,
                isReviewed: false
            )
        }
        let titleCache = Dictionary(
            uniqueKeysWithValues: records.map { record in
                (
                    PhotoLocationGrouping.groupID(latitude: record.latitude, longitude: record.longitude),
                    PhotoLocationResolvedTitle(title: "地点 \(record.identifier)")
                )
            }
        )

        let result = PhotoLocationGrouping.buildGroups(
            from: records,
            maximumGroups: 2,
            titleCache: titleCache
        )

        #expect(result.groups.count == 2)
        #expect(result.groups.reduce(0) { $0 + $1.assetCount } == 2)
        #expect(result.locatedAssetCount == 5)
    }

    @Test func photoLocationDisplayTitlePrefersReadablePlaceFields() async throws {
        #expect(
            PhotoLocationGrouping.displayTitle(
                name: "People's Park",
                locality: "上海",
                subLocality: "黄浦",
                administrativeArea: "上海市",
                country: "中国"
            ) == "上海 · 黄浦"
        )
        #expect(
            PhotoLocationGrouping.displayTitle(
                name: "中国",
                locality: nil,
                subLocality: nil,
                administrativeArea: nil,
                country: "中国"
            ) == "中国"
        )
        #expect(
            PhotoLocationGrouping.displayTitle(
                name: "31.2304, 121.4737",
                locality: nil,
                subLocality: nil,
                administrativeArea: nil,
                country: nil
            ) == nil
        )
    }

    @Test func photoReviewModeNormalizesStoredValues() async throws {
        #expect(PhotoReviewMode.normalized("browser") == .browser)
        #expect(PhotoReviewMode.normalized("card") == .card)
        #expect(PhotoReviewMode.normalized("unknown") == .card)
        #expect(PhotoReviewMode.normalized(nil) == .card)
        #expect(PhotoReviewMode.card.toggled == .browser)
        #expect(PhotoReviewMode.browser.toggled == .card)
    }

    @Test func photoReviewModeSyncRefreshesAnchorWhenEnteringBrowser() async throws {
        #expect(PhotoReviewModeSyncPolicy.shouldRefreshBrowserAnchor(from: .card, to: .browser))
        #expect(!PhotoReviewModeSyncPolicy.shouldRefreshBrowserAnchor(from: .browser, to: .card))
        #expect(!PhotoReviewModeSyncPolicy.shouldRefreshBrowserAnchor(from: .browser, to: .browser))
        #expect(!PhotoReviewModeSyncPolicy.shouldRefreshBrowserAnchor(from: .card, to: .card))
    }

    @Test func photoCategoryIncludesLivePhotosQuickEntry() async throws {
        #expect(PhotoCategory.allCases == [.all, .unclassified, .videos, .screenshots, .livePhotos, .favorites])
        #expect(PhotoCategory.unclassified.rawValue == "未归类照片")
        #expect(PhotoCategory.unclassified.icon == "tray")
        #expect(PhotoCategory.livePhotos.icon == "livephoto")
    }

    @Test func unclassifiedPhotoFilterExcludesAlbumMembersOnly() async throws {
        let allIDs = ["new-photo", "album-photo", "downloaded-photo", "shared-album-photo"]
        let result = UnclassifiedPhotoFilter.unclassifiedIdentifiers(
            allIdentifiers: allIDs,
            albumMemberIdentifiers: ["album-photo", "shared-album-photo"]
        )

        #expect(result == ["new-photo", "downloaded-photo"])
    }

    @Test func albumLoadPolicyRefreshesCachedAlbumsUntilMembershipIsReady() async throws {
        #expect(AlbumLoadNeededPolicy.shouldLoad(
            hasLoadedAlbums: true,
            hasLoadedAlbumMembership: false,
            isFetchingAlbums: false
        ))
        #expect(!AlbumLoadNeededPolicy.shouldLoad(
            hasLoadedAlbums: true,
            hasLoadedAlbumMembership: true,
            isFetchingAlbums: false
        ))
        #expect(!AlbumLoadNeededPolicy.shouldLoad(
            hasLoadedAlbums: false,
            hasLoadedAlbumMembership: false,
            isFetchingAlbums: true
        ))
    }

    @Test func appLanguageSupportsMainLocalizedLanguages() async throws {
        #expect(AppLanguage.allCases.first == .system)
        #expect(AppLanguage.allCases.contains(.en))
        #expect(AppLanguage.allCases.contains(.ja))
        #expect(AppLanguage.allCases.contains(.ar))
        #expect(AppLanguage.allCases.contains(.he))
        #expect(AppLanguage.allCases.contains(.ur))
        #expect(AppLanguage.zhHans.showsSimplifiedChineseOnlyContent)
        #expect(!AppLanguage.zhHant.showsSimplifiedChineseOnlyContent)
        #expect(!AppLanguage.en.showsSimplifiedChineseOnlyContent)
        #expect(AppLanguage.ar.isRightToLeft)
        #expect(AppLanguage.he.isRightToLeft)
        #expect(AppLanguage.ur.isRightToLeft)
        #expect(!AppLanguage.ja.isRightToLeft)
    }

    @Test func appLanguageCoversWorthwhileAppStoreMetadataLocales() async throws {
        #expect(AppLanguage.supportedStoreMetadataLocales.count == 50)
        #expect(AppLanguage.supportedStoreMetadataLocales.contains("en-US"))
        #expect(AppLanguage.supportedStoreMetadataLocales.contains("ar-SA"))
        #expect(AppLanguage.supportedStoreMetadataLocales.contains("he"))
        #expect(AppLanguage.supportedStoreMetadataLocales.contains("ur-PK"))
        #expect(AppLanguage.supportedStoreMetadataLocales.contains("bn-BD"))
        #expect(AppLanguage.supportedStoreMetadataLocales.contains("ta-IN"))
        #expect(AppLanguage.supportedStoreMetadataLocales.contains("zh-Hant"))
    }

    @Test func appStoreReviewURLTargetsPhotoDeleteReviewPage() async throws {
        #expect(AppConstants.appStoreID == "6779493280")
        #expect(AppConstants.appStoreReviewURL.absoluteString.contains(AppConstants.appStoreID))
        #expect(AppConstants.appStoreReviewURL.absoluteString.contains("action=write-review"))
        #expect(AppConstants.appStoreProductURL.absoluteString.contains(AppConstants.appStoreID))
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
    @Test func supporterPlanIncludesImageCompression() async throws {
        let features = SupporterPlanComparisonCard.features

        #expect(AppConstants.isImageCompressionVisible)
        #expect(features.contains { $0.titleID == .imageCompression && $0.free == .notIncluded && $0.supporter == .included })
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

    @MainActor
    @Test func paidSupporterAccessOverridesExistingTrialState() async throws {
        let suiteName = "PhotoDeleteRedeemedSupporterTrial-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(true, forKey: AppConstants.supporterEntitlementKey)
        defaults.set(now.addingTimeInterval(-86_400), forKey: AppConstants.supporterTrialStartDateKey)

        let manager = PurchaseManager(
            userDefaults: defaults,
            nowProvider: { now },
            startsStoreKitTasks: false
        )

        #expect(manager.hasPaidSupporterAccess)
        #expect(manager.isSupporter)
        #expect(!manager.isUsingTrialSupporterAccess)
        #expect(!manager.isSupporterTrialActive)
        #expect(manager.supporterTrialStartDate == nil)
        #expect(defaults.object(forKey: AppConstants.supporterTrialStartDateKey) == nil)
        #expect(manager.supporterTrialStatusText == nil)
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

        #expect(progress.count == 14)
        #expect(firstCleanup.isUnlocked)
        #expect(delete10.progress == 0.8)
        #expect(delete10.remainingValue == 2)
    }

    @MainActor
    @Test func cachedModelTitlesFollowCurrentAppLanguage() async throws {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: AppConstants.appLanguageKey)
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: AppConstants.appLanguageKey)
            } else {
                defaults.removeObject(forKey: AppConstants.appLanguageKey)
            }
        }

        let summary = CleanupStatsSummary(
            sessions: 1,
            deletedPhotos: 0,
            favoritedPhotos: 0,
            organizedPhotos: 1,
            estimatedSpaceSavedMB: 0
        )

        let achievement = try #require(
            CleanupAchievementEvaluator
                .allProgress(summary: summary, streakDays: 0)
                .first { $0.achievement.id == "first_cleanup" }?
                .achievement
        )

        defaults.set(AppLanguage.zhHans.rawValue, forKey: AppConstants.appLanguageKey)
        #expect(achievement.title == "第一次清理")
        #expect(achievement.subtitle == "完成第一轮照片整理")
        #expect(SwipeGesturePreset.standard.title == "左删右留")
        #expect(SwipeGesturePreset.standard.subtitle == "左滑删除，右滑保留，上滑收藏")
        #expect(SwipeGesturePreset.leftKeepRightDelete.title == "左留右删")
        #expect(SwipeGesturePreset.leftKeepRightDelete.subtitle == "左滑保留，右滑删除，上滑收藏")
        #expect(AdvancedCleanupKind.similarPhotos.title == "相似照片")
        #expect(PhotoCategory.unclassified.title == "未归类照片")
        #expect(L10n.string("保留首张") == "保留首张")
        #expect(String(format: L10n.string("%lld 张相近候选"), Int64(3)) == "3 张相近候选")

        defaults.set(AppLanguage.en.rawValue, forKey: AppConstants.appLanguageKey)
        #expect(achievement.title == "First Cleanup")
        #expect(achievement.subtitle == "Complete your first photo cleanup")
        #expect(SwipeGesturePreset.standard.title == "Delete left, keep right")
        #expect(SwipeGesturePreset.standard.subtitle == "Swipe left to delete, right to keep, up to favorite")
        #expect(SwipeGesturePreset.leftKeepRightDelete.title == "Keep left, delete right")
        #expect(SwipeGesturePreset.leftKeepRightDelete.subtitle == "Swipe left to keep, right to delete, up to favorite")
        #expect(AdvancedCleanupKind.similarPhotos.title == "Similar Photos")
        #expect(PhotoCategory.unclassified.title == "Unfiled Photos")
        #expect(L10n.string("保留首张") == "Keep First")
        #expect(String(format: L10n.string("%lld 张相近候选"), Int64(3)) == "3 similar candidates")
    }

    @MainActor
    @Test func albumCleanupAndDownSwipeHintsAreLocalizedForVisibleLanguages() async throws {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: AppConstants.appLanguageKey)
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: AppConstants.appLanguageKey)
            } else {
                defaults.removeObject(forKey: AppConstants.appLanguageKey)
            }
        }

        let localizedExpectations: [(AppLanguage, [String: String])] = [
            (.ar, [
                "%lld 个相册删除失败，请稍后再试": "تعذر حذف %lld ألبومًا. حاول مرة أخرى لاحقًا.",
                "下滑动作": "السحب للأسفل",
                "下滑可移出当前相册，不会删除照片": "اسحب للأسفل للإزالة من هذا الألبوم دون حذف الصورة",
                "下滑移出相册，不删除照片": "اسحب للأسفل للإزالة من الألبوم، وليس الحذف",
                "只会删除空相册，不会删除任何照片。": "سيتم حذف الألبومات الفارغة فقط. لن يتم حذف أي صور.",
                "删除 %lld 个空相册": "حذف %lld ألبومًا فارغًا",
                "删除空相册": "حذف الألبومات الفارغة",
                "发现 %lld 个空相册": "تم العثور على %lld ألبومًا فارغًا",
                "普通整理": "مراجعة عادية",
                "正在删除 %lld/%lld": "جارٍ الحذف %lld/%lld",
                "没有空相册": "لا توجد ألبومات فارغة",
                "相册操作": "إجراءات الألبوم",
                "移出相册，不删除照片": "إزالة من الألبوم، وليس حذفًا"
            ]),
            (.de, [
                "%lld 个相册删除失败，请稍后再试": "%lld Alben konnten nicht gelöscht werden. Versuche es später erneut.",
                "下滑动作": "Nach unten wischen",
                "下滑可移出当前相册，不会删除照片": "Wische nach unten, um aus diesem Album zu entfernen, ohne das Foto zu löschen",
                "下滑移出相册，不删除照片": "Nach unten wischen: aus Album entfernen, nicht löschen",
                "只会删除空相册，不会删除任何照片。": "Es werden nur leere Alben gelöscht. Keine Fotos werden gelöscht.",
                "删除 %lld 个空相册": "%lld leere Alben löschen",
                "删除空相册": "Leere Alben löschen",
                "发现 %lld 个空相册": "%lld leere Alben gefunden",
                "普通整理": "Normale Durchsicht",
                "正在删除 %lld/%lld": "Löschen %lld/%lld",
                "没有空相册": "Keine leeren Alben",
                "相册操作": "Albumaktionen",
                "移出相册，不删除照片": "Aus Album entfernen, nicht löschen"
            ]),
            (.ja, [
                "%lld 个相册删除失败，请稍后再试": "%lld個のアルバムを削除できませんでした。あとでもう一度お試しください。",
                "下滑动作": "下スワイプ",
                "下滑可移出当前相册，不会删除照片": "下にスワイプすると、このアルバムから外せます。写真は削除されません",
                "下滑移出相册，不删除照片": "下スワイプでアルバムから外す（削除しません）",
                "只会删除空相册，不会删除任何照片。": "空のアルバムだけを削除します。写真は削除されません。",
                "删除 %lld 个空相册": "%lld個の空のアルバムを削除",
                "删除空相册": "空のアルバムを削除",
                "发现 %lld 个空相册": "%lld個の空のアルバムが見つかりました",
                "普通整理": "通常の整理",
                "正在删除 %lld/%lld": "削除中 %lld/%lld",
                "没有空相册": "空のアルバムはありません",
                "相册操作": "アルバム操作",
                "移出相册，不删除照片": "アルバムから外す（削除しません）"
            ])
        ]

        for (language, expectations) in localizedExpectations {
            defaults.set(language.rawValue, forKey: AppConstants.appLanguageKey)
            for (key, expected) in expectations {
                #expect(L10n.key(key) == expected)
            }
        }
    }

    @Test func similarPhotoKeepFirstSelectionTogglesRecommendedAssets() async throws {
        let groupAssetIDs = makeAssetIDs(4)
        let firstTapSelection = AdvancedSimilarPhotoRecommendedSelection.toggledSelection(
            current: [],
            groupAssetIDs: groupAssetIDs
        )

        #expect(firstTapSelection == Set(groupAssetIDs.dropFirst()))

        let secondTapSelection = AdvancedSimilarPhotoRecommendedSelection.toggledSelection(
            current: firstTapSelection,
            groupAssetIDs: groupAssetIDs
        )

        #expect(secondTapSelection.isEmpty)

        let mixedSelection = AdvancedSimilarPhotoRecommendedSelection.toggledSelection(
            current: ["other-asset", groupAssetIDs[1]],
            groupAssetIDs: groupAssetIDs
        )

        #expect(mixedSelection == Set(["other-asset"] + Array(groupAssetIDs.dropFirst())))
    }

    @Test func cleanupAchievementEvaluatorIncludesExpandedSpaceMilestones() async throws {
        let summary = CleanupStatsSummary(
            sessions: 1,
            deletedPhotos: 0,
            favoritedPhotos: 0,
            organizedPhotos: 1,
            estimatedSpaceSavedMB: 100_000
        )

        let progress = CleanupAchievementEvaluator.allProgress(summary: summary, streakDays: 0)
        let spaceProgress = progress.filter { $0.achievement.category == .space }
        let spaceIDs = Set(spaceProgress.map(\.achievement.id))

        #expect(spaceIDs == ["save_100mb", "save_1gb", "save_10gb", "save_100gb"])
        #expect(spaceProgress.allSatisfy { progress in progress.isUnlocked })
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
        #expect(store.sessions[0].items.first?.isOriginalDeleted == false)

        let deletedAt = makeDate(year: 2026, month: 6, day: 16, calendar: Calendar(identifier: .gregorian))
        #expect(store.markOriginalsDeleted(assetIdentifiers: ["original-video"], date: deletedAt))
        #expect(store.sessions[0].items.first?.originalDeletedAt == deletedAt)
        #expect(!store.markOriginalsDeleted(assetIdentifiers: ["original-video"], date: deletedAt))

        let reloadedStore = VideoCompressionHistoryStore(fileURL: fileURL)
        #expect(reloadedStore.sessions.count == 1)
        #expect(reloadedStore.summary.compressedSizeMB == 62)
        #expect(reloadedStore.sessions[0].items.first?.createdAssetIdentifier == "compressed-copy")
        #expect(reloadedStore.sessions[0].items.first?.originalDeletedAt == deletedAt)
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

    // MARK: - ImageCompressionHistoryStore tests

    @Test func imageCompressionHistoryStoreRecordsAndPersistsSessions() async throws {
        let fileURL = temporaryStatsURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = ImageCompressionHistoryStore(fileURL: fileURL)
        let date = makeDate(year: 2026, month: 6, day: 25, calendar: Calendar(identifier: .gregorian))
        let item = ImageCompressionSessionItem(
            originalAssetIdentifier: "original-image",
            createdAssetIdentifier: "compressed-image",
            originalSizeMB: 12,
            compressedSizeMB: 5
        )
        store.recordSession(
            imageCount: 3,
            failedCount: 1,
            originalSizeMB: 30,
            compressedSizeMB: 14,
            date: date,
            items: [item]
        )

        #expect(store.sessions.count == 1)
        #expect(store.summary.imageCount == 3)
        #expect(store.summary.failedCount == 1)
        #expect(store.summary.savedSizeMB == 16)
        #expect(store.sessions[0].formattedSavedSize == "16.0 MB")
        #expect(store.sessions[0].items == [item])
        #expect(store.sessions[0].items.first?.isOriginalDeleted == false)

        let deletedAt = makeDate(year: 2026, month: 6, day: 26, calendar: Calendar(identifier: .gregorian))
        #expect(store.markOriginalsDeleted(assetIdentifiers: ["original-image"], date: deletedAt))
        #expect(store.sessions[0].items.first?.originalDeletedAt == deletedAt)
        #expect(!store.markOriginalsDeleted(assetIdentifiers: ["original-image"], date: deletedAt))

        let reloadedStore = ImageCompressionHistoryStore(fileURL: fileURL)
        #expect(reloadedStore.sessions.count == 1)
        #expect(reloadedStore.summary.compressedSizeMB == 14)
        #expect(reloadedStore.sessions[0].items.first?.createdAssetIdentifier == "compressed-image")
        #expect(reloadedStore.sessions[0].items.first?.originalDeletedAt == deletedAt)
    }

    @Test func dataManagerRecordsImageCompressionHistoryAndUpdatesRevision() async throws {
        let statsURL = temporaryStatsURL()
        let videoHistoryURL = temporaryStatsURL()
        let imageHistoryURL = temporaryStatsURL()
        defer {
            try? FileManager.default.removeItem(at: statsURL)
            try? FileManager.default.removeItem(at: videoHistoryURL)
            try? FileManager.default.removeItem(at: imageHistoryURL)
        }

        let historyStore = ImageCompressionHistoryStore(fileURL: imageHistoryURL)
        let dm = DataManager(
            cleanupStatsStore: CleanupStatsStore(fileURL: statsURL),
            videoCompressionHistoryStore: VideoCompressionHistoryStore(fileURL: videoHistoryURL),
            imageCompressionHistoryStore: historyStore
        )
        let initialRevision = dm.imageCompressionHistoryRevision

        dm.recordImageCompressionSession(
            imageCount: 2,
            failedCount: 0,
            originalSizeMB: 18,
            compressedSizeMB: 9
        )

        #expect(dm.imageCompressionHistoryRevision != initialRevision)
        #expect(historyStore.sessions.count == 1)
        #expect(historyStore.summary.savedSizeMB == 9)
    }

    @Test func imageCompressionSizeDownscalesWithoutUpscaling() async throws {
        let large = CGSize(width: 4_032, height: 3_024)
        let small = CGSize(width: 1_200, height: 900)

        #expect(ImageCompressionSize.original.targetPixelSize(for: large) == large)
        #expect(ImageCompressionSize.automatic.targetPixelSize(for: large) == CGSize(width: 3_200, height: 2_400))
        #expect(ImageCompressionSize.large.targetPixelSize(for: large) == CGSize(width: 2_400, height: 1_800))
        #expect(ImageCompressionSize.medium.targetPixelSize(for: large) == CGSize(width: 1_600, height: 1_200))
        #expect(ImageCompressionSize.automatic.targetPixelSize(for: small) == small)
        #expect(ImageCompressionSize.large.targetPixelSize(for: small) == small)
    }

    @Test func imageCompressionDefaultPlanPreservesMoreDetail() async throws {
        #expect(ImageCompressionPlan.default.quality == .high)
        #expect(ImageCompressionPlan.default.size == .automatic)
    }

    @Test func imageCompressionQualityRatiosAreOrdered() async throws {
        #expect(ImageCompressionQuality.high.jpegQuality > ImageCompressionQuality.balanced.jpegQuality)
        #expect(ImageCompressionQuality.balanced.jpegQuality > ImageCompressionQuality.spaceSaving.jpegQuality)
        #expect(ImageCompressionQuality.high.estimatedSavingsRatio < ImageCompressionQuality.balanced.estimatedSavingsRatio)
        #expect(ImageCompressionQuality.balanced.estimatedSavingsRatio < ImageCompressionQuality.spaceSaving.estimatedSavingsRatio)
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

    @Test func homeLibraryStateAllowsEntryBeforeInitialLoadCompletes() async throws {
        #expect(HomeLibraryContentState.resolve(
            hasPhotoLibraryAccess: true,
            isPreparingLibrary: false,
            isLoadingPhotoLibrary: false,
            hasLoadedPhotoLibrary: false,
            totalPhotosCount: 0
        ) == .available)

        #expect(HomeLibraryContentState.resolve(
            hasPhotoLibraryAccess: true,
            isPreparingLibrary: false,
            isLoadingPhotoLibrary: true,
            hasLoadedPhotoLibrary: false,
            totalPhotosCount: 0
        ) == .available)
    }

    @Test func homeLibraryStateAllowsOrganizingWhileMetadataFinishesLoading() async throws {
        #expect(HomeLibraryContentState.resolve(
            hasPhotoLibraryAccess: true,
            isPreparingLibrary: true,
            isLoadingPhotoLibrary: true,
            hasLoadedPhotoLibrary: true,
            totalPhotosCount: 12
        ) == .available)
    }

    @Test func homeCategoryCountsPreferLoadingTextDuringInitialPreparation() async throws {
        #expect(HomeCategoryCountDetailResolver.shouldShowLibraryLoading(
            category: .all,
            count: 500,
            isPreparingLibrary: true,
            isLoadingPhotoLibrary: true
        ))

        #expect(HomeCategoryCountDetailResolver.shouldShowLibraryLoading(
            category: .unclassified,
            count: 406,
            isPreparingLibrary: true,
            isLoadingPhotoLibrary: true
        ))

        #expect(!HomeCategoryCountDetailResolver.shouldShowLibraryLoading(
            category: .all,
            count: 500,
            isPreparingLibrary: false,
            isLoadingPhotoLibrary: true
        ))
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

    @Test func photoLibraryDisplayCountUsesCachedSnapshotBeforeFullRestore() async throws {
        #expect(PhotoLibraryDisplayCountResolver.count(
            current: 0,
            cached: 128,
            hasLoadedPhotoLibrary: false
        ) == 128)
        #expect(PhotoLibraryDisplayCountResolver.count(
            current: 36,
            cached: 128,
            hasLoadedPhotoLibrary: false
        ) == 128)
        #expect(PhotoLibraryDisplayCountResolver.count(
            current: 36,
            cached: nil,
            hasLoadedPhotoLibrary: false
        ) == 0)
        #expect(PhotoLibraryDisplayCountResolver.count(
            current: 0,
            cached: 128,
            hasLoadedPhotoLibrary: true
        ) == 0)
    }

    @Test func photoLibrarySnapshotRestoreKeepsStaleCacheForBackgroundRefresh() async throws {
        #expect(PhotoLibrarySnapshotRestorePolicy.decision(
            cachedIdentifierCount: 100,
            restoredIdentifierCount: 100,
            currentLibraryCount: 100
        ) == PhotoLibrarySnapshotRestoreDecision(shouldRestore: true, shouldRefreshAfterRestore: false))

        #expect(PhotoLibrarySnapshotRestorePolicy.decision(
            cachedIdentifierCount: 100,
            restoredIdentifierCount: 100,
            currentLibraryCount: 103
        ) == PhotoLibrarySnapshotRestoreDecision(shouldRestore: true, shouldRefreshAfterRestore: true))

        #expect(PhotoLibrarySnapshotRestorePolicy.decision(
            cachedIdentifierCount: 100,
            restoredIdentifierCount: 97,
            currentLibraryCount: 103
        ) == PhotoLibrarySnapshotRestoreDecision(shouldRestore: true, shouldRefreshAfterRestore: true))

        #expect(PhotoLibrarySnapshotRestorePolicy.decision(
            cachedIdentifierCount: 100,
            restoredIdentifierCount: 0,
            currentLibraryCount: 100
        ) == PhotoLibrarySnapshotRestoreDecision(shouldRestore: false, shouldRefreshAfterRestore: true))
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
        #expect(snapshot.cleanupQueues.map(\.kind) == AdvancedCleanupKind.visibleCases)
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

    @Test func emptyAlbumCleanupPlannerOnlyIncludesDeletableEmptyUserAlbums() async throws {
        let albums = [
            AlbumInfo(id: "empty-user", title: "Empty", assetCollection: nil, type: .userCreated, photosCount: 0),
            AlbumInfo(id: "filled-user", title: "Filled", assetCollection: nil, type: .userCreated, photosCount: 2),
            AlbumInfo(id: "empty-system", title: "Favorites", assetCollection: nil, type: .favorites, photosCount: 0),
            AlbumInfo(id: "protected-user", title: "Protected", assetCollection: nil, type: .userCreated, photosCount: 0)
        ]

        let candidates = EmptyAlbumCleanupPlanner.cleanupCandidates(from: albums) { album in
            album.id != "protected-user"
        }

        #expect(candidates.map(\.id) == ["empty-user"])
    }

    @Test func albumsSortedByCustomOrderPrioritizesSavedIDs() async throws {
        let albums = [
            AlbumInfo(id: "album-a", title: "A", assetCollection: nil, type: .userCreated, photosCount: 1),
            AlbumInfo(id: "album-b", title: "B", assetCollection: nil, type: .userCreated, photosCount: 1),
            AlbumInfo(id: "album-c", title: "C", assetCollection: nil, type: .userCreated, photosCount: 1),
            AlbumInfo(id: "album-d", title: "D", assetCollection: nil, type: .userCreated, photosCount: 1)
        ]

        let sorted = DataManager.albumsSortedByCustomOrder(
            albums,
            customOrder: ["album-c", "album-a"]
        )

        #expect(sorted.map(\.id) == ["album-c", "album-a", "album-b", "album-d"])
    }

    @Test func albumsSortedByCustomOrderKeepsOriginalOrderForUnknownIDs() async throws {
        let albums = [
            AlbumInfo(id: "album-a", title: "A", assetCollection: nil, type: .userCreated, photosCount: 1),
            AlbumInfo(id: "album-b", title: "B", assetCollection: nil, type: .userCreated, photosCount: 1),
            AlbumInfo(id: "album-c", title: "C", assetCollection: nil, type: .userCreated, photosCount: 1)
        ]

        let sorted = DataManager.albumsSortedByCustomOrder(
            albums,
            customOrder: ["missing-album", "album-c"]
        )

        #expect(sorted.map(\.id) == ["album-c", "album-a", "album-b"])
    }

    @Test func customAlbumOrderByPrependingMovesCreatedAlbumToFront() async throws {
        #expect(
            DataManager.customAlbumOrderByPrepending(
                "album-new",
                to: ["album-a", "album-b", "album-c"]
            ) == ["album-new", "album-a", "album-b", "album-c"]
        )
        #expect(
            DataManager.customAlbumOrderByPrepending(
                "album-b",
                to: ["album-a", "album-b", "album-c"]
            ) == ["album-b", "album-a", "album-c"]
        )
    }

    @Test func decodeCustomAlbumOrderFallsBackForInvalidData() async throws {
        #expect(DataManager.decodeCustomAlbumOrder(nil).isEmpty)
        #expect(DataManager.decodeCustomAlbumOrder("not-json").isEmpty)
        #expect(DataManager.decodeCustomAlbumOrder("[\"album-b\",\"album-a\"]") == ["album-b", "album-a"])
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

    private func clearPendingCandidateDefaults() {
        UserDefaults.standard.removeObject(forKey: AppConstants.pendingDeleteCandidateIDsKey)
        UserDefaults.standard.removeObject(forKey: AppConstants.pendingFavoriteCandidateIDsKey)
    }

    private func storedPendingCandidateIDs(for key: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    @Test func addToDeleteCandidatesRemovesFromFavorites() async throws {
        guard let asset = fetchFirstAsset() else { return }
        clearPendingCandidateDefaults()
        defer { clearPendingCandidateDefaults() }
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
        clearPendingCandidateDefaults()
        defer { clearPendingCandidateDefaults() }
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
        clearPendingCandidateDefaults()
        defer { clearPendingCandidateDefaults() }
        let dm = DataManager()

        dm.addToDeleteCandidates(asset)
        dm.addToFavoriteCandidates(asset)
        dm.cancelAllOperations()
        #expect(dm.deleteCandidates.isEmpty)
        #expect(dm.favoriteCandidates.isEmpty)
    }

    @Test func pendingCandidatesPersistAndClearLocalIdentifiers() async throws {
        guard let asset = fetchFirstAsset() else { return }
        let suiteName = "PhotoDeleteTests.pendingCandidates.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let dm = DataManager(userDefaults: defaults)

        dm.addToDeleteCandidates(asset)
        try await Task.sleep(for: .milliseconds(700))
        #expect(storedPendingCandidateIDs(for: AppConstants.pendingDeleteCandidateIDsKey, defaults: defaults) == [asset.localIdentifier])
        #expect(storedPendingCandidateIDs(for: AppConstants.pendingFavoriteCandidateIDsKey, defaults: defaults).isEmpty)

        dm.addToFavoriteCandidates(asset)
        try await Task.sleep(for: .milliseconds(700))
        #expect(storedPendingCandidateIDs(for: AppConstants.pendingDeleteCandidateIDsKey, defaults: defaults).isEmpty)
        #expect(storedPendingCandidateIDs(for: AppConstants.pendingFavoriteCandidateIDsKey, defaults: defaults) == [asset.localIdentifier])

        dm.cancelAllOperations()
        try await Task.sleep(for: .milliseconds(50))
        #expect(storedPendingCandidateIDs(for: AppConstants.pendingDeleteCandidateIDsKey, defaults: defaults).isEmpty)
        #expect(storedPendingCandidateIDs(for: AppConstants.pendingFavoriteCandidateIDsKey, defaults: defaults).isEmpty)
    }

    @Test func candidateMembershipAfterAdding() async throws {
        guard let asset = fetchFirstAsset() else { return }
        clearPendingCandidateDefaults()
        defer { clearPendingCandidateDefaults() }
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

    @Test func randomMemoriesPrioritizeUnreviewedOldPhotosAndNeverIncludeRecentPhotos() async throws {
        let oldPhotoIDs = ["old-a", "old-b", "old-reviewed"]
        let resolved = PhotoRandomReviewPlanner.resolvedSessionIdentifiers(
            existingSessionIDs: [],
            candidateIdentifiers: oldPhotoIDs,
            fallbackCandidateIdentifiers: oldPhotoIDs,
            validIdentifiers: Set(oldPhotoIDs),
            excludedIdentifiers: ["old-reviewed"],
            fallbackExcludedIdentifiers: [],
            seed: "old-memories",
            limit: Int.max
        )

        #expect(Set(resolved.prefix(2)) == ["old-a", "old-b"])
        #expect(resolved.last == "old-reviewed")
        #expect(!resolved.contains("recent-photo"))
    }

    @Test func randomMemoryDatePolicyOnlyAcceptsPhotosOlderThanSixMonths() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 UTC
        let sevenMonthsAgo = try #require(calendar.date(byAdding: .month, value: -7, to: now))
        let twoMonthsAgo = try #require(calendar.date(byAdding: .month, value: -2, to: now))

        #expect(PhotoRandomReviewDatePolicy.isOlderMemory(
            creationDate: sevenMonthsAgo,
            now: now,
            calendar: calendar
        ))
        #expect(!PhotoRandomReviewDatePolicy.isOlderMemory(
            creationDate: twoMonthsAgo,
            now: now,
            calendar: calendar
        ))
        #expect(!PhotoRandomReviewDatePolicy.isOlderMemory(
            creationDate: nil,
            now: now,
            calendar: calendar
        ))
    }

    @Test func randomReviewWaitsForTheCompleteLibraryEvenWhenPartialPhotosExist() async throws {
        #expect(PhotoReviewSessionInitializationPolicy.shouldWaitForSource(
            isRandomReview: true,
            hasPhotos: true,
            isWaitingForSourceData: true
        ))
        #expect(!PhotoReviewSessionInitializationPolicy.shouldWaitForSource(
            isRandomReview: true,
            hasPhotos: true,
            isWaitingForSourceData: false
        ))
        #expect(!PhotoReviewSessionInitializationPolicy.shouldWaitForSource(
            isRandomReview: false,
            hasPhotos: true,
            isWaitingForSourceData: true
        ))
    }

    @Test func randomReviewPlannerPrunesExistingSessionToValidIdentifiers() async throws {
        let existing = PhotoRandomReviewPlanner.existingSessionIdentifiers(
            ["a", "missing", "a", "b"],
            keepingValid: ["a", "b"]
        )

        #expect(existing == ["a", "b"])
    }

    @Test func randomReviewPlannerFiltersExistingSessionAndBackfillsToLimit() async throws {
        let resolved = PhotoRandomReviewPlanner.resolvedSessionIdentifiers(
            existingSessionIDs: ["a", "missing", "reviewed", "a", "b"],
            candidateIdentifiers: ["a", "b", "c", "d", "reviewed"],
            validIdentifiers: ["a", "b", "c", "d", "reviewed"],
            excludedIdentifiers: ["reviewed"],
            seed: "fill",
            limit: 4
        )

        #expect(Array(resolved.prefix(2)) == ["a", "b"])
        #expect(resolved.count == 4)
        #expect(Set(resolved).count == resolved.count)
        #expect(!resolved.contains("reviewed"))
        #expect(!resolved.contains("missing"))
    }

    @Test func randomReviewPlannerCanPreserveExistingReviewedSessionItems() async throws {
        let resolved = PhotoRandomReviewPlanner.resolvedSessionIdentifiers(
            existingSessionIDs: ["a", "reviewed", "b"],
            candidateIdentifiers: ["a", "b", "c", "d", "reviewed"],
            validIdentifiers: ["a", "b", "c", "d", "reviewed"],
            excludedIdentifiers: ["reviewed"],
            seed: "preserve",
            limit: 4,
            preservesExistingSessionIdentifiers: true
        )

        #expect(Array(resolved.prefix(3)) == ["a", "reviewed", "b"])
        #expect(resolved.count == 4)
        #expect(Set(resolved).count == resolved.count)
    }

    @Test func randomReviewPlannerRefillsLegacyTenItemSessionToDefaultBatchSize() async throws {
        let identifiers = makeAssetIDs(32)
        let resolved = PhotoRandomReviewPlanner.resolvedSessionIdentifiers(
            existingSessionIDs: Array(identifiers.prefix(10)),
            candidateIdentifiers: identifiers,
            validIdentifiers: Set(identifiers),
            excludedIdentifiers: [],
            seed: "legacy-ten",
            limit: PhotoRandomReviewPlanner.defaultBatchSize
        )

        #expect(resolved.count == PhotoRandomReviewPlanner.defaultBatchSize)
        #expect(Array(resolved.prefix(10)) == Array(identifiers.prefix(10)))
        #expect(Set(resolved).count == resolved.count)
    }

    @Test func randomReviewPlannerContinuousModeDropsReviewedLegacySessionItems() async throws {
        let identifiers = makeAssetIDs(120)
        let reviewed = Set(identifiers.prefix(20))
        let resolved = PhotoRandomReviewPlanner.resolvedSessionIdentifiers(
            existingSessionIDs: Array(identifiers.prefix(30)),
            candidateIdentifiers: identifiers,
            validIdentifiers: Set(identifiers),
            excludedIdentifiers: reviewed,
            seed: "continuous",
            limit: PhotoRandomReviewPlanner.continuousReviewLimit
        )

        #expect(resolved.count == 100)
        #expect(Set(resolved) == Set(identifiers.dropFirst(20)))
        #expect(Set(resolved).isDisjoint(with: reviewed))
        #expect(Array(resolved.prefix(10)) == Array(identifiers.dropFirst(20).prefix(10)))
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

    @Test func randomReviewMigrationClearsOnlyLegacyRandomStateOnce() async throws {
        let suiteName = "PhotoDeleteRandomMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PhotoReviewProgressStore.save(assetIdentifier: "recent-cursor", scopeID: "random:memories", defaults: defaults)
        PhotoReviewProgressStore.save(assetIdentifier: "category-cursor", scopeID: "category:all", defaults: defaults)
        PhotoRandomReviewSessionStore.save(
            assetIdentifiers: ["recent-a", "recent-b"],
            scopeID: "random:memories",
            defaults: defaults
        )

        PhotoRandomReviewMigration.applyIfNeeded(defaults: defaults)

        #expect(PhotoReviewProgressStore.load(scopeID: "random:memories", defaults: defaults) == nil)
        #expect(PhotoReviewProgressStore.load(scopeID: "category:all", defaults: defaults) == "category-cursor")
        #expect(PhotoRandomReviewSessionStore.load(scopeID: "random:memories", defaults: defaults).isEmpty)

        PhotoReviewProgressStore.save(assetIdentifier: "new-random-cursor", scopeID: "random:memories", defaults: defaults)
        PhotoRandomReviewMigration.applyIfNeeded(defaults: defaults)
        #expect(PhotoReviewProgressStore.load(scopeID: "random:memories", defaults: defaults) == "new-random-cursor")
    }

    @Test func reviewProgressStoreRoundTripsAndClearsScope() async throws {
        let suiteName = "PhotoDeleteReviewProgress-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PhotoReviewProgressStore.save(assetIdentifier: "asset-42", scopeID: "category:all", defaults: defaults)

        #expect(PhotoReviewProgressStore.load(scopeID: "category:all", defaults: defaults) == "asset-42")
        #expect(PhotoReviewProgressStore.load(scopeID: "category:videos", defaults: defaults) == nil)

        PhotoReviewProgressStore.clear(scopeID: "category:all", defaults: defaults)
        #expect(PhotoReviewProgressStore.load(scopeID: "category:all", defaults: defaults) == nil)
    }

    @Test func clearLocalOrganizeDataClearsReviewProgress() async throws {
        let suiteName = "PhotoDeleteClearProgress-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PhotoReviewProgressStore.save(assetIdentifier: "asset-42", scopeID: "category:all", defaults: defaults)
        let dm = DataManager(userDefaults: defaults)

        dm.clearLocalOrganizeData()

        #expect(PhotoReviewProgressStore.load(scopeID: "category:all", defaults: defaults) == nil)
    }

    @Test func reviewSessionPaginatorExpandsNearEndAndClampsAtTotal() async throws {
        #expect(PhotoReviewSessionPaginator.initialLoadedCount(totalCount: 500) == 80)
        #expect(PhotoReviewSessionPaginator.expandedLoadedCount(totalCount: 500, currentLoadedCount: 80, currentIndex: 40) == 80)
        #expect(PhotoReviewSessionPaginator.expandedLoadedCount(totalCount: 500, currentLoadedCount: 80, currentIndex: 75) == 160)
        #expect(PhotoReviewSessionPaginator.expandedLoadedCount(totalCount: 120, currentLoadedCount: 80, currentIndex: 75) == 120)
    }

    @Test func browsingDoesNotSkipUnreviewedPhotosAfterReturningToAnEarlierPhoto() async throws {
        let ids = ["photo-1", "photo-2", "photo-3", "photo-4", "photo-5"]
        var reviewed: Set<String> = []

        // Pure browsing from 1 → 4 does not add review decisions.
        #expect(PhotoReviewSessionDecisionPolicy.remainingCount(
            assetIdentifiers: ids,
            reviewedAssetIdentifiers: reviewed
        ) == 5)

        // After returning to photo 2 and classifying it, photo 3 is next.
        reviewed.insert("photo-2")
        let nextIndex = PhotoReviewSessionDecisionPolicy.nextUnreviewedIndex(
            assetIdentifiers: ids,
            reviewedAssetIdentifiers: reviewed,
            after: 1
        )

        #expect(nextIndex == 2)
        #expect(PhotoReviewSessionDecisionPolicy.remainingCount(
            assetIdentifiers: ids,
            reviewedAssetIdentifiers: reviewed
        ) == 4)
    }

    @Test func nextUnreviewedPhotoCanBeFoundBeyondTheLoadedPage() async throws {
        let ids = (0..<100).map { "photo-\($0)" }
        let reviewed = Set(ids.prefix(80))

        let nextIndex = PhotoReviewSessionDecisionPolicy.nextUnreviewedIndex(
            assetIdentifiers: ids,
            reviewedAssetIdentifiers: reviewed,
            after: 70
        )

        #expect(nextIndex == 80)
    }

    @Test func favoriteIsAModifierThatDoesNotAdvanceOrCompleteReview() async throws {
        #expect(!PhotoReviewActionPolicy.shouldAdvance(after: .favorite))
        #expect(!PhotoReviewActionPolicy.shouldAdvance(after: .previous))
        #expect(!PhotoReviewActionPolicy.shouldAdvance(after: .next))
        #expect(PhotoReviewActionPolicy.shouldAdvance(after: .keep))
        #expect(PhotoReviewActionPolicy.shouldAdvance(after: .delete))
    }

    @Test func twoRowBrowserSignatureDetectsMiddleReplacementAndReordering() async throws {
        let original = TwoRowPhotoBrowserView.AssetSignature(identifiers: ["first", "middle", "last"])
        let replaced = TwoRowPhotoBrowserView.AssetSignature(identifiers: ["first", "other", "last"])
        let reordered = TwoRowPhotoBrowserView.AssetSignature(identifiers: ["first", "last", "middle"])

        #expect(original != replaced)
        #expect(original != reordered)
    }

    @Test func reviewSessionInitialTargetPrioritizesNewPhotosBeforeSavedProgress() async throws {
        let ids = ["new-2", "new-1", "reviewed-0", "saved-70", "unreviewed-71"]
        let reviewed: Set<String> = ["reviewed-0", "saved-70"]

        let index = PhotoReviewSessionPaginator.initialTargetIndex(
            assetIdentifiers: ids,
            reviewedAssetIdentifiers: reviewed,
            savedAssetIdentifier: "saved-70",
            prefersFirstUnreviewedBeforeSavedProgress: true
        )

        #expect(index == 0)
    }

    @Test func reviewSessionInitialTargetReturnsToSavedProgressAfterNewPhotosAreReviewed() async throws {
        let ids = ["new-2", "new-1", "reviewed-0", "saved-70", "unreviewed-71"]
        let reviewed: Set<String> = ["new-2", "new-1", "reviewed-0"]

        let index = PhotoReviewSessionPaginator.initialTargetIndex(
            assetIdentifiers: ids,
            reviewedAssetIdentifiers: reviewed,
            savedAssetIdentifier: "saved-70",
            prefersFirstUnreviewedBeforeSavedProgress: true
        )

        #expect(index == 3)
    }

    @Test func reviewSessionInitialTargetContinuesAfterSavedProgressWhenNewPhotosAreReviewed() async throws {
        let ids = ["new-2", "new-1", "reviewed-0", "saved-70", "unreviewed-71"]
        let reviewed: Set<String> = ["new-2", "new-1", "reviewed-0", "saved-70"]

        let index = PhotoReviewSessionPaginator.initialTargetIndex(
            assetIdentifiers: ids,
            reviewedAssetIdentifiers: reviewed,
            savedAssetIdentifier: "saved-70",
            prefersFirstUnreviewedBeforeSavedProgress: true
        )

        #expect(index == 4)
    }

    @Test func reviewSessionInitialTargetUsesSavedProgressWhenNoNewPhotosExist() async throws {
        let ids = ["reviewed-2", "reviewed-1", "reviewed-0", "saved-70", "unreviewed-71"]
        let reviewed: Set<String> = ["reviewed-2", "reviewed-1", "reviewed-0"]

        let index = PhotoReviewSessionPaginator.initialTargetIndex(
            assetIdentifiers: ids,
            reviewedAssetIdentifiers: reviewed,
            savedAssetIdentifier: "saved-70",
            prefersFirstUnreviewedBeforeSavedProgress: true
        )

        #expect(index == 3)
    }

    @Test func reviewSessionInitialTargetContinuesAfterSavedProgressWhenNoEarlierUnreviewedExists() async throws {
        let ids = ["reviewed-0", "saved-70", "unreviewed-71", "unreviewed-72"]
        let reviewed: Set<String> = ["reviewed-0", "saved-70"]

        let index = PhotoReviewSessionPaginator.initialTargetIndex(
            assetIdentifiers: ids,
            reviewedAssetIdentifiers: reviewed,
            savedAssetIdentifier: "saved-70",
            prefersFirstUnreviewedBeforeSavedProgress: true
        )

        #expect(index == 2)
    }

    @Test func reviewSessionInitialTargetKeepsSavedProgressForScopedLists() async throws {
        let ids = ["new-2", "new-1", "saved-70", "unreviewed-71"]
        let reviewed: Set<String> = ["saved-70"]

        let index = PhotoReviewSessionPaginator.initialTargetIndex(
            assetIdentifiers: ids,
            reviewedAssetIdentifiers: reviewed,
            savedAssetIdentifier: "saved-70"
        )

        #expect(index == 3)
    }

    @Test func photoReviewReadinessAllowsAllPhotosDuringBackgroundLoading() async throws {
        #expect(!PhotoReviewSourceReadiness.isWaiting(
            selectedCategory: .all,
            selectedLocationGroupID: nil,
            hasLoadedAllCategoryPhotos: true,
            isPhotoLibraryLoading: true,
            isPreparingLibrary: true,
            isRestoringLibrarySnapshot: false,
            isLoadingLocationGroups: false,
            isResolvingLocationTitles: false,
            isLoadingAdvancedCleanupQueues: false,
            hasLoadedAlbumMembership: true,
            isLoadingAlbums: false
        ))

        #expect(PhotoReviewSourceReadiness.isWaiting(
            selectedCategory: .videos,
            selectedLocationGroupID: nil,
            hasLoadedAllCategoryPhotos: true,
            isPhotoLibraryLoading: true,
            isPreparingLibrary: true,
            isRestoringLibrarySnapshot: false,
            isLoadingLocationGroups: false,
            isResolvingLocationTitles: false,
            isLoadingAdvancedCleanupQueues: false,
            hasLoadedAlbumMembership: true,
            isLoadingAlbums: false
        ))

        #expect(PhotoReviewSourceReadiness.isWaiting(
            selectedCategory: .all,
            selectedLocationGroupID: nil,
            hasLoadedAllCategoryPhotos: false,
            isPhotoLibraryLoading: true,
            isPreparingLibrary: false,
            isRestoringLibrarySnapshot: false,
            isLoadingLocationGroups: false,
            isResolvingLocationTitles: false,
            isLoadingAdvancedCleanupQueues: false,
            hasLoadedAlbumMembership: true,
            isLoadingAlbums: false
        ))

        #expect(PhotoReviewSourceReadiness.isWaiting(
            selectedCategory: .unclassified,
            selectedLocationGroupID: nil,
            hasLoadedAllCategoryPhotos: true,
            isPhotoLibraryLoading: false,
            isPreparingLibrary: false,
            isRestoringLibrarySnapshot: false,
            isLoadingLocationGroups: false,
            isResolvingLocationTitles: false,
            isLoadingAdvancedCleanupQueues: false,
            hasLoadedAlbumMembership: false,
            isLoadingAlbums: true
        ))

        #expect(!PhotoReviewSourceReadiness.isWaiting(
            selectedCategory: .unclassified,
            selectedLocationGroupID: nil,
            hasLoadedAllCategoryPhotos: true,
            isPhotoLibraryLoading: false,
            isPreparingLibrary: false,
            isRestoringLibrarySnapshot: false,
            isLoadingLocationGroups: false,
            isResolvingLocationTitles: false,
            isLoadingAdvancedCleanupQueues: false,
            hasLoadedAlbumMembership: true,
            isLoadingAlbums: false
        ))
    }

    @Test func photoReviewReadinessStillWaitsForScopedLocationAndAdvancedQueues() async throws {
        #expect(PhotoReviewSourceReadiness.isWaiting(
            selectedCategory: .all,
            selectedLocationGroupID: "location:shanghai",
            hasLoadedAllCategoryPhotos: true,
            isPhotoLibraryLoading: true,
            isPreparingLibrary: false,
            isRestoringLibrarySnapshot: false,
            isLoadingLocationGroups: true,
            isResolvingLocationTitles: false,
            isLoadingAdvancedCleanupQueues: false,
            hasLoadedAlbumMembership: true,
            isLoadingAlbums: false
        ))

        #expect(PhotoReviewSourceReadiness.isWaiting(
            selectedCategory: nil,
            selectedLocationGroupID: nil,
            hasLoadedAllCategoryPhotos: true,
            isPhotoLibraryLoading: false,
            isPreparingLibrary: false,
            isRestoringLibrarySnapshot: false,
            isLoadingLocationGroups: false,
            isResolvingLocationTitles: false,
            isLoadingAdvancedCleanupQueues: true,
            hasLoadedAlbumMembership: true,
            isLoadingAlbums: false
        ))
    }

    @Test func similarPhotoGroupingUsesBurstIdentifierForTwoItemGroups() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let groups = DataManager.similarPhotoIdentifierGroups(from: [
            similarFingerprint("burst-a", date: date, burstIdentifier: "burst-1"),
            similarFingerprint("burst-b", date: date.addingTimeInterval(30), burstIdentifier: "burst-1")
        ])

        #expect(groups == [["burst-a", "burst-b"]])
    }

    @Test func similarPhotoGroupingRejectsLooseTimeOnlyMatches() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let groups = DataManager.similarPhotoIdentifierGroups(from: [
            similarFingerprint("a", date: date),
            similarFingerprint("b", date: date.addingTimeInterval(45)),
            similarFingerprint("c", date: date.addingTimeInterval(90))
        ])

        #expect(groups.isEmpty)
    }

    @Test func similarPhotoGroupingAcceptsTightSameDimensionSequence() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let groups = DataManager.similarPhotoIdentifierGroups(from: [
            similarFingerprint("a", date: date),
            similarFingerprint("b", date: date.addingTimeInterval(3)),
            similarFingerprint("c", date: date.addingTimeInterval(6))
        ])

        #expect(groups == [["a", "b", "c"]])
    }

    @Test func similarPhotoGroupingAcceptsTightTwoPhotoSequence() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let groups = DataManager.similarPhotoIdentifierGroups(from: [
            similarFingerprint("a", date: date),
            similarFingerprint("b", date: date.addingTimeInterval(3))
        ])

        #expect(groups == [["a", "b"]])
    }

    @Test func similarPhotoGroupingRejectsAdjacentButLooseSequence() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let groups = DataManager.similarPhotoIdentifierGroups(from: [
            similarFingerprint("a", date: date),
            similarFingerprint("b", date: date.addingTimeInterval(8)),
            similarFingerprint("c", date: date.addingTimeInterval(16))
        ])

        #expect(groups.isEmpty)
    }

    @Test func similarPhotoGroupingRejectsSmallDimensionDrift() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let groups = DataManager.similarPhotoIdentifierGroups(from: [
            similarFingerprint("a", date: date, width: 4_032, height: 3_024),
            similarFingerprint("b", date: date.addingTimeInterval(3), width: 4_180, height: 3_135),
            similarFingerprint("c", date: date.addingTimeInterval(6), width: 4_032, height: 3_024)
        ])

        #expect(groups.isEmpty)
    }

    @Test func similarPhotoGroupingSeparatesDifferentDimensions() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let groups = DataManager.similarPhotoIdentifierGroups(from: [
            similarFingerprint("a", date: date, width: 4_032, height: 3_024),
            similarFingerprint("b", date: date.addingTimeInterval(3), width: 3_024, height: 4_032),
            similarFingerprint("c", date: date.addingTimeInterval(6), width: 4_032, height: 3_024)
        ])

        #expect(groups.isEmpty)
    }

    @Test func videoPlaybackProgressMapperClampsDragLocations() async throws {
        #expect(VideoPlaybackProgressMapper.progress(locationX: -12, width: 120) == 0)
        #expect(VideoPlaybackProgressMapper.progress(locationX: 60, width: 120) == 0.5)
        #expect(VideoPlaybackProgressMapper.progress(locationX: 180, width: 120) == 1)
        #expect(VideoPlaybackProgressMapper.progress(locationX: 60, width: 0) == 0)
    }

    @Test func videoPlaybackDurationResolverFallsBackToAssetDuration() async throws {
        #expect(VideoPlaybackDurationResolver.playableDuration(
            playerItemDuration: 12,
            assetDuration: 8
        ) == 12)
        #expect(VideoPlaybackDurationResolver.playableDuration(
            playerItemDuration: .nan,
            assetDuration: 8
        ) == 8)
        #expect(VideoPlaybackDurationResolver.playableDuration(
            playerItemDuration: 0,
            assetDuration: 8
        ) == 8)
        #expect(VideoPlaybackDurationResolver.playableDuration(
            playerItemDuration: nil,
            assetDuration: 0
        ) == nil)
    }

    @Test func videoPlaybackControlVisibilityHidesPlayingControlsUntilTapped() async throws {
        #expect(!VideoPlaybackControlVisibility.shouldShowButton(
            isPlaying: true,
            controlsVisible: false,
            playbackProgress: 0.2
        ))
        #expect(VideoPlaybackControlVisibility.shouldShowButton(
            isPlaying: true,
            controlsVisible: true,
            playbackProgress: 0.2
        ))
        #expect(VideoPlaybackControlVisibility.shouldShowButton(
            isPlaying: false,
            controlsVisible: false,
            playbackProgress: 0.2
        ))
        #expect(VideoPlaybackControlVisibility.shouldShowButton(
            isPlaying: true,
            controlsVisible: false,
            playbackProgress: 1
        ))
    }

    @Test func videoPlaybackControlVisibilityAutoHidesOnlyWhilePlaying() async throws {
        #expect(VideoPlaybackControlVisibility.shouldAutoHideControls(isPlaying: true, controlsVisible: true))
        #expect(!VideoPlaybackControlVisibility.shouldAutoHideControls(isPlaying: false, controlsVisible: true))
        #expect(!VideoPlaybackControlVisibility.shouldAutoHideControls(isPlaying: true, controlsVisible: false))
    }

    @Test func videoPlaybackProgressHitRegionOnlyUsesBottomControlArea() async throws {
        let containerSize = CGSize(width: 320, height: 500)

        #expect(VideoPlaybackControlLayout.isInProgressHitRegion(
            point: CGPoint(x: 160, y: 480),
            containerSize: containerSize
        ))
        #expect(!VideoPlaybackControlLayout.isInProgressHitRegion(
            point: CGPoint(x: 160, y: 300),
            containerSize: containerSize
        ))
        #expect(!VideoPlaybackControlLayout.isInProgressHitRegion(
            point: CGPoint(x: 340, y: 480),
            containerSize: containerSize
        ))
        #expect(VideoPlaybackControlLayout.progressHitHeight >= 44)
    }

    @Test func videoPlaybackScrubResumePolicyUsesPlayerAndViewState() async throws {
        #expect(VideoPlaybackScrubResumePolicy.shouldResumeAfterScrub(
            wasPlayingState: true,
            playerWasPlaying: false
        ))
        #expect(VideoPlaybackScrubResumePolicy.shouldResumeAfterScrub(
            wasPlayingState: false,
            playerWasPlaying: true
        ))
        #expect(!VideoPlaybackScrubResumePolicy.shouldResumeAfterScrub(
            wasPlayingState: false,
            playerWasPlaying: false
        ))
        #expect(VideoPlaybackScrubResumePolicy.shouldResumeAfterScrub(
            wasPlayingState: false,
            playerWasPlaying: false,
            autoPlayEnabled: true,
            playbackProgress: 0.5
        ))
        #expect(!VideoPlaybackScrubResumePolicy.shouldResumeAfterScrub(
            wasPlayingState: false,
            playerWasPlaying: false,
            autoPlayEnabled: true,
            playbackProgress: 1
        ))
    }

    @Test func videoPlaybackScrubFallbackEndsQuicklyWhenTouchEndIsLost() async throws {
        #expect(VideoPlaybackScrubTiming.endFallbackDelay <= 0.2)
        #expect(VideoPlaybackScrubTiming.resumeAfterLastScrubDelay <= 0.25)
        #expect(VideoPlaybackScrubTiming.controlHideRetryDelay <= 0.3)
        #expect(VideoPlaybackScrubTiming.controlHideAfterResumeDelay <= 0.5)
    }

    @Test func inlineVideoScrubGestureRegionReservesBottomVideoArea() async throws {
        let cardSize = CGSize(width: 320, height: 520)

        #expect(InlineVideoScrubGestureRegion.contains(
            startLocation: CGPoint(x: 160, y: 470),
            cardSize: cardSize,
            isVideoPlaying: true,
            reservedBottomHeight: 78
        ))
        #expect(!InlineVideoScrubGestureRegion.contains(
            startLocation: CGPoint(x: 160, y: 430),
            cardSize: cardSize,
            isVideoPlaying: true,
            reservedBottomHeight: 78
        ))
    }

    @Test func inlineVideoCardHitRegionKeepsScrubberAreaInteractive() async throws {
        let cardSize = CGSize(width: 320, height: 520)
        let scrubberPoint = CGPoint(x: 160, y: 470)

        #expect(InlineVideoScrubGestureRegion.contains(
            startLocation: scrubberPoint,
            cardSize: cardSize,
            isVideoPlaying: true,
            reservedBottomHeight: 78
        ))
        #expect(InlineVideoCardHitRegion.contains(
            point: scrubberPoint,
            cardSize: cardSize
        ))
    }

    @Test func inlineVideoCardGestureRoutingOnlyReservesBottomScrubberDrags() async throws {
        let cardSize = CGSize(width: 320, height: 520)

        #expect(InlineVideoCardGestureRouting.shouldReserveForVideoScrubber(
            startLocation: CGPoint(x: 160, y: 470),
            cardSize: cardSize,
            isVideoPlaying: true,
            reservedBottomHeight: 78,
            isCurrentVideoScrubbing: false,
            isScrubGestureActive: false
        ))
        #expect(!InlineVideoCardGestureRouting.shouldReserveForVideoScrubber(
            startLocation: CGPoint(x: 160, y: 260),
            cardSize: cardSize,
            isVideoPlaying: true,
            reservedBottomHeight: 78,
            isCurrentVideoScrubbing: true,
            isScrubGestureActive: false
        ))
        #expect(InlineVideoCardGestureRouting.shouldReserveForVideoScrubber(
            startLocation: CGPoint(x: 160, y: 260),
            cardSize: cardSize,
            isVideoPlaying: true,
            reservedBottomHeight: 78,
            isCurrentVideoScrubbing: false,
            isScrubGestureActive: true
        ))
    }

    @Test func inlineVideoScrubGestureRegionIgnoresInactiveVideoAndInvalidSizes() async throws {
        let cardSize = CGSize(width: 320, height: 520)

        #expect(!InlineVideoScrubGestureRegion.contains(
            startLocation: CGPoint(x: 160, y: 470),
            cardSize: cardSize,
            isVideoPlaying: false,
            reservedBottomHeight: 78
        ))
        #expect(!InlineVideoScrubGestureRegion.contains(
            startLocation: CGPoint(x: 160, y: 470),
            cardSize: .zero,
            isVideoPlaying: true,
            reservedBottomHeight: 78
        ))
    }

    @Test func albumShortcutVisibilityRequiresAlbumsAndActionableReviewPhoto() async throws {
        #expect(AlbumShortcutVisibility.shouldShow(
            isAlbumMode: false,
            canPerformPhotoAction: true,
            albumCount: 1
        ))
        #expect(!AlbumShortcutVisibility.shouldShow(
            isAlbumMode: true,
            canPerformPhotoAction: true,
            albumCount: 1
        ))
        #expect(!AlbumShortcutVisibility.shouldShow(
            isAlbumMode: false,
            canPerformPhotoAction: false,
            albumCount: 1
        ))
        #expect(!AlbumShortcutVisibility.shouldShow(
            isAlbumMode: false,
            canPerformPhotoAction: true,
            albumCount: 0
        ))
    }

    @Test func albumShortcutLayoutUsesCompactTwoRowsFromFourAlbums() async throws {
        #expect(!AlbumShortcutLayout.usesTwoRows(albumCount: 3))
        #expect(AlbumShortcutLayout.usesTwoRows(albumCount: 4))
        #expect(AlbumShortcutLayout.stripHeight(albumCount: 3) == 44)
        #expect(AlbumShortcutLayout.stripHeight(albumCount: 4) == 88)
        #expect(AlbumShortcutLayout.rowSpacing <= 2)
    }

    @Test func albumShortcutEligibilityOnlyIncludesWritableUserAlbums() async throws {
        #expect(AlbumShortcutEligibility.shouldInclude(
            type: .userCreated,
            hasAssetCollection: true,
            canAddContent: true
        ))
        #expect(!AlbumShortcutEligibility.shouldInclude(
            type: .userCreated,
            hasAssetCollection: false,
            canAddContent: true
        ))
        #expect(!AlbumShortcutEligibility.shouldInclude(
            type: .userCreated,
            hasAssetCollection: true,
            canAddContent: false
        ))
        #expect(!AlbumShortcutEligibility.shouldInclude(
            type: .favorites,
            hasAssetCollection: true,
            canAddContent: true
        ))
    }

    @Test func albumReviewDownSwipeOnlyRemovesFromWritableUserAlbums() async throws {
        #expect(AlbumReviewDownSwipeBehavior.resolve(
            isAlbumMode: true,
            albumType: .userCreated,
            hasAssetCollection: true,
            canRemoveContent: true
        ) == .removeFromAlbum)
        #expect(AlbumReviewDownSwipeBehavior.resolve(
            isAlbumMode: false,
            albumType: .userCreated,
            hasAssetCollection: true,
            canRemoveContent: true
        ) == .returnToList)
        #expect(AlbumReviewDownSwipeBehavior.resolve(
            isAlbumMode: true,
            albumType: .userCreated,
            hasAssetCollection: false,
            canRemoveContent: true
        ) == .returnToList)
        #expect(AlbumReviewDownSwipeBehavior.resolve(
            isAlbumMode: true,
            albumType: .favorites,
            hasAssetCollection: true,
            canRemoveContent: true
        ) == .returnToList)
        #expect(AlbumReviewDownSwipeBehavior.resolve(
            isAlbumMode: true,
            albumType: .userCreated,
            hasAssetCollection: true,
            canRemoveContent: false
        ) == .returnToList)
        #expect(AlbumReviewDownSwipeBehavior.removeFromAlbum.detailTitle == L10n.string("移出相册，不删除照片"))
        #expect(AlbumReviewDownSwipeBehavior.removeFromAlbum.feedbackTitle == L10n.string("下滑移出相册"))
    }

    @Test func photoSwipeDragFeedbackPlacesDownSwipeHintAtTop() async throws {
        #expect(PhotoSwipeDragFeedbackHintPlacement.placement(for: .down) == .top)
        #expect(PhotoSwipeDragFeedbackHintPlacement.placement(for: .up) == .top)
        #expect(PhotoSwipeDragFeedbackHintPlacement.placement(for: .left) == .center)
        #expect(PhotoSwipeDragFeedbackHintPlacement.placement(for: .right) == .center)
    }

    @Test func photoLibraryLoadingPublishesOnlyUsefulLaunchUpdates() async throws {
        #expect(PhotoLibraryLoadingPublishPolicy.shouldPublishInitialPhotos(
            batchStart: 0,
            batchEnd: 500,
            totalCount: 5_000,
            preserveExistingData: false
        ))
        #expect(!PhotoLibraryLoadingPublishPolicy.shouldPublishInitialPhotos(
            batchStart: 500,
            batchEnd: 1_000,
            totalCount: 5_000,
            preserveExistingData: false
        ))
        #expect(!PhotoLibraryLoadingPublishPolicy.shouldPublishInitialPhotos(
            batchStart: 0,
            batchEnd: 500,
            totalCount: 5_000,
            preserveExistingData: true
        ))

        #expect(!PhotoLibraryLoadingPublishPolicy.shouldPublishScanProgress(
            batchEnd: 500,
            totalCount: 30_000,
            batchSize: 500
        ))
        #expect(PhotoLibraryLoadingPublishPolicy.shouldPublishScanProgress(
            batchEnd: 2_500,
            totalCount: 30_000,
            batchSize: 500
        ))
        #expect(PhotoLibraryLoadingPublishPolicy.shouldPublishScanProgress(
            batchEnd: 30_000,
            totalCount: 30_000,
            batchSize: 500
        ))
    }

    @Test func restoredSnapshotDefersTimelineBuildAfterLaunch() async throws {
        #expect(PhotoLibraryStartupRefreshTiming.initialLibraryProgressDelay >= 1.5)
        #expect(PhotoLibraryStartupRefreshTiming.initialLibraryProgressDelay <= 3.0)
        #expect(PhotoLibraryStartupRefreshTiming.restoredSnapshotProgressDelay >= 1.0)
        #expect(PhotoLibraryStartupRefreshTiming.restoredSnapshotProgressDelay <= 2.0)
    }

    @Test func photoLibraryReloadIsDeferredOnlyForTrackedChangesDuringARealLoad() async throws {
        #expect(!PhotoLibraryDeferredReloadPolicy.shouldDeferReload(
            isLoading: true,
            isRestoringSnapshot: false,
            hasTrackedFetchResult: false,
            hasChangeDetails: false
        ))
        #expect(!PhotoLibraryDeferredReloadPolicy.shouldDeferReload(
            isLoading: true,
            isRestoringSnapshot: false,
            hasTrackedFetchResult: true,
            hasChangeDetails: false
        ))
        #expect(PhotoLibraryDeferredReloadPolicy.shouldDeferReload(
            isLoading: true,
            isRestoringSnapshot: false,
            hasTrackedFetchResult: true,
            hasChangeDetails: true
        ))
        #expect(PhotoLibraryDeferredReloadPolicy.shouldDeferReload(
            isLoading: false,
            isRestoringSnapshot: true,
            hasTrackedFetchResult: true,
            hasChangeDetails: true
        ))
    }

    @Test func singlePassAssetClassificationPreservesExistingMediaRules() async throws {
        let screenSize = CGSize(width: 1_170, height: 2_532)

        let screenshot = PhotoLibraryAssetClassification.resolve(
            mediaType: .image,
            mediaSubtypes: [.photoScreenshot],
            pixelWidth: 2_000,
            pixelHeight: 3_000,
            screenPixelSize: screenSize,
            isFavorite: true
        )
        #expect(screenshot.isScreenshot)
        #expect(screenshot.isFavorite)
        #expect(!screenshot.isVideo)
        #expect(!screenshot.isLivePhoto)

        let livePhoto = PhotoLibraryAssetClassification.resolve(
            mediaType: .image,
            mediaSubtypes: [.photoLive],
            pixelWidth: 4_032,
            pixelHeight: 3_024,
            screenPixelSize: screenSize,
            isFavorite: false
        )
        #expect(livePhoto.isLivePhoto)
        #expect(!livePhoto.isScreenshot)

        let dimensionMatchedScreenshot = PhotoLibraryAssetClassification.resolve(
            mediaType: .image,
            mediaSubtypes: [],
            pixelWidth: 1_170,
            pixelHeight: 2_532,
            screenPixelSize: screenSize,
            isFavorite: false
        )
        #expect(dimensionMatchedScreenshot.isScreenshot)

        let video = PhotoLibraryAssetClassification.resolve(
            mediaType: .video,
            mediaSubtypes: [],
            pixelWidth: 1_170,
            pixelHeight: 2_532,
            screenPixelSize: screenSize,
            isFavorite: false
        )
        #expect(video.isVideo)
        #expect(!video.isScreenshot)
        #expect(!video.isLivePhoto)
    }

    @Test func albumScanProgressPublishesAtCoarseIntervalsAndCompletion() async throws {
        #expect(!AlbumScanProgressPublishPolicy.shouldPublish(
            completedSteps: 1,
            totalSteps: 100,
            lastPublishedProgress: 0
        ))
        #expect(AlbumScanProgressPublishPolicy.shouldPublish(
            completedSteps: 5,
            totalSteps: 100,
            lastPublishedProgress: 0
        ))
        #expect(!AlbumScanProgressPublishPolicy.shouldPublish(
            completedSteps: 9,
            totalSteps: 100,
            lastPublishedProgress: 0.05
        ))
        #expect(AlbumScanProgressPublishPolicy.shouldPublish(
            completedSteps: 100,
            totalSteps: 100,
            lastPublishedProgress: 0.95
        ))
    }

    @Test func albumReviewSessionsIgnorePersistedReviewedStateOnRefresh() async throws {
        let persistedReviewedIDs: Set<String> = ["asset-a", "asset-b"]

        #expect(PhotoReviewSessionReviewedStatePolicy.reviewedAssetIdentifiers(
            isAlbumMode: true,
            persistedReviewedAssetIdentifiers: persistedReviewedIDs
        ).isEmpty)
        #expect(PhotoReviewSessionReviewedStatePolicy.reviewedCount(
            isAlbumMode: true,
            persistedReviewedCount: persistedReviewedIDs.count
        ) == 0)
        #expect(!PhotoReviewSessionReviewedStatePolicy.shouldShowCompletionAfterRefresh(
            isAlbumMode: true,
            hasPhotos: true,
            firstUnreviewedIndex: nil
        ))

        #expect(PhotoReviewSessionReviewedStatePolicy.reviewedAssetIdentifiers(
            isAlbumMode: false,
            persistedReviewedAssetIdentifiers: persistedReviewedIDs
        ) == persistedReviewedIDs)
        #expect(PhotoReviewSessionReviewedStatePolicy.reviewedCount(
            isAlbumMode: false,
            persistedReviewedCount: persistedReviewedIDs.count
        ) == persistedReviewedIDs.count)
        #expect(PhotoReviewSessionReviewedStatePolicy.shouldShowCompletionAfterRefresh(
            isAlbumMode: false,
            hasPhotos: true,
            firstUnreviewedIndex: nil
        ))

        #expect(PhotoReviewSessionReviewedStatePolicy.reviewedAssetIdentifiers(
            isAlbumMode: false,
            isRandomMemoriesMode: true,
            persistedReviewedAssetIdentifiers: persistedReviewedIDs
        ).isEmpty)
        #expect(!PhotoReviewSessionReviewedStatePolicy.shouldShowCompletionAfterRefresh(
            isAlbumMode: false,
            isRandomMemoriesMode: true,
            hasPhotos: true,
            firstUnreviewedIndex: nil
        ))
    }

    @Test func albumShortcutScrollRestorationDoesNotRunAfterCurrentPhotoChanges() async throws {
        #expect(AlbumShortcutScrollRestorationPolicy.shouldRestore(anchorID: "album-a", reason: .appear))
        #expect(AlbumShortcutScrollRestorationPolicy.shouldRestore(anchorID: "album-a", reason: .albumsChanged))
        #expect(!AlbumShortcutScrollRestorationPolicy.shouldRestore(anchorID: "album-a", reason: .currentPhotoChanged))
        #expect(!AlbumShortcutScrollRestorationPolicy.shouldRestore(anchorID: nil, reason: .appear))
    }

    @Test func albumShortcutVisibilityCanStayStableWhileAlbumFilingFinishes() async throws {
        #expect(!AlbumShortcutVisibility.shouldShow(
            isAlbumMode: false,
            canPerformPhotoAction: false,
            albumCount: 2
        ))
        #expect(AlbumShortcutVisibility.shouldShow(
            isAlbumMode: false,
            canPerformPhotoAction: false,
            shouldKeepStableDuringFiling: true,
            albumCount: 2
        ))
        #expect(!AlbumShortcutVisibility.shouldShow(
            isAlbumMode: true,
            canPerformPhotoAction: false,
            shouldKeepStableDuringFiling: true,
            albumCount: 2
        ))
    }

    @Test func albumShortcutFilingCounterTracksConcurrentWrites() async throws {
        let firstIncrement = AlbumShortcutFilingCounter.increment([:], albumID: "album-a")
        let secondIncrement = AlbumShortcutFilingCounter.increment(firstIncrement, albumID: "album-a")

        #expect(AlbumShortcutFilingCounter.isFiling(secondIncrement, albumID: "album-a"))
        #expect(secondIncrement["album-a"] == 2)

        let firstDecrement = AlbumShortcutFilingCounter.decrement(secondIncrement, albumID: "album-a")
        #expect(AlbumShortcutFilingCounter.isFiling(firstDecrement, albumID: "album-a"))
        #expect(firstDecrement["album-a"] == 1)

        let secondDecrement = AlbumShortcutFilingCounter.decrement(firstDecrement, albumID: "album-a")
        #expect(!AlbumShortcutFilingCounter.isFiling(secondDecrement, albumID: "album-a"))
        #expect(secondDecrement["album-a"] == nil)
    }

    @Test func advancedPreviewPagingShowsSelectedPositionAndNeighbors() async throws {
        let identifiers = ["first", "second", "third"]

        #expect(AdvancedPreviewPaging.positionText(selectedIdentifier: "second", identifiers: identifiers) == "2 / 3")
        #expect(AdvancedPreviewPaging.adjacentIdentifier(
            selectedIdentifier: "second",
            identifiers: identifiers,
            direction: .previous
        ) == "first")
        #expect(AdvancedPreviewPaging.adjacentIdentifier(
            selectedIdentifier: "second",
            identifiers: identifiers,
            direction: .next
        ) == "third")
    }

    @Test func advancedPreviewPagingStopsAtEdgesAndHidesSingleItemPosition() async throws {
        let identifiers = ["first", "second", "third"]

        #expect(AdvancedPreviewPaging.positionText(selectedIdentifier: "first", identifiers: ["first"]) == nil)
        #expect(AdvancedPreviewPaging.adjacentIdentifier(
            selectedIdentifier: "first",
            identifiers: identifiers,
            direction: .previous
        ) == nil)
        #expect(AdvancedPreviewPaging.adjacentIdentifier(
            selectedIdentifier: "third",
            identifiers: identifiers,
            direction: .next
        ) == nil)
    }

    @Test func advancedSelectableThumbnailSelectionButtonStaysVisuallySubtle() async throws {
        #expect(AdvancedSelectableThumbnailSelectionButtonStyle.selectedIconOpacity <= 0.8)
        #expect(AdvancedSelectableThumbnailSelectionButtonStyle.unselectedIconOpacity <= 0.65)
        #expect(AdvancedSelectableThumbnailSelectionButtonStyle.backgroundOpacity(isSelected: true) <= 0.5)
        #expect(AdvancedSelectableThumbnailSelectionButtonStyle.backgroundOpacity(isSelected: false) <= 0.3)
        #expect(AdvancedSelectableThumbnailSelectionButtonStyle.shadowOpacity <= 0.15)
        #expect(AdvancedSelectableThumbnailSelectionButtonStyle.visualSize <= 30)
    }

    @Test func visibleListPaginationFiltersBeforePagingAndClampsLimit() async throws {
        let summaries = [
            makePeriodSummary(index: 0, assetCount: 0),
            makePeriodSummary(index: 1, assetCount: 12),
            makePeriodSummary(index: 2, assetCount: 8)
        ]
        let filtered = VisibleListPagination.filteredItems(summaries) { $0.assetCount > 0 }

        #expect(filtered.map(\.assetCount) == [12, 8])
        #expect(VisibleListPagination.visibleItems(filtered, limit: 1).count == 1)
        #expect(VisibleListPagination.hasMore(totalCount: filtered.count, limit: 1))
        #expect(VisibleListPagination.advancedLimit(totalCount: filtered.count, currentLimit: 1, step: 20) == 2)
    }

    @Test func visibleListPaginationKeepsTotalSeparateFromVisibleCount() async throws {
        let items = Array(0..<250)
        let firstPage = VisibleListPagination.visibleItems(items, limit: 120)
        let secondLimit = VisibleListPagination.advancedLimit(
            totalCount: items.count,
            currentLimit: firstPage.count,
            step: 120
        )
        let secondPage = VisibleListPagination.visibleItems(items, limit: secondLimit)

        #expect(items.count == 250)
        #expect(firstPage.count == 120)
        #expect(secondPage.count == 240)
        #expect(VisibleListPagination.hasMore(totalCount: items.count, limit: secondPage.count))
    }

    @MainActor
    @Test func memoryCaptionFormatterHandlesUnknownTodayAndPastDates() async throws {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: AppConstants.appLanguageKey)
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: AppConstants.appLanguageKey)
            } else {
                defaults.removeObject(forKey: AppConstants.appLanguageKey)
            }
        }
        defaults.set(AppLanguage.zhHans.rawValue, forKey: AppConstants.appLanguageKey)

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

    private func makeAssetIDs(_ count: Int, prefix: String = "asset") -> [String] {
        (0..<count).map { "\(prefix)-\($0)" }
    }

    private func makePeriodSummary(
        index: Int,
        scope: AdvancedTimeScope = .month,
        assetCount: Int = 1,
        reviewedCount: Int = 0
    ) -> PhotoPeriodSummary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = makeDate(year: 2026, month: 1 + index, day: 1, calendar: calendar)
        let interval = calendar.dateInterval(for: scope, containing: date)
        return PhotoPeriodSummary(
            scope: scope,
            intervalStart: interval.start,
            intervalEnd: interval.end,
            assetCount: assetCount,
            screenshotCount: 0,
            videoCount: 0,
            reviewedCount: reviewedCount,
            estimatedSizeMB: 0
        )
    }

    private func similarFingerprint(
        _ identifier: String,
        date: Date,
        width: Int = 4_032,
        height: Int = 3_024,
        burstIdentifier: String? = nil
    ) -> SimilarPhotoAssetFingerprint {
        SimilarPhotoAssetFingerprint(
            identifier: identifier,
            creationDate: date,
            pixelWidth: width,
            pixelHeight: height,
            burstIdentifier: burstIdentifier
        )
    }

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
