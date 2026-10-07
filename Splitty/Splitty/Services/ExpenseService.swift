//
//  ExpenseService.swift
//  Splitty
//
//  Created by Snowye on 19/11/25.
//

import Foundation

/// A new expense as the form built it.
struct NewExpenseRequest: Equatable {
    let groupId: Int
    let description: String
    let amountCents: Int
    let paidBy: Int
    let date: Date?
    let category: ExpenseCategory
    let splitMode: ExpenseSplitMode
    let splits: [ExpenseSplitRequest]
    /// Nil unless it repeats: `never` is the server's default, so it is not sent.
    var repeatFrequency: ExpenseRepeat? = nil
    /// The IANA zone the repeats come due in. Sent only with `repeatFrequency`.
    var timeZone: String? = nil
}

/// An edit. Every nil field is left unchanged by the server.
struct ExpenseUpdateRequest: Equatable {
    let groupId: Int
    let expenseId: Int
    var description: String? = nil
    var amountCents: Int? = nil
    var paidBy: Int? = nil
    var date: Date? = nil
    var category: ExpenseCategory? = nil
    var splitMode: ExpenseSplitMode? = nil
    var splits: [ExpenseSplitRequest]? = nil
    /// Nil for an expense entered by hand, whose edit has nothing to reach past it.
    var scope: ExpenseScope? = nil
    /// A new frequency, or `never` to stop. Only ever sent with `.following`.
    var repeatFrequency: ExpenseRepeat? = nil
}

class ExpenseService {
    static let shared = ExpenseService()
    
    private init() {}
    
    func getExpenses(groupId: Int) async throws -> [Expense] {
        try await APIClient.shared.request(endpoint: "/group/\(groupId)/expenses")
    }
    
    func getExpense(groupId: Int, expenseId: Int) async throws -> Expense {
        try await APIClient.shared.request(endpoint: "/group/\(groupId)/expenses/\(expenseId)")
    }
    
    func createExpense(_ request: NewExpenseRequest) async throws -> Expense {
        var body: [String: Any] = [
            "groupId": request.groupId,
            "description": request.description,
            "amount": Money.requestValue(cents: request.amountCents),
            "paidBy": request.paidBy,
            "category": request.category.rawValue,
            "splitMode": request.splitMode.rawValue,
            "splits": request.splits.map(Self.splitBody(_:))
        ]
        if let date = request.date { body["date"] = Self.timestamp(from: date) }
        if let repeatFrequency = request.repeatFrequency { body["repeat"] = repeatFrequency.rawValue }
        if let timeZone = request.timeZone { body["timeZone"] = timeZone }

        return try await APIClient.shared.request(
            endpoint: "/group/\(request.groupId)/expenses",
            method: .POST,
            body: body
        )
    }

    func updateExpense(_ request: ExpenseUpdateRequest) async throws -> Expense {
        var body: [String: Any] = [:]
        if let description = request.description { body["description"] = description }
        if let amountCents = request.amountCents { body["amount"] = Money.requestValue(cents: amountCents) }
        if let paidBy = request.paidBy { body["paidBy"] = paidBy }
        if let date = request.date { body["date"] = Self.timestamp(from: date) }
        if let category = request.category { body["category"] = category.rawValue }
        // The rows and the mode naming them are one fact: an update sending splits without
        // a mode is rejected, so they travel together or not at all.
        if let splitMode = request.splitMode { body["splitMode"] = splitMode.rawValue }
        if let splits = request.splits { body["splits"] = splits.map(Self.splitBody(_:)) }
        if let repeatFrequency = request.repeatFrequency { body["repeat"] = repeatFrequency.rawValue }

        return try await APIClient.shared.request(
            endpoint: "/group/\(request.groupId)/expenses/\(request.expenseId)" + Self.query(request.scope),
            method: .PUT,
            body: body
        )
    }
    
    /// The expense routes refuse `payment` rows; a settlement is deleted through
    /// `SettlementService`.
    func deleteExpense(groupId: Int, expenseId: Int, scope: ExpenseScope? = nil) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/expenses/\(expenseId)" + Self.query(scope),
            method: .DELETE
        )
    }

    /// No scope means the route's default, `this`, which is all a plain expense has.
    private static func query(_ scope: ExpenseScope?) -> String {
        scope.map { "?scope=\($0.rawValue)" } ?? ""
    }

    /// A split row. `percentage` is omitted rather than sent as null when there is none:
    /// the API stores null either way, and an absent key says the same thing in less JSON.
    private static func splitBody(_ split: ExpenseSplitRequest) -> [String: Any] {
        var body: [String: Any] = [
            "userId": split.userId,
            "amount": Money.requestValue(cents: split.amountCents)
        ]
        if let percentage = split.percentage {
            body["percentage"] = NSDecimalNumber(decimal: percentage)
        }
        return body
    }

    /// UTC, no fractional seconds. The API reads a timestamp without an offset as already
    /// UTC, so sending one with an offset is what keeps the stored instant unambiguous.
    static func timestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
