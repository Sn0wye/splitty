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

// MARK: - Expense Model
struct Expense: Codable, Identifiable {
    let id: Int
    let groupId: Int
    let paidBy: Int
    let amount: Double
    let description: String
    let type: ExpenseType
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

    enum CodingKeys: String, CodingKey {
        case id, groupId, paidBy, amount, description, type, splitMode, date
        case createdAt, updatedAt, paidByUser, splits
    }
}

extension Expense {
    /// Decoded by hand for one field: an unrecognised `splitMode` becomes `nil` rather
    /// than throwing. A mode added by a newer client must not fail the whole group's
    /// expense list over a value this build has no opinion about.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        groupId = try container.decode(Int.self, forKey: .groupId)
        paidBy = try container.decode(Int.self, forKey: .paidBy)
        amount = try container.decode(Double.self, forKey: .amount)
        description = try container.decode(String.self, forKey: .description)
        type = try container.decode(ExpenseType.self, forKey: .type)
        splitMode = try? container.decodeIfPresent(ExpenseSplitMode.self, forKey: .splitMode)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        paidByUser = try container.decode(User.self, forKey: .paidByUser)
        splits = try container.decode([ExpenseSplit].self, forKey: .splits)
    }
}

// MARK: - Expense Split Model
struct ExpenseSplit: Codable, Identifiable {
    let id: Int
    let expenseId: Int
    let userId: Int
    let amount: Double
    /// The share this row was said to be, in percent units (`70`). Non-null on every row
    /// of a percentage expense, null everywhere else. Never used to derive `amount`.
    let percentage: Double?
    let user: User
}

// MARK: - Grouped Expenses by Date
struct GroupedExpense {
    let date: Date
    let dateString: String
    let expenses: [Expense]
}

// MARK: - Extensions for Date Formatting and Calculations
extension Expense {
    /// The date the expense is filed under: the user-supplied one when there is one, the
    /// audit timestamp otherwise.
    var effectiveDate: Date? {
        Self.parseTimestamp(date ?? createdAt)
    }

    /// Parses the API's ISO-8601 timestamps, with and without fractional seconds.
    static func parseTimestamp(_ value: String) -> Date? {
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = iso8601Formatter.date(from: value) {
            return date
        }

        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: value) {
            return date
        }

        // Timestamps serialized without a zone marker are UTC, like every other one.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        var cleaned = value
        if let fractionRange = value.range(of: "\\.\\d+", options: .regularExpression) {
            cleaned = value.replacingCharacters(in: fractionRange, with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "Z", with: "")

        return formatter.date(from: cleaned)
    }

    var dayString: String {
        guard let date = effectiveDate else { return "Unknown" }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, E" // Apr 12, Sat
            return formatter.string(from: date)
        }
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
    
    // Get display information for UI
    func getDisplayInfo(currentUserId: Int) -> (isUserPaid: Bool, userSplit: Double) {
        let isUserPaid = paidBy == currentUserId
        let userSplit = splits.first { $0.userId == currentUserId }?.amount ?? 0.0
        return (isUserPaid, userSplit)
    }
    
    static func groupExpensesByDate(_ expenses: [Expense]) -> [GroupedExpense] {
        let calendar = Calendar.current
        
        let grouped = Dictionary(grouping: expenses) { expense in
            guard let date = expense.effectiveDate else { return Date.distantPast }
            return calendar.startOfDay(for: date)
        }
        
        return grouped.compactMap { (date, expenses) in
            let sortedExpenses = expenses.sorted { expense1, expense2 in
                guard let date1 = expense1.effectiveDate,
                      let date2 = expense2.effectiveDate else { return false }
                return date1 > date2
            }
            
            let expense = expenses.first!
            return GroupedExpense(
                date: date,
                dateString: expense.dayString,
                expenses: sortedExpenses
            )
        }.sorted { $0.date > $1.date }
    }
}
