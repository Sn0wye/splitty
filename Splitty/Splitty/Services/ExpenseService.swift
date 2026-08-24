//
//  ExpenseService.swift
//  Splitty
//
//  Created by Snowye on 19/11/25.
//

import Foundation

class ExpenseService {
    static let shared = ExpenseService()
    
    private init() {}
    
    func getExpenses(groupId: Int) async throws -> [Expense] {
        try await APIClient.shared.request(endpoint: "/group/\(groupId)/expenses")
    }
    
    func getExpense(groupId: Int, expenseId: Int) async throws -> Expense {
        try await APIClient.shared.request(endpoint: "/group/\(groupId)/expenses/\(expenseId)")
    }
    
    func createExpense(
        groupId: Int,
        description: String,
        amountCents: Int,
        paidBy: Int,
        date: Date?,
        splitMode: ExpenseSplitMode,
        splits: [ExpenseSplitRequest]
    ) async throws -> Expense {
        var body: [String: Any] = [
            "groupId": groupId,
            "description": description,
            "amount": Money.requestValue(cents: amountCents),
            "paidBy": paidBy,
            "splitMode": splitMode.rawValue,
            "splits": splits.map(Self.splitBody(_:))
        ]
        if let date { body["date"] = Self.timestamp(from: date) }

        return try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/expenses",
            method: .POST,
            body: body
        )
    }
    
    func updateExpense(
        groupId: Int,
        expenseId: Int,
        description: String? = nil,
        amountCents: Int? = nil,
        paidBy: Int? = nil,
        date: Date? = nil,
        splitMode: ExpenseSplitMode? = nil,
        splits: [ExpenseSplitRequest]? = nil
    ) async throws -> Expense {
        var body: [String: Any] = [:]
        if let description { body["description"] = description }
        if let amountCents { body["amount"] = Money.requestValue(cents: amountCents) }
        if let paidBy { body["paidBy"] = paidBy }
        if let date { body["date"] = Self.timestamp(from: date) }
        // The rows and the mode naming them are one fact: an update sending splits without
        // a mode is rejected, so they travel together or not at all.
        if let splitMode { body["splitMode"] = splitMode.rawValue }
        if let splits { body["splits"] = splits.map(Self.splitBody(_:)) }

        return try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/expenses/\(expenseId)",
            method: .PUT,
            body: body
        )
    }
    
    /// The expense routes refuse `payment` rows; a settlement is deleted through
    /// `SettlementService`.
    func deleteExpense(groupId: Int, expenseId: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/expenses/\(expenseId)",
            method: .DELETE
        )
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
