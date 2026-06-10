//
//  PhotoDelTests.swift
//  PhotoDelTests
//
//  Created by jackie xiao on 11/7/25.
//

import Testing
import Foundation
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

    @Test func organizeStatsFormatsSavedSpace() async throws {
        #expect(OrganizeStats(spaceSaved: 42).formattedSpaceSaved == "42.0 MB")
        #expect(OrganizeStats(spaceSaved: 1536).formattedSpaceSaved == "1.5 GB")
    }

    private func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day, hour: 12)
        return components.date!
    }

}
