//
//  SettleUpViewModel.swift
//  Splitty
//

import Foundation

struct SettleUpResult {
    let payerId: Int
    let payeeId: Int
    let amountCents: Int
    let date: Date
    let settlementId: Int?
    /// True when this payment brings the current user's net balance in the group to zero.
    var settlesUp = false
    /// The id the payment was sent under, which matches it to the server's row (ADR 0008).
    var clientId: UUID? = nil
    /// True when it was kept to send later rather than recorded now.
    var queued = false
}

struct SettleUpDataSource {
    /// Group, payer, payee, amount in cents, date.
    var create: (Int, Int, Int, Int, Date) async throws -> Void
    /// Group, payment, amount in cents, date.
    var update: (Int, Int, Int, Date) async throws -> Void
    /// Sends a new payment through the outbox instead of `create`, when set. Group, payer,
    /// payee, amount in cents, date.
    var send: ((Int, Int, Int, Int, Date) async throws -> SettleUpSend)? = nil

    static let live = SettleUpDataSource(
        create: { groupId, payerId, payeeId, amountCents, date in
            try await SettlementService.shared.settleUp(
                groupId: groupId,
                fromUserId: payerId,
                toUserId: payeeId,
                amountCents: amountCents,
                date: date
            )
        },
        update: { groupId, expenseId, amountCents, date in
            try await SettlementService.shared.updateSettlement(
                groupId: groupId,
                expenseId: expenseId,
                amountCents: amountCents,
                date: date
            )
        }
    )
}

@MainActor
final class SettleUpViewModel: ObservableObject {
    @Published var amount: AmountExpression
    @Published var date: Date
    /// Who paid and who was paid, picked the way an expense's payer is. Any member may record
    /// a payment between any two members (ADR 0010), so neither has to be the current user.
    @Published private(set) var payerId: Int?
    @Published private(set) var payeeId: Int?
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    private let session: GroupSession
    var groupId: Int { session.groupId }
    var members: [GroupMember] { session.members }
    let currentUserId: Int

    private let settlementId: Int?
    /// The edited payment's amount. An edit changes the amount and date, never the sides.
    private let originalCents: Int?
    /// Set once the sides came from somewhere other than a suggestion: a balance row, the
    /// payment being edited, or the member's own pick. A later suggestion leaves them alone.
    private var partiesAreChosen: Bool
    private let dataSource: SettleUpDataSource

    init(
        session: GroupSession,
        currentUserId: Int,
        preselectedRow: BalanceRow? = nil,
        settlement: Expense? = nil,
        dataSource: SettleUpDataSource = .live
    ) {
        self.session = session
        self.currentUserId = currentUserId
        settlementId = settlement?.id
        self.dataSource = dataSource
        date = settlement?.effectiveDate ?? Date()

        if let settlement {
            originalCents = Money.cents(from: settlement.amount)
            amount = AmountExpression(cents: Money.cents(from: settlement.amount))
            payerId = settlement.paidBy
            payeeId = settlement.peer?.id
            partiesAreChosen = true
        } else if let preselectedRow {
            originalCents = nil
            amount = AmountExpression()
            payerId = preselectedRow.from.id
            payeeId = preselectedRow.to.id
            partiesAreChosen = true
        } else {
            originalCents = nil
            amount = AmountExpression()
            partiesAreChosen = false
        }
    }

    var balancesPending: Bool { session.balancesPending }
    /// The session's debts with this device's unsent writes counted, so a payment recorded
    /// offline is measured against what is really owed.
    private var debts: [SimplifiedDebt] { session.displaySummary?.simplifiedDebts ?? [] }
    /// Every member's net, positive when owed. Greedy simplification carries each net
    /// exactly, so this is the same position the server's cap reads.
    private var nets: [Int: Int] { LedgerMath.nets(from: debts) }

    var isEditing: Bool { settlementId != nil }
    var amountCents: Int { amount.resolvedCents }
    var canSubmit: Bool {
        // Pending balances no longer block a payment: the server caps it against the rows,
        // not the stored balances (ADR 0009).
        payer != nil && payee != nil && payerId != payeeId && amountCents > 0 && !isSubmitting
    }

    /// The simplified debt from one member to another, as Balances shows it.
    func pairCents(from payer: Int, to payee: Int) -> Int? {
        debts.filter { $0.from.id == payer && $0.to.id == payee }.map(\.amountCents).max()
    }

    /// A member's net, positive when the group owes them.
    func netCents(of userId: Int) -> Int { nets[userId] ?? 0 }

    var payer: GroupMember? { member(payerId) }
    var payee: GroupMember? { member(payeeId) }

