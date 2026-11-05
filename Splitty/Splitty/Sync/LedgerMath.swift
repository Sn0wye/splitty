import Foundation

/// The group ledger's math (`LedgerCore` on the server), in cents, for the estimate shown
/// while writes are queued. The server stays the authority: this only adds what this device
/// has not sent yet to the last figures the server gave.
enum LedgerMath {
    /// Each member's net move for one row: what the group owes them, negative when they owe.
    /// The payer's own split owes nothing, and split amounts count by magnitude, so a
    /// settlement's negative payee split pays down its debt — the replay's rules.
    static func nets(of row: Expense) -> [Int: Int] {
        var nets: [Int: Int] = [:]
        for split in row.splits where split.userId != row.paidBy {
            let cents = abs(Money.cents(from: split.amount))
            nets[row.paidBy, default: 0] += cents
            nets[split.userId, default: 0] -= cents
        }
        return nets
    }

    /// Every member's net, recovered from simplified debts. Greedy matching runs until no
    /// debtor or creditor is left, so the debts carry every net exactly.
    static func nets(from debts: [SimplifiedDebt]) -> [Int: Int] {
        var nets: [Int: Int] = [:]
        for debt in debts {
            nets[debt.to.id, default: 0] += debt.amountCents
            nets[debt.from.id, default: 0] -= debt.amountCents
        }
        return nets
    }

    static func adding(_ lhs: [Int: Int], _ rhs: [Int: Int]) -> [Int: Int] {
        lhs.merging(rhs, uniquingKeysWith: +)
    }

    /// Greedy matching of the largest net debtor and the largest net creditor, ties broken by
    /// the lower user id, repeated until one side runs out (ADR 0003). The same order as the
    /// server, so an estimate made from the same nets suggests the same payments.
    static func simplify(_ nets: [Int: Int]) -> [(from: Int, to: Int, cents: Int)] {
        var remaining = nets
        var payments: [(from: Int, to: Int, cents: Int)] = []
        while true {
            let debtor = remaining.filter { $0.value < 0 }
                .min { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
            let creditor = remaining.filter { $0.value > 0 }
                .min { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            guard let debtor, let creditor else { break }
            let cents = min(-debtor.value, creditor.value)
            payments.append((debtor.key, creditor.key, cents))
            remaining[debtor.key, default: 0] += cents
            remaining[creditor.key, default: 0] -= cents
        }
        return payments
    }

    /// The most `payer` may settle with `payee` (invariant 5): the smaller of the payer's
    /// net debt and the payee's net credit.
    static func cap(_ nets: [Int: Int], payer: Int, payee: Int) -> Int {
        min(max(0, -(nets[payer] ?? 0)), max(0, nets[payee] ?? 0))
    }

    /// `summary` with `deltas` applied and re-simplified. Names and pictures come from the
    /// summary itself, then from `members`; a member known to neither keeps their id only.
    static func projected(
        _ summary: GroupBalanceSummary,
        adding deltas: [Int: Int],
        members: [GroupMember]
    ) -> GroupBalanceSummary {
        guard deltas.contains(where: { $0.value != 0 }) else { return summary }
        var people: [Int: DebtMember] = [:]
        for member in members {
            people[member.userId] = DebtMember(id: member.userId, name: member.name, avatarUrl: member.avatarUrl)
        }
        for debt in summary.simplifiedDebts {
            people[debt.from.id] = debt.from
            people[debt.to.id] = debt.to
        }
        let nets = adding(Self.nets(from: summary.simplifiedDebts), deltas)
        let debts = simplify(nets).map { payment in
            SimplifiedDebt(
                from: people[payment.from] ?? DebtMember(id: payment.from, name: "", avatarUrl: ""),
                to: people[payment.to] ?? DebtMember(id: payment.to, name: "", avatarUrl: ""),
                amountCents: payment.cents
            )
        }
        return GroupBalanceSummary(simplifiedDebts: debts, balancesPending: summary.balancesPending)
    }
}
