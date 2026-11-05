//
//  SettleUpViewModel.swift
//  Splitty
//

import Foundation

/// Which way a new payment goes, seen from the current user. A net debtor pays the group's
/// net creditors; a net creditor records being paid by its net debtors. Nobody is both, so
/// the user's own position decides the direction and the peer list needs no toggle.
enum SettleDirection: Equatable {
    case youPay
    case youReceive
}

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
    @Published private(set) var selectedPeerId: Int?
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    private let session: GroupSession
    var groupId: Int { session.groupId }
    var members: [GroupMember] { session.members }
    let currentUserId: Int

    private let settlementId: Int?
    /// The edited payment as it stands: its amount and its two sides. Any member may edit
    /// it, so the current user can be the payer, the payee, or neither.
    private let original: (cents: Int, payerId: Int, payeeId: Int)?
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
        original = settlement.flatMap { settlement in
            settlement.peer.map { (Money.cents(from: settlement.amount), settlement.paidBy, $0.id) }
        }
        self.dataSource = dataSource

        if let settlement {
            amount = AmountExpression(cents: Money.cents(from: settlement.amount))
            date = settlement.effectiveDate ?? Date()
            // The other side from the current user's; the payer when they are neither.
            selectedPeerId = settlement.paidBy == currentUserId ? settlement.peer?.id : settlement.paidBy
        } else if let preselectedRow {
            amount = AmountExpression()
            date = Date()
            selectedPeerId = preselectedRow.involvement == .paysYou ? preselectedRow.from.id : preselectedRow.to.id
        } else {
            amount = AmountExpression()
            date = Date()
            selectedPeerId = nil
        }
    }

    var balancesPending: Bool { session.balancesPending }
    /// The session's debts with this device's unsent writes counted, so a payment recorded
    /// offline is measured against what is really owed.
    private var debts: [SimplifiedDebt] { session.displaySummary?.simplifiedDebts ?? [] }

    /// Nil for a settled user, who has nothing to record, and for an edit of a payment
    /// between two other members.
    var direction: SettleDirection? {
        if let original {
            if original.payerId == currentUserId { return .youPay }
            if original.payeeId == currentUserId { return .youReceive }
            return nil
        }
        if netCents < 0 { return .youPay }
        if netCents > 0 { return .youReceive }
        return nil
    }

    /// The members on the other side of the group from the current user. The cap reads
    /// net positions, not pairs, so this is every net creditor (or debtor), including one
    /// the user never shared an expense with.
    private var settleablePeerIds: Set<Int> {
        let ids: [Int] = switch direction {
        case .youPay: debts.map(\.to.id)
        case .youReceive: debts.map(\.from.id)
        case nil: []
        }
        return Set(ids.filter { $0 != currentUserId })
    }

    var isEditing: Bool { settlementId != nil }
    var amountCents: Int { amount.resolvedCents }
    var canSubmit: Bool {
        // Pending balances no longer block a payment: the server caps it against the rows,
        // not the stored balances (ADR 0009).
        selectedPeer != nil && amountCents > 0 && !isSubmitting
    }

    var selectedPeer: GroupMember? {
        guard let selectedPeerId else { return nil }
        return members.first { $0.userId == selectedPeerId && (isEditing || settleablePeerIds.contains($0.userId)) }
    }

    var peers: [GroupMember] {
        members
            .filter { $0.userId != currentUserId && (isEditing || settleablePeerIds.contains($0.userId)) }
            .sorted { lhs, rhs in
                let lhsDebt = debtCents(for: lhs.userId) ?? 0
                let rhsDebt = debtCents(for: rhs.userId) ?? 0
                if (lhsDebt > 0) != (rhsDebt > 0) { return lhsDebt > 0 }
                if lhsDebt != rhsDebt { return lhsDebt > rhsDebt }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    /// The amount screen's heading: who pays whom, from where the current user stands.
    var heading: String {
        let name = selectedPeer.map { MemberDisplay($0).name } ?? L10n.Common.member
        guard let original else {
            return direction == .youReceive ? L10n.Settlement.paidYou(name) : L10n.Settlement.pay(name)
        }
        guard direction == nil else { return L10n.Settlement.paymentWith(name) }
        return L10n.Group.payerPaidPayee(displayName(of: original.payerId), displayName(of: original.payeeId))
    }

    var payAllTitle: String? {
        guard let selectedPeerId,
              let cents = debtCents(for: selectedPeerId),
              cents > 0
        else { return nil }
        let amount = Money.formatted(cents: cents, currency: session.currency)
        return direction == .youReceive ? L10n.Settlement.fullAmount(amount) : L10n.Settlement.payAll(amount)
    }

    /// The current user's net balance across the simplified debts: positive when owed.
    private var netCents: Int {
        debts.reduce(0) { net, debt in
            if debt.to.id == currentUserId { return net + debt.amountCents }
            if debt.from.id == currentUserId { return net - debt.amountCents }
            return net
        }
    }

    /// How this submission moves the current user's net balance: up when they pay, down
    /// when they are paid. An edit moves it only by the difference, and not at all when
    /// the current user is neither side.
    private var netChange: Int {
        let sign = switch direction {
        case .youPay: 1
        case .youReceive: -1
        case nil: 0
        }
        guard let original else { return sign * amountCents }
        return sign * (amountCents - original.cents)
    }

    /// The simplified debt between the current user and the peer, in the direction the
    /// user settles: what they owe the peer, or what the peer owes them.
    func debtCents(for peerId: Int) -> Int? {
        debts.filter { counterpart(in: $0) == peerId }.map(\.amountCents).max()
    }

    private func counterpart(in debt: SimplifiedDebt) -> Int? {
        switch direction {
        case .youPay: debt.from.id == currentUserId ? debt.to.id : nil
        case .youReceive: debt.to.id == currentUserId ? debt.from.id : nil
        case nil: nil
        }
    }

    private func displayName(of userId: Int) -> String {
        if userId == currentUserId { return L10n.Common.you }
        return members.first { $0.userId == userId }.map { MemberDisplay($0).name } ?? L10n.Common.member
    }

    func select(peerId: Int) {
        guard !isEditing,
              settleablePeerIds.contains(peerId),
              members.contains(where: { $0.userId == peerId })
        else { return }
        selectedPeerId = peerId
        // A new payment starts empty; Pay all fills in the debt.
        amount.clear()
        errorMessage = nil
    }

    func payAll() {
        guard let selectedPeerId, let cents = debtCents(for: selectedPeerId), cents > 0 else { return }
        amount.replaceEntry(cents: cents)
    }

    func loadDebts() async {
        guard !isEditing else { return }
        _ = try? await session.summaryForSettleUp()
        suggestPayment()
    }

    /// Only the peer choice and amount entry belong to this screen; debts stay in the session.
    /// Suggests a peer, never an amount: the entry stays the user's until Pay all.
    func suggestPayment() {
        guard !isEditing else { return }
        if let selectedPeerId {
            if !settleablePeerIds.contains(selectedPeerId) {
                self.selectedPeerId = nil
                amount.clear()
            }
            return
        }

        if let suggestion = debts.lazy.compactMap(counterpart(in:)).first {
            selectedPeerId = suggestion
        }
    }

    func submit() async -> SettleUpResult? {
        guard canSubmit, let peer = selectedPeer, let parties = parties(with: peer) else { return nil }
        // Read before the write: the session's summary is stale once it reports the payment.
        let net = netCents
        let settlesUp = net != 0 && net + netChange == 0

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            var sent: SettleUpSend?
            if let settlementId {
                try await dataSource.update(groupId, settlementId, amountCents, date)
            } else if let send = dataSource.send {
                sent = try await send(groupId, parties.payerId, parties.payeeId, amountCents, date)
            } else {
                try await dataSource.create(groupId, parties.payerId, parties.payeeId, amountCents, date)
            }
            var result = SettleUpResult(payerId: parties.payerId, payeeId: parties.payeeId,
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

    private func parties(with peer: GroupMember) -> (payerId: Int, payeeId: Int)? {
        if let original { return (original.payerId, original.payeeId) }
        return switch direction {
        case .youPay: (currentUserId, peer.userId)
        case .youReceive: (peer.userId, currentUserId)
        case nil: nil
        }
    }

    func recordSubmissionFailure(_ error: Error) {
        // The server's cap is current; the debts on screen may predate another payment.
        if case .settlementExceedsCap(let cap, _) = error as? APIError, let peer = selectedPeer, cap > 0 {
            errorMessage = onlyOwesMessage(peer, cents: cap)
            return
        }
        if !isEditing,
           let peer = selectedPeer,
           let debtCents = debtCents(for: peer.userId),
           debtCents > 0,
           debtCents < amountCents
        {
            errorMessage = onlyOwesMessage(peer, cents: debtCents)
        } else {
            errorMessage = L10n.Settlement.recordFailed
        }
    }

    private func onlyOwesMessage(_ peer: GroupMember, cents: Int) -> String {
        let name = MemberDisplay(peer).name
        let amount = Money.formatted(cents: cents, currency: session.currency)
        return direction == .youReceive
            ? L10n.Settlement.onlyOwesYou(name, amount)
            : L10n.Settlement.onlyOwe(name, amount)
    }
}
