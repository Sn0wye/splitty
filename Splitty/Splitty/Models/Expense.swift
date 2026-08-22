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

// MARK: - Expense Model
struct Expense: Codable, Identifiable {
    let id: Int
    let groupId: Int
    let paidBy: Int
    let amount: Double
    let description: String
    let type: ExpenseType
    /// When the expense happened, as the user says it did. Nullable: rows written before
    /// the column existed have no user-supplied date, so every reader falls back to
    /// `createdAt`.
    let date: String?
    let createdAt: String
    let updatedAt: String
    let paidByUser: User
    let splits: [ExpenseSplit]
}

// MARK: - Expense Split Model
struct ExpenseSplit: Codable, Identifiable {
    let id: Int
    let expenseId: Int
    let userId: Int
    let amount: Double
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
