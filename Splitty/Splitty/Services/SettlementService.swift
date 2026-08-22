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

    func deleteSettlement(groupId: Int, expenseId: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/settlements/\(expenseId)",
            method: .DELETE
        )
    }
}
