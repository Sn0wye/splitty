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

    /// Records `fromUserId` paying `toUserId` and answers with the settlement the server
    /// recorded. Either may be the current user: the payer records "I paid", the payee "I was
    /// paid". A nil `fromUserId` sends the older shape, which means the current user paid; a
    /// queued draft saved before either side could record has no payer. `clientId` makes a
    /// resend safe: the server answers a settlement it already stored with that row (ADR 0008).
    @discardableResult
    func settleUp(
        groupId: Int,
        fromUserId: Int?,
        toUserId: Int,
        amountCents: Int,
        date: Date,
        clientId: UUID? = nil,
        currency: Currency? = nil
    ) async throws -> Expense {
        var body: [String: Any] = [
            "amount": Money.requestValue(cents: amountCents),
            "date": ExpenseService.timestamp(from: date)
        ]
        if let fromUserId {
            body["fromUserId"] = fromUserId
            body["toUserId"] = toUserId
        } else {
            body["withUserId"] = toUserId
        }
        if let clientId { body["clientId"] = clientId.uuidString }
        if let currency { body["currency"] = currency.rawValue }
        return try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/settle",
            method: .POST,
            body: body
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
