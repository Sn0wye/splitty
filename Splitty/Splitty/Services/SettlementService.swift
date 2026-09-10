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

    func settleUp(groupId: Int, withUserId: Int, amountCents: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/settle",
            method: .POST,
            body: [
                "withUserId": withUserId,
                "amount": Money.requestValue(cents: amountCents)
            ]
        )
    }

    /// Leaves the stored date alone. The edit route treats an absent date as "keep it",
    /// and the amount screen has no date control to imply otherwise.
    func updateSettlement(groupId: Int, expenseId: Int, amountCents: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/settlements/\(expenseId)",
            method: .PUT,
            body: ["amount": Money.requestValue(cents: amountCents)]
        )
    }

    func deleteSettlement(groupId: Int, expenseId: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/settlements/\(expenseId)",
            method: .DELETE
        )
    }
}
