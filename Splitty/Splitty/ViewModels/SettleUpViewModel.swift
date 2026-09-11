//
//  SettleUpViewModel.swift
//  Splitty
//

import Foundation

struct SettleUpResult {
    let peer: GroupMember
    let amountCents: Int
    let date: Date
    let isEditing: Bool
}

@MainActor
final class SettleUpViewModel: ObservableObject {
    @Published var amount: AmountExpression
    @Published var date: Date
    @Published private(set) var selectedPeerId: Int?
    @Published private(set) var debtsByPeerId: [Int: Int] = [:]
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    let groupId: Int
    let members: [GroupMember]
    let currentUserId: Int

    private let settlementId: Int?

    init(
        groupId: Int,
        members: [GroupMember],
        currentUserId: Int,
        preselectedRow: BalanceRow? = nil,
        settlement: Expense? = nil
    ) {
        self.groupId = groupId
        self.members = members
        self.currentUserId = currentUserId
        settlementId = settlement?.id

        if let settlement {
            amount = AmountExpression(cents: Money.cents(from: settlement.amount))
            date = settlement.effectiveDate ?? Date()
            selectedPeerId = settlement.peer?.id
        } else if let preselectedRow {
            amount = AmountExpression()
            date = Date()
            selectedPeerId = preselectedRow.peerId
            debtsByPeerId[preselectedRow.peerId] = preselectedRow.magnitudeCents
        } else {
            amount = AmountExpression()
            date = Date()
            selectedPeerId = nil
        }
    }

    var isEditing: Bool { settlementId != nil }
    var amountCents: Int { amount.resolvedCents }
    var canSubmit: Bool { selectedPeer != nil && amountCents > 0 && !isSubmitting }

    var selectedPeer: GroupMember? {
        guard let selectedPeerId else { return nil }
        return members.first { $0.userId == selectedPeerId }
    }

    var peers: [GroupMember] {
        members
            .filter { $0.userId != currentUserId }
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
        return "Pay all \(Money.formatted(cents: cents))"
    }

    func debtCents(for peerId: Int) -> Int? {
        debtsByPeerId[peerId]
    }

    func select(peerId: Int) {
        guard !isEditing, members.contains(where: { $0.userId == peerId }) else { return }
        selectedPeerId = peerId
        amount.clear()
        errorMessage = nil
    }

    func payAll() {
        guard let selectedPeerId, let cents = debtCents(for: selectedPeerId), cents > 0 else { return }
        amount.replaceEntry(cents: cents)
    }

    func setDebt(_ cents: Int?, for peerId: Int) {
        if let cents {
            debtsByPeerId[peerId] = max(cents, 0)
        } else {
            debtsByPeerId.removeValue(forKey: peerId)
        }
    }

    func loadDebts() async {
        guard !isEditing else { return }
        guard let summary = try? await GroupService.shared.getBalanceSummary(groupId: groupId) else { return }
        apply(summary)
    }

    func apply(_ summary: GroupBalanceSummary) {
        debtsByPeerId = Dictionary(
            summary.balances
                .filter { $0.userId == currentUserId }
                .map { ($0.peerId, max(-$0.amountCents, 0)) },
            uniquingKeysWith: max
        )
    }

    func submit() async -> SettleUpResult? {
        guard canSubmit, let peer = selectedPeer else { return nil }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            if let settlementId {
                try await SettlementService.shared.updateSettlement(
                    groupId: groupId,
                    expenseId: settlementId,
                    amountCents: amountCents,
                    date: date
                )
            } else {
                try await SettlementService.shared.settleUp(
                    groupId: groupId,
                    withUserId: peer.userId,
                    amountCents: amountCents,
                    date: date
                )
            }
            return SettleUpResult(peer: peer, amountCents: amountCents, date: date, isEditing: isEditing)
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
            errorMessage = "You only owe \(peer.name) \(Money.formatted(cents: debtCents))."
        } else {
            errorMessage = "Couldn't record that payment. Pull down to refresh and try again."
        }
    }
}
