//
//  BalancesViewModel.swift
//  Splitty
//

import Foundation

struct BalanceDataSource {
    var requestRefresh: (Int) async throws -> Void

    init(
        requestRefresh: @escaping (Int) async throws -> Void
    ) {
        self.requestRefresh = requestRefresh
    }

    static let live = BalanceDataSource(
        requestRefresh: { try await GroupService.shared.requestBalanceRecomputation(groupId: $0) }
    )
}

struct BalanceRow: Identifiable, Equatable {
    enum Involvement: Equatable {
        case youPay
        case paysYou
        case uninvolved
    }

    let from: DebtMember
    let to: DebtMember
    let amountCents: Int
    let involvement: Involvement

    var id: String { "\(from.id)-\(to.id)" }

    var statement: String {
        let amount = Money.formatted(cents: amountCents)
        return switch involvement {
        case .youPay:
            L10n.Balances.youOwePeer(to.name, amount)
        case .paysYou:
            L10n.Balances.peerOwesYou(from.name, amount)
        case .uninvolved:
            L10n.Balances.peerOwesPeer(from.name, to.name, amount)
        }
    }
}

enum BalancesDisplayState: Equatable {
    case loading
    case balances([BalanceRow])
    case settled
    case error(String)
}

@MainActor
final class BalancesViewModel: ObservableObject {
    let groupId: Int

    @Published private(set) var state: BalancesDisplayState = .loading
    private let dataSource: BalanceDataSource

    init(groupId: Int, dataSource: BalanceDataSource = .live) {
        self.groupId = groupId
        self.dataSource = dataSource
    }

    var rows: [BalanceRow] {
        guard case .balances(let rows) = state else { return [] }
        return rows
    }

    func refresh(session: GroupSession) async {
        do {
            try await dataSource.requestRefresh(groupId)
            await session.snapshot.refresh(groupId: groupId)
        } catch {
            fail(with: error)
        }
    }

    /// Display seam: transforms a decoded API snapshot into exactly what the sheet states.
    func apply(_ summary: GroupBalanceSummary, currentUserId: Int) {
        let openRows = summary.simplifiedDebts
            .map { debt in
                BalanceRow(
                    from: debt.from,
                    to: debt.to,
                    amountCents: debt.amountCents,
                    involvement: involvement(in: debt, currentUserId: currentUserId)
                )
            }
            .sorted { lhs, rhs in
                let lhsRank = rank(lhs.involvement)
                let rhsRank = rank(rhs.involvement)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.amountCents > rhs.amountCents
            }

        state = openRows.isEmpty ? .settled : .balances(openRows)
    }

    private func involvement(in debt: SimplifiedDebt, currentUserId: Int) -> BalanceRow.Involvement {
        if debt.from.id == currentUserId { return .youPay }
        if debt.to.id == currentUserId { return .paysYou }
        return .uninvolved
    }

    private func rank(_ involvement: BalanceRow.Involvement) -> Int {
        switch involvement {
        case .youPay: 0
        case .paysYou: 1
        case .uninvolved: 2
        }
    }

    func fail(with error: Error) {
        state = .error(error.displayMessage)
    }
}
