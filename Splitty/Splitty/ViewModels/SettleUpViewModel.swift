//
//  SettleUpViewModel.swift
//  Splitty
//

import Foundation

struct SettleUpResult {
    let peer: GroupMember
    let amountCents: Int
    let date: Date
    let settlementId: Int?
    /// True when this payment brings the payer's net balance in the group to zero.
    var settlesUp = false
}

struct SettleUpDataSource {
    var create: (Int, Int, Int, Date) async throws -> Void
    var update: (Int, Int, Int, Date) async throws -> Void

    static let live = SettleUpDataSource(
        create: { groupId, peerId, amountCents, date in
            try await SettlementService.shared.settleUp(
                groupId: groupId,
                withUserId: peerId,
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
    /// The edited payment as it stands: its amount, and whether the current user paid it.
    private let original: (cents: Int, youPaid: Bool)?
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
        original = settlement.map { (Money.cents(from: $0.amount), $0.paidBy == currentUserId) }
        self.dataSource = dataSource

        if let settlement {
            amount = AmountExpression(cents: Money.cents(from: settlement.amount))
            date = settlement.effectiveDate ?? Date()
            selectedPeerId = settlement.peer?.id
        } else if let preselectedRow {
            amount = AmountExpression()
            date = Date()
            selectedPeerId = preselectedRow.to.id
        } else {
            amount = AmountExpression()
            date = Date()
            selectedPeerId = nil
        }
    }

    var balancesPending: Bool { session.balancesPending }
    private var debts: [SimplifiedDebt] { session.latestSummary?.simplifiedDebts ?? [] }
    private var payablePeerIds: Set<Int> {
        Set(debts.map(\.to.id).filter { $0 != currentUserId })
    }

    var isEditing: Bool { settlementId != nil }
    var amountCents: Int { amount.resolvedCents }
    var canSubmit: Bool {
        selectedPeer != nil && amountCents > 0 && !isSubmitting && !balancesPending
    }

    var selectedPeer: GroupMember? {
        guard let selectedPeerId else { return nil }
        return members.first { $0.userId == selectedPeerId && (isEditing || payablePeerIds.contains($0.userId)) }
    }

    var peers: [GroupMember] {
        members
            .filter { $0.userId != currentUserId && (isEditing || payablePeerIds.contains($0.userId)) }
            .sorted { lhs, rhs in
                let lhsDebt = debtCents(for: lhs.userId) ?? 0
                let rhsDebt = debtCents(for: rhs.userId) ?? 0
                if (lhsDebt > 0) != (rhsDebt > 0) { return lhsDebt > 0 }
                if lhsDebt != rhsDebt { return lhsDebt > rhsDebt }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var payAllTitle: String? {
        guard let selectedPeerId,
              let cents = debtCents(for: selectedPeerId),
              cents > 0
        else { return nil }
        return L10n.Settlement.payAll(Money.formatted(cents: cents, currency: session.currency))
    }

    /// The current user's net balance across the simplified debts: positive when owed.
    private var netCents: Int {
        debts.reduce(0) { net, debt in
            if debt.to.id == currentUserId { return net + debt.amountCents }
            if debt.from.id == currentUserId { return net - debt.amountCents }
            return net
        }
    }

    /// How this submission moves the current user's net balance. An edit only moves it by
    /// the difference, in the payer's favour.
    private var netChange: Int {
        guard let original else { return amountCents }
        let delta = amountCents - original.cents
        return original.youPaid ? delta : -delta
    }

    func debtCents(for peerId: Int) -> Int? {
        debts.filter { $0.from.id == currentUserId && $0.to.id == peerId }.map(\.amountCents).max()
    }

    func select(peerId: Int) {
        guard !isEditing,
              payablePeerIds.contains(peerId),
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
            if !payablePeerIds.contains(selectedPeerId) {
                self.selectedPeerId = nil
                amount.clear()
            }
            return
        }

        if let suggestion = debts.first(where: { $0.from.id == currentUserId }) {
            selectedPeerId = suggestion.to.id
        }
    }

    func submit() async -> SettleUpResult? {
        guard canSubmit, let peer = selectedPeer else { return nil }
        // Read before the write: the session's summary is stale once it reports the payment.
        let net = netCents
        let settlesUp = net != 0 && net + netChange == 0

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            if let settlementId {
                try await dataSource.update(groupId, settlementId, amountCents, date)
            } else {
                try await dataSource.create(groupId, peer.userId, amountCents, date)
            }
            return SettleUpResult(peer: peer, amountCents: amountCents, date: date,
                                  settlementId: settlementId, settlesUp: settlesUp)
        } catch {
            recordSubmissionFailure(error)
            return nil
        }
    }

    func recordSubmissionFailure(_ error: Error) {
        if !isEditing,
           let peer = selectedPeer,
           let debtCents = debtCents(for: peer.userId),
           debtCents > 0,
           debtCents < amountCents
        {
            errorMessage = L10n.Settlement.onlyOwe(peer.name, Money.formatted(cents: debtCents, currency: session.currency))
        } else {
            errorMessage = L10n.Settlement.recordFailed
        }
    }
}
