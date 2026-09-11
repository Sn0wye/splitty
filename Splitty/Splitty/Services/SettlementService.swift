//
//  SettlementService.swift
//  Splitty
//

import Foundation

/// A settlement is stored as an `Expense` with `type == .payment`, but it is mutated
/// through its own routes: the expense `PUT`/`DELETE` refuse payment rows rather than
/// branching on a field the client never sent.
class SettlementService {
    static let shared = SettlementService()

    private init() {}

    func settleUp(groupId: Int, withUserId: Int, amountCents: Int, date: Date) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/settle",
            method: .POST,
            body: [
                "withUserId": withUserId,
                "amount": Money.requestValue(cents: amountCents),
                "date": ExpenseService.timestamp(from: date)
            ]
        )
    }

    /// A nil date leaves the stored date unchanged.
    func updateSettlement(
        groupId: Int,
        expenseId: Int,
        amountCents: Int,
        date: Date? = nil
    ) async throws {
        var body: [String: Any] = ["amount": Money.requestValue(cents: amountCents)]
        if let date { body["date"] = ExpenseService.timestamp(from: date) }

        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/settlements/\(expenseId)",
            method: .PUT,
            body: body
        )
    }

    func deleteSettlement(groupId: Int, expenseId: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/settlements/\(expenseId)",
            method: .DELETE
        )
    }
}
