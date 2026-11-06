//
//  Expense.swift
//  Splitty
//
//  Created by Snowye on 19/11/25.
//

import Foundation

// MARK: - Expense Type Enum
enum ExpenseType: String, Codable {
    case expense = "expense"
    case payment = "payment"
}

// MARK: - Split Mode
/// How the user said an expense was divided, as the API stores it. Descriptive: the
/// amounts are the money truth and are never re-derived from this.
enum ExpenseSplitMode: String, Codable {
    case equal
    case custom
    case percentage
}

// MARK: - Repeat
/// How often a recurring expense adds an expense. `never` exists only on the way in: the
/// API answers with one of the other four, or with nothing for an expense entered by hand.
enum ExpenseRepeat: String, Codable, CaseIterable, Identifiable {
    case never
    case weekly
    case fortnightly
    case monthly
    case yearly

    var id: String { rawValue }

    /// What the Repeats picker lists for this choice.
    var name: String {
        switch self {
        case .never: L10n.Repeat.never
        case .weekly: L10n.Repeat.weekly
        case .fortnightly: L10n.Repeat.fortnightly
        case .monthly: L10n.Repeat.monthly
        case .yearly: L10n.Repeat.yearly
        }
    }

    /// The badge on an expense a recurring expense added. Nil for `never`, which no
    /// such expense carries.
    var badge: String? {
        switch self {
        case .never: nil
        case .weekly: L10n.Repeat.repeatsWeekly
        case .fortnightly: L10n.Repeat.repeatsFortnightly
        case .monthly: L10n.Repeat.repeatsMonthly
        case .yearly: L10n.Repeat.repeatsYearly
        }
    }
}

/// How far an edit or delete of an expense a recurring expense added reaches: that
/// expense only, or it and every later one the same recurring expense added.
enum ExpenseScope: String {
    case this
    case following
}

// MARK: - Expense Model
struct Expense: Codable, Identifiable, Equatable {
    let id: Int
    let groupId: Int
    let paidBy: Int
    let amount: Double
    let description: String
    let type: ExpenseType
    let category: ExpenseCategory
    /// How this was divided. `nil` on a settlement, on a row written before the column
    /// existed, and on a mode this build does not recognise — see `init(from:)`.
    let splitMode: ExpenseSplitMode?
    /// When the expense happened, as the user says it did. Nullable: rows written before
    /// the column existed have no user-supplied date, so every reader falls back to
    /// `createdAt`.
    let date: String?
    let createdAt: String
    let updatedAt: String
    let paidByUser: User
    let splits: [ExpenseSplit]
    /// The recurring expense that added this expense; nil for one entered by hand, and
    /// for one whose recurring expense has since stopped.
    var recurringExpenseId: Int? = nil
    /// How often `recurringExpenseId` repeats. Nil when it is nil, and on a frequency this
    /// build does not recognise.
    var repeatFrequency: ExpenseRepeat? = nil
    /// The last day, `yyyy-MM-dd`, `recurringExpenseId` may add an expense on. Nil when it
    /// never ends, and when there is no recurring expense.
    var endsOn: String? = nil
    /// Which installment this is. Nil for an expense entered by hand and for one added by
    /// a recurring expense with no end.
    var installment: ExpenseInstallment? = nil
    /// The id the creating device gave this row before the server saw it. Nil for rows
    /// written without one. A row this device queued carries it from the start, which is
    /// how the server's answer is matched to the row already on screen (ADR 0008).
    var clientId: UUID? = nil
    /// Goes up by one on every edit; an edit sends it back as `baseVersion`. Nil on a row
    /// the server has not stored yet.
    var version: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, groupId, paidBy, amount, description, type, category, splitMode, date
        case createdAt, updatedAt, paidByUser, splits, recurringExpenseId, endsOn, installment
        case clientId, version
        case repeatFrequency = "repeat"
    }

    /// Added by a recurring expense, so editing or deleting it asks how far to reach.
    var isRecurring: Bool { recurringExpenseId != nil }

    /// The badge on a row or detail screen: how often it repeats, and which installment it
    /// is when its recurring expense has an end. Nil for an expense that does not repeat.
    var repeatBadge: String? {
        guard isRecurring, let badge = repeatFrequency?.badge else { return nil }
        guard let installment else { return badge }
        return "\(badge) · \(installment.number)/\(installment.total)"
    }
}

/// Installment `number` of `total`, both counted by the server from the expenses that
/// exist, so deleting one on its own lowers both.
struct ExpenseInstallment: Codable, Equatable {
    let number: Int
    let total: Int
}

