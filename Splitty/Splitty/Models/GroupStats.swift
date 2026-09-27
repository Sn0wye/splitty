//
//  GroupStats.swift
//  Splitty
//

import Foundation

/// `GET /group/{id}/stats`: group spend and the caller's share over one range, per leaf
/// category. Both halves arrive together, so switching between them needs no request.
struct GroupStats: Codable, Equatable {
    let group: SpendStats
    let mine: SpendStats

    subscript(lens: ChartsLens) -> SpendStats {
        switch lens {
        case .group: group
        case .mine: mine
        }
    }
}

struct SpendStats: Codable, Equatable {
    @DecodedCents var totalCents: Int
    let expenseCount: Int
    /// Non-zero categories only, largest first.
    let categories: [CategoryStats]

    private enum CodingKeys: String, CodingKey {
        case totalCents = "total"
        case expenseCount, categories
    }
}

struct CategoryStats: Codable, Equatable {
    let category: ExpenseCategory
    @DecodedCents var totalCents: Int
    let expenseCount: Int
    /// This category's five largest expenses, which is enough to derive the top five
    /// overall or under any heading.
    let top: [TopExpense]

    private enum CodingKeys: String, CodingKey {
        case category
        case totalCents = "total"
        case expenseCount, top
    }

    init(category: ExpenseCategory, totalCents: Int, expenseCount: Int, top: [TopExpense]) {
        self.category = category
        _totalCents = DecodedCents(wrappedValue: totalCents)
        self.expenseCount = expenseCount
        self.top = top
    }

    /// A category this build does not know files under `general`, as it does on an
    /// expense, rather than failing the whole screen.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = (try? container.decode(ExpenseCategory.self, forKey: .category)) ?? .general
        _totalCents = try container.decode(DecodedCents.self, forKey: .totalCents)
        expenseCount = try container.decode(Int.self, forKey: .expenseCount)
        top = try container.decode([TopExpense].self, forKey: .top)
    }
}

struct TopExpense: Codable, Equatable {
    let expenseId: Int
    let description: String
    /// The effective date, `date ?? createdAt`, as the API serialized it.
    let date: String
    /// The full amount under group spend, the caller's split under share.
    @DecodedCents var amountCents: Int

    private enum CodingKeys: String, CodingKey {
        case expenseId, description, date
        case amountCents = "amount"
    }

    var effectiveDate: Date? { Expense.parseTimestamp(date) }
}

/// Group = group spend, Mine = share.
enum ChartsLens: CaseIterable, Identifiable {
    case group
    case mine

    var id: Self { self }
}

/// What the stats route is asked for: local dates, `to` exclusive, read in `timeZone`.
struct StatsQuery: Equatable {
    let from: String?
    let to: String?
    let timeZone: String
}

/// A named period. The server has none of these: each resolves to two local dates on the
/// client, so adding one is a client-only change.
enum ChartsRange: CaseIterable, Identifiable {
    case month
    case threeMonths
    case year
    case allTime

    var id: Self { self }

    /// `calendar` must be Gregorian, since the server reads `YYYY-MM-DD` as Gregorian
    /// dates; its time zone is the one sent.
    func query(now: Date, calendar: Calendar) -> StatsQuery {
        let timeZone = calendar.timeZone.identifier
        let bounds: (from: Date, to: Date)? = switch self {
        case .month:
            monthBounds(now: now, calendar: calendar, monthsBack: 0)
        case .threeMonths:
            monthBounds(now: now, calendar: calendar, monthsBack: 2)
        case .year:
            calendar.dateInterval(of: .year, for: now).map { ($0.start, $0.end) }
        case .allTime:
            nil
        }

        guard let bounds else { return StatsQuery(from: nil, to: nil, timeZone: timeZone) }
        return StatsQuery(
            from: Self.localDate(bounds.from, calendar: calendar),
            to: Self.localDate(bounds.to, calendar: calendar),
            timeZone: timeZone
        )
    }

    private func monthBounds(now: Date, calendar: Calendar, monthsBack: Int) -> (from: Date, to: Date)? {
        guard let month = calendar.dateInterval(of: .month, for: now),
              let start = calendar.date(byAdding: .month, value: -monthsBack, to: month.start)
        else { return nil }
        return (start, month.end)
    }

    private static func localDate(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
