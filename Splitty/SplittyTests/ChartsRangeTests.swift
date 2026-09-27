//
//  ChartsRangeTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

/// A range is two local calendar dates, `to` exclusive, plus the zone the server reads
/// them in. The client never builds instants.
struct ChartsRangeTests {
    private static let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.saoPaulo
        return calendar
    }

    /// 2026-03-14 12:00 in São Paulo.
    private let midMarch = Date(timeIntervalSince1970: 1_773_500_400)

    @Test func monthRunsFromTheFirstToTheFirstOfNextMonth() {
        #expect(ChartsRange.month.query(now: midMarch, calendar: calendar)
            == StatsQuery(from: "2026-03-01", to: "2026-04-01", timeZone: "America/Sao_Paulo"))
    }

    @Test func threeMonthsStartsTwoMonthsBackAndEndsWithThisMonth() {
        #expect(ChartsRange.threeMonths.query(now: midMarch, calendar: calendar)
            == StatsQuery(from: "2026-01-01", to: "2026-04-01", timeZone: "America/Sao_Paulo"))
    }

    @Test func yearRunsFromTheFirstOfJanuaryToTheNext() {
        #expect(ChartsRange.year.query(now: midMarch, calendar: calendar)
            == StatsQuery(from: "2026-01-01", to: "2027-01-01", timeZone: "America/Sao_Paulo"))
    }

    @Test func allTimeSendsNoDatesButStillTheZone() {
        #expect(ChartsRange.allTime.query(now: midMarch, calendar: calendar)
            == StatsQuery(from: nil, to: nil, timeZone: "America/Sao_Paulo"))
    }

    // 23:30 on 31 Jan in São Paulo is already 1 Feb in UTC. Still January locally.
    @Test func lateOnTheLastDayOfAMonthIsStillThatMonth() {
        let lateOnJanuary31 = Date(timeIntervalSince1970: 1_769_913_000)
        #expect(ChartsRange.month.query(now: lateOnJanuary31, calendar: calendar)
            == StatsQuery(from: "2026-01-01", to: "2026-02-01", timeZone: "America/Sao_Paulo"))
    }

    // 23:30 on 31 Dec in São Paulo is already New Year in UTC. Still this year locally.
    @Test func lateOnNewYearsEveIsStillThatYear() {
        let lateOnDecember31 = Date(timeIntervalSince1970: 1_798_770_600)
        #expect(ChartsRange.year.query(now: lateOnDecember31, calendar: calendar)
            == StatsQuery(from: "2026-01-01", to: "2027-01-01", timeZone: "America/Sao_Paulo"))
        #expect(ChartsRange.month.query(now: lateOnDecember31, calendar: calendar)
            == StatsQuery(from: "2026-12-01", to: "2027-01-01", timeZone: "America/Sao_Paulo"))
    }

    @Test func rangesCrossTheYearBoundary() {
        // 2026-12-20 12:00 and 2027-01-10 12:00 in São Paulo.
        let december = Date(timeIntervalSince1970: 1_797_778_800)
        let january = Date(timeIntervalSince1970: 1_799_593_200)

        #expect(ChartsRange.month.query(now: december, calendar: calendar)
            == StatsQuery(from: "2026-12-01", to: "2027-01-01", timeZone: "America/Sao_Paulo"))
        #expect(ChartsRange.threeMonths.query(now: january, calendar: calendar)
            == StatsQuery(from: "2026-11-01", to: "2027-02-01", timeZone: "America/Sao_Paulo"))
    }
}
