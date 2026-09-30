import Foundation

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

    var rows: [BalanceRow] {
        guard case .balances(let rows) = self else { return [] }
        return rows
    }

    init(summary: GroupBalanceSummary, currentUserId: Int) {
        let rows = summary.simplifiedDebts.map { debt in
            BalanceRow(from: debt.from, to: debt.to, amountCents: debt.amountCents,
                       involvement: Self.involvement(in: debt, currentUserId: currentUserId))
        }.sorted { lhs, rhs in
            let lhsRank = Self.rank(lhs.involvement)
            let rhsRank = Self.rank(rhs.involvement)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.amountCents > rhs.amountCents
        }
        self = rows.isEmpty ? .settled : .balances(rows)
    }

    private static func involvement(in debt: SimplifiedDebt, currentUserId: Int) -> BalanceRow.Involvement {
        if debt.from.id == currentUserId { return .youPay }
        if debt.to.id == currentUserId { return .paysYou }
        return .uninvolved
    }

    private static func rank(_ involvement: BalanceRow.Involvement) -> Int {
        switch involvement {
        case .youPay: 0
        case .paysYou: 1
        case .uninvolved: 2
        }
    }
}
