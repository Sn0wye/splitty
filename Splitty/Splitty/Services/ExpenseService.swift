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
        amount: Double,
        paidBy: Int,
        date: Date?,
        splits: [ExpenseSplitRequest]
    ) async throws -> Expense {
        var body: [String: Any] = [
            "groupId": groupId,
            "description": description,
            "amount": amount,
            "paidBy": paidBy,
            "splits": splits.map { ["userId": $0.userId, "amount": $0.amount] }
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
        amount: Double? = nil,
        paidBy: Int? = nil,
        date: Date? = nil,
        splits: [ExpenseSplitRequest]? = nil
    ) async throws -> Expense {
        var body: [String: Any] = [:]
        if let description { body["description"] = description }
        if let amount { body["amount"] = amount }
        if let paidBy { body["paidBy"] = paidBy }
        if let date { body["date"] = Self.timestamp(from: date) }
        if let splits {
            body["splits"] = splits.map { ["userId": $0.userId, "amount": $0.amount] }
        }

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

    /// UTC, no fractional seconds. The API reads a timestamp without an offset as already
    /// UTC, so sending one with an offset is what keeps the stored instant unambiguous.
    static func timestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
