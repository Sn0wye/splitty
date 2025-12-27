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
    var formattedDate: Date? {
        // Use ISO8601DateFormatter for robust parsing
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = iso8601Formatter.date(from: createdAt) {
            return date
        }
        
        // Fallback to without fractional seconds
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: createdAt) {
            return date
        }
        
        // Last resort: try manual DateFormatter
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        
        // Strip fractional seconds if present
        var cleanedDate = createdAt
        if let dotRange = createdAt.range(of: "\\.\\d+Z", options: .regularExpression) {
            cleanedDate = createdAt.replacingCharacters(in: dotRange, with: "Z")
        }
        
        if let date = formatter.date(from: cleanedDate) {
            return date
        }
        
        print("❌ Failed to parse date: \(createdAt)")
        return nil
    }
    
    var dayString: String {
        guard let date = formattedDate else { return "Unknown" }
        
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
            guard let date = expense.formattedDate else { return Date.distantPast }
            return calendar.startOfDay(for: date)
        }
        
        return grouped.compactMap { (date, expenses) in
            let sortedExpenses = expenses.sorted { expense1, expense2 in
                guard let date1 = expense1.formattedDate,
                      let date2 = expense2.formattedDate else { return false }
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