extension Expense {
    /// Decoded by hand for two fields: an unrecognised `splitMode` or `repeat` becomes `nil`
    /// rather than throwing. A mode added by a newer client must not fail the whole group's
    /// expense list over a value this build has no opinion about.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        groupId = try container.decode(Int.self, forKey: .groupId)
        paidBy = try container.decode(Int.self, forKey: .paidBy)
        amount = try container.decode(Double.self, forKey: .amount)
        description = try container.decode(String.self, forKey: .description)
        type = try container.decode(ExpenseType.self, forKey: .type)
        category = (try? container.decode(ExpenseCategory.self, forKey: .category)) ?? .general
        splitMode = try? container.decodeIfPresent(ExpenseSplitMode.self, forKey: .splitMode)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        paidByUser = try container.decode(User.self, forKey: .paidByUser)
        splits = try container.decode([ExpenseSplit].self, forKey: .splits)
        recurringExpenseId = try container.decodeIfPresent(Int.self, forKey: .recurringExpenseId)
        // Lenient for the same reason as `splitMode`: a frequency added later must not
        // fail the whole list.
        repeatFrequency = try? container.decodeIfPresent(ExpenseRepeat.self, forKey: .repeatFrequency)
        endsOn = try? container.decodeIfPresent(String.self, forKey: .endsOn)
        installment = try? container.decodeIfPresent(ExpenseInstallment.self, forKey: .installment)
        clientId = try? container.decodeIfPresent(UUID.self, forKey: .clientId)
        version = try? container.decodeIfPresent(Int.self, forKey: .version)
    }
}

// MARK: - Expense Split Model
struct ExpenseSplit: Codable, Identifiable, Equatable {
    let id: Int
    let expenseId: Int
    let userId: Int
    let amount: Double
    /// The share this row was said to be, in percent units (`70`). Non-null on every row
    /// of a percentage expense, null everywhere else. Never used to derive `amount`.
    let percentage: Double?
    let user: User
}

// MARK: - Involvement
/// How one member stands on a timeline row. Only `lent` and `borrowed` move money
/// between people, so only they carry an amount.
enum ExpenseInvolvement: Equatable {
    case lent(Double)
    case borrowed(Double)
    case paidForYourself
    case notInvolved
    case payment
}

// MARK: - Grouped Expenses by Date
/// One day of the timeline. Identified by the normalized day rather than by
/// `dateString`: two days in different years share a label ("Apr 12, Sat"), and a
/// duplicated identity makes SwiftUI reuse the wrong section.
struct GroupedExpense: Identifiable {
    let date: Date
    let dateString: String
    let expenses: [Expense]

    var id: Date { date }
}

// MARK: - Extensions for Date Formatting and Calculations
extension Expense {
    /// The date the expense is filed under: the user-supplied one when there is one, the
    /// audit timestamp otherwise.
    var effectiveDate: Date? {
        Self.parseTimestamp(date ?? createdAt)
    }

    /// Parses the API's ISO-8601 timestamps, with and without fractional seconds.
    ///
    /// The shapes the API writes are read by hand first; anything else goes to the
    /// formatters, which decide it exactly as before.
    static func parseTimestamp(_ value: String) -> Date? {
        if let date = Self.readTimestamp(value) { return date }
        return parseTimestampWithFormatters(value)
    }

