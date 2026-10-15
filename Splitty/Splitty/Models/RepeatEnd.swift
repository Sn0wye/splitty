//
//  RepeatEnd.swift
//  Splitty
//

import Foundation

/// How a recurring expense ends, as the Ends control offers it. The server only ever
/// receives a day: "after N times" is turned into the day of the Nth expense here.
enum RepeatEndKind: String, CaseIterable, Identifiable {
    case never
    case afterCount
    case onDate

    var id: String { rawValue }

    var name: String {
        switch self {
        case .never: L10n.Repeat.endsNever
        case .afterCount: L10n.Repeat.endsAfter
        case .onDate: L10n.Repeat.endsOnDate
        }
    }
}

/// The Ends control's state. Each kind keeps its own value, so switching away and back
/// does not lose a typed count or a picked day.
struct RepeatEndDraft: Equatable {
    var kind: RepeatEndKind = .never
    /// How many expenses, counting the one being saved.
    var count = 1
    var date: Date
}

/// What a "this and following" edit asks of the end.
enum RepeatEndChange: Equatable {
    /// A new last day, `yyyy-MM-dd`.
    case on(String)
    /// No end any more.
    case never
}

/// The days a recurring expense comes due, by the server's rule: each is computed from the
/// start, never from the previous one, so a monthly expense from the 31st goes 31 → 28 → 31,
/// and a yearly one from 29 February lands on 28 February outside leap years.
enum RecurringDueDays {
    /// Gregorian whatever the device calendar is, since the server reads Gregorian days.
    static func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// The `n`th due day after the day `start` falls on, which is the 0th.
    static func dueDay(start: Date, frequency: ExpenseRepeat, n: Int, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: start)
        switch frequency {
        case .never: return nil
        case .weekly: return calendar.date(byAdding: .day, value: 7 * n, to: day)
        case .fortnightly: return calendar.date(byAdding: .day, value: 14 * n, to: day)
        // Both clamp to the last day of a shorter month, which is the rule.
        case .monthly: return calendar.date(byAdding: .month, value: n, to: day)
        case .yearly: return calendar.date(byAdding: .year, value: n, to: day)
        }
    }

    /// The day `date` falls on, as `yyyy-MM-dd`.
    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Midnight of a `yyyy-MM-dd` day.
    static func date(fromDay day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