    /// The current user first, the way the expense form's Paid by lists them.
    var choices: [GroupMember] {
        members.sorted { lhs, rhs in
            if (lhs.userId == currentUserId) != (rhs.userId == currentUserId) { return lhs.userId == currentUserId }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// The most this payment may be: what the payer owes the group, but no more than the
    /// payee is owed. The same cap the server applies (invariant 5).
    var capCents: Int {
        guard let payerId, let payeeId, payerId != payeeId else { return 0 }
        return LedgerMath.cap(nets, payer: payerId, payee: payeeId)
    }

    /// What Pay all fills in: the suggested debt between the two, as Balances shows it, or
    /// the cap for two members the simplified debts do not pair. Never above the cap.
    var fullAmountCents: Int {
        guard let payerId, let payeeId else { return 0 }
        return min(pairCents(from: payerId, to: payeeId) ?? capCents, capCents)
    }

    var payAllTitle: String? {
        guard fullAmountCents > 0 else { return nil }
        let amount = Money.formatted(cents: fullAmountCents, currency: session.currency)
        return payerId == currentUserId ? L10n.Settlement.payAll(amount) : L10n.Settlement.fullAmount(amount)
    }

    func name(of member: GroupMember) -> String {
        member.userId == currentUserId ? L10n.Common.you : MemberDisplay(member).name
    }

    /// How this submission moves the current user's net balance: up when they pay, down
    /// when they are paid, not at all when they are neither side. An edit moves it only by
    /// the difference.
    private var netChange: Int {
        let sign = payerId == currentUserId ? 1 : payeeId == currentUserId ? -1 : 0
        return sign * (amountCents - (originalCents ?? 0))
    }

    func setPayer(_ userId: Int) {
        guard !isEditing, userId != payerId else { return }
        // Picking the payee as the payer swaps the two, like the swap button.
        if userId == payeeId { payeeId = payerId }
        payerId = userId
        partiesChanged()
    }

    func setPayee(_ userId: Int) {
        guard !isEditing, userId != payeeId else { return }
        if userId == payerId { payerId = payeeId }
        payeeId = userId
        partiesChanged()
    }

    func swapParties() {
        guard !isEditing else { return }
        (payerId, payeeId) = (payeeId, payerId)
        partiesChanged()
    }

    private func partiesChanged() {
        partiesAreChosen = true
        errorMessage = nil
    }

    func payAll() {
        guard fullAmountCents > 0 else { return }
        amount.replaceEntry(cents: fullAmountCents)
    }

    func loadDebts() async {
        guard !isEditing else { return }
        _ = try? await session.summaryForSettleUp()
        suggestPayment()
    }

    /// Suggests the two sides, never an amount: the entry stays the member's until Pay all.
    /// The current user's own largest debt comes first, then the largest owed to them, then
    /// any debt in the group, and with none the current user paying someone.
    func suggestPayment() {
        guard !isEditing, !partiesAreChosen else { return }
        let known = Set(members.map(\.userId))
        let live = debts.filter { known.contains($0.from.id) && known.contains($0.to.id) }
            .sorted { $0.amountCents > $1.amountCents }
        let suggestion = live.first { $0.from.id == currentUserId }
            ?? live.first { $0.to.id == currentUserId }
            ?? live.first
        if let suggestion {
            payerId = suggestion.from.id
            payeeId = suggestion.to.id
        } else {
            payerId = currentUserId
            payeeId = choices.first { $0.userId != currentUserId }?.userId
        }
    }

    func submit() async -> SettleUpResult? {
        guard canSubmit, let payerId, let payeeId else { return nil }
        // Read before the write: the session's summary is stale once it reports the payment.
        let net = nets[currentUserId] ?? 0
        let settlesUp = net != 0 && net + netChange == 0

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            var sent: SettleUpSend?
            if let settlementId {
                try await dataSource.update(groupId, settlementId, amountCents, date)
            } else if let send = dataSource.send {
                sent = try await send(groupId, payerId, payeeId, amountCents, date)
            } else {
                try await dataSource.create(groupId, payerId, payeeId, amountCents, date)
            }
            var result = SettleUpResult(payerId: payerId, payeeId: payeeId,
                                        amountCents: amountCents, date: date,
                                        settlementId: settlementId, settlesUp: settlesUp)
            switch sent {
            case .confirmed(let clientId): result.clientId = clientId
            case .queued(let clientId):
                result.clientId = clientId
                result.queued = true
            case nil: break
            }
            return result
        } catch {
            recordSubmissionFailure(error)
            return nil
        }
    }

    func recordSubmissionFailure(_ error: Error) {
        // The server's cap is current; the debts on screen may predate another payment.
        if case .settlementExceedsCap(let cap, _) = error as? APIError, cap > 0, let message = onlyOwesMessage(cents: cap) {
            errorMessage = message
            return
        }
        if !isEditing, capCents > 0, capCents < amountCents, let message = onlyOwesMessage(cents: capCents) {
            errorMessage = message
        } else {
            errorMessage = L10n.Settlement.recordFailed
        }
    }

    private func onlyOwesMessage(cents: Int) -> String? {
        guard let payer, let payee else { return nil }
        let amount = Money.formatted(cents: cents, currency: session.currency)
        if payer.userId == currentUserId { return L10n.Settlement.onlyOwe(MemberDisplay(payee).name, amount) }
        if payee.userId == currentUserId { return L10n.Settlement.onlyOwesYou(MemberDisplay(payer).name, amount) }
        return L10n.Settlement.onlyOwesPeer(MemberDisplay(payer).name, MemberDisplay(payee).name, amount)
    }

    private func member(_ userId: Int?) -> GroupMember? {
        guard let userId else { return nil }
        return members.first { $0.userId == userId }
    }
}
