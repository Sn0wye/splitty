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

        if let settlement {
            amount = AmountExpression(cents: Money.cents(from: settlement.amount))
            date = settlement.effectiveDate ?? Date()
            selectedPeerId = settlement.peer?.id
        } else if let preselectedRow {
            amount = AmountExpression(cents: preselectedRow.amountCents)
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
        return L10n.Settlement.payAll(Money.formatted(cents: cents))
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
        if let cents = debtCents(for: peerId), cents > 0 {
            amount.replaceEntry(cents: cents)
        } else {
            amount.clear()
        }
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
    func suggestPayment() {
        guard !isEditing else { return }
        if let selectedPeerId {
            guard payablePeerIds.contains(selectedPeerId) else {
                self.selectedPeerId = nil
                amount.clear()
                return
            }
            if let cents = debtCents(for: selectedPeerId) {
                amount.replaceEntry(cents: cents)
            }
            return
        }

        guard let suggestion = debts.first(where: { $0.from.id == currentUserId }) else {
            return
        }

        selectedPeerId = suggestion.to.id
        amount.replaceEntry(cents: suggestion.amountCents)
    }

    func submit() async -> SettleUpResult? {
        guard canSubmit, let peer = selectedPeer else { return nil }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            if let settlementId {
                try await dataSource.update(groupId, settlementId, amountCents, date)
            } else {
                try await dataSource.create(groupId, peer.userId, amountCents, date)
            }
            return SettleUpResult(peer: peer, amountCents: amountCents, date: date, settlementId: settlementId)
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
            errorMessage = L10n.Settlement.onlyOwe(peer.name, Money.formatted(cents: debtCents))
        } else {
            errorMessage = L10n.Settlement.recordFailed
        }
    }
}