    /// The formatters are shared. Building one costs more than the parse it performs,
    /// and the timeline parses every loaded record. Even shared, a parse costs tens of
    /// microseconds, and a groups list or a timeline parses hundreds on the main thread.
    static func parseTimestampWithFormatters(_ value: String) -> Date? {
        if let date = fractionalISO8601Formatter.date(from: value) {
            return date
        }

        if let date = iso8601Formatter.date(from: value) {
            return date
        }

        var cleaned = value
        if let fractionRange = value.range(of: "\\.\\d+", options: .regularExpression) {
            cleaned = value.replacingCharacters(in: fractionRange, with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "Z", with: "")

        return zonelessUTCFormatter.date(from: cleaned)
    }

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// `yyyy-MM-ddTHH:mm:ss`, then optionally `.` and fractional digits, then `Z`, a
    /// `±HH:mm` offset, or nothing, read to the same instant the formatters give it: the
    /// fraction is cut to milliseconds, and with no zone it is UTC and the fraction is
    /// dropped. Nil for anything else, including a value the formatters read leniently
    /// (Feb 30, 24:00) or on the Julian calendar (before 1583), so those stay theirs.
    static func readTimestamp(_ value: String) -> Date? {
        var value = value
        return value.withUTF8(readTimestamp(bytes:))
    }

    private static func readTimestamp(bytes: UnsafeBufferPointer<UInt8>) -> Date? {
        let count = bytes.count
        guard count >= 19,
              bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"), bytes[10] == UInt8(ascii: "T"),
              bytes[13] == UInt8(ascii: ":"), bytes[16] == UInt8(ascii: ":")
        else { return nil }

        func digits(_ start: Int, _ length: Int) -> Int? {
            var value = 0
            for index in start..<(start + length) {
                let digit = Int(bytes[index]) - 48
                guard digit >= 0, digit <= 9 else { return nil }
                value = value * 10 + digit
            }
            return value
        }

        guard let year = digits(0, 4), let month = digits(5, 2), let day = digits(8, 2),
              let hour = digits(11, 2), let minute = digits(14, 2), let second = digits(17, 2),
              year >= 1900, (1...12).contains(month), hour <= 23, minute <= 59, second <= 59,
              day >= 1, day <= daysIn(month: month, year: year)
        else { return nil }

        var index = 19
        var milliseconds = 0
        if index < count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            let start = index
            while index < count, bytes[index] >= 48, bytes[index] <= 57 {
                if index - start < 3 { milliseconds = milliseconds * 10 + Int(bytes[index]) - 48 }
                index += 1
            }
            let read = index - start
            guard read > 0 else { return nil }
            for _ in min(read, 3)..<3 { milliseconds *= 10 }
        }

        let offset: Int
        if index == count {
            // No zone: UTC, whole seconds, the way the zoneless fallback reads it.
            offset = 0
            milliseconds = 0
        } else if bytes[index] == UInt8(ascii: "Z"), index + 1 == count {
            offset = 0
        } else if bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-"),
                  index + 6 == count, bytes[index + 3] == UInt8(ascii: ":"),
                  let offsetHours = digits(index + 1, 2), let offsetMinutes = digits(index + 4, 2),
                  offsetHours <= 14, offsetMinutes <= 59 {
            let magnitude = offsetHours * 3_600 + offsetMinutes * 60
            offset = bytes[index] == UInt8(ascii: "-") ? -magnitude : magnitude
        } else {
            return nil
        }

        let seconds = daysSince1970(year: year, month: month, day: day) * 86_400
            + hour * 3_600 + minute * 60 + second - offset
        // The same arithmetic the formatters do: milliseconds since 1970, then seconds since 2001.
        let since1970Milliseconds = Double(seconds * 1_000 + milliseconds)
        return Date(timeIntervalSinceReferenceDate: since1970Milliseconds / 1_000 - Date.timeIntervalBetween1970AndReferenceDate)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days from 1970-01-01 to a proleptic Gregorian date (Howard Hinnant's `days_from_civil`).
    private static func daysSince1970(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = shiftedYear / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Timestamps serialized without a zone marker are UTC, like every other one.
    private static let zonelessUTCFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    var dayString: String {
        Self.dayLabel(for: effectiveDate)
    }

    /// The section heading for an already-parsed date. Takes `now` so the relative
    /// labels can be tested without waiting for midnight.
    static func dayLabel(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return L10n.Expense.unknownDay }

        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return L10n.Common.today
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return L10n.Common.yesterday
        }
        // Built per call rather than cached: the app's language can change while the
        // timeline is open, and a format style is cheap where a formatter is not.
        return date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated).inAppLanguage())
    }
    
    /// The counterparty on a settlement: the split that is not the payer's, which is the
    /// shape every settlement is built with (`[+amount, -amount]`).
    var peer: User? {
        splits.first { $0.userId != paidBy }?.user
    }

    // Calculate the expense split for the current user
    func getUserSplit(currentUserId: Int) -> Double {
        // Find the current user's split
        let userSplit = splits.first { $0.userId == currentUserId }
        let userOwes = userSplit?.amount ?? 0.0
        
        // If the current user paid, they lent money
        if paidBy == currentUserId {
            return amount - userOwes // Amount they lent (total - what they owe themselves)
        } else {
            return -userOwes // Amount they owe (negative)
        }
    }
    
    /// Where `userId` stands on this row. A payer whose lent amount is zero paid only for
    /// themselves, which is not a loan.
    func involvement(of userId: Int) -> ExpenseInvolvement {
        let isPayer = paidBy == userId
        guard isPayer || splits.contains(where: { $0.userId == userId }) else { return .notInvolved }
        if type == .payment { return .payment }

        let split = getUserSplit(currentUserId: userId)
        if isPayer { return split == 0 ? .paidForYourself : .lent(split) }
        return .borrowed(-split)
    }

    // Get display information for UI
    func getDisplayInfo(currentUserId: Int) -> (isUserPaid: Bool, userSplit: Double) {
        let isUserPaid = paidBy == currentUserId
        let userSplit = splits.first { $0.userId == currentUserId }?.amount ?? 0.0
        return (isUserPaid, userSplit)
    }
    
    /// Builds the whole timeline in one pass and hands back a finished snapshot.
    ///
    /// Each record's timestamp is parsed exactly once. Reading `effectiveDate` from
    /// inside the grouping key and the sort comparison parses the same string O(n log n)
    /// times, which is what made a 500-row group expensive to open.
    static func groupExpensesByDate(_ expenses: [Expense], now: Date = Date()) -> [GroupedExpense] {
        let calendar = Calendar.current
        let dated = expenses.map { (expense: $0, date: $0.effectiveDate) }

        // An unparsable timestamp still belongs on screen: it files under the oldest
        // possible day, under the label the row itself would have shown.
        let grouped = Dictionary(grouping: dated) { entry in
            entry.date.map(calendar.startOfDay(for:)) ?? Date.distantPast
        }

        return grouped.map { day, entries in
            let sorted = entries.sorted { first, second in
                guard let firstDate = first.date, let secondDate = second.date else { return false }
                return firstDate > secondDate
            }

            return GroupedExpense(
                date: day,
                dateString: dayLabel(for: sorted.first?.date, now: now),
                expenses: sorted.map(\.expense)
            )
        }.sorted { $0.date > $1.date }
    }
}
