//
//  BalancesViewModel.swift
//  Splitty
//

import Foundation

struct BalanceSheetContext {
    let groupId: Int
    let initialNetCents: Int
    let balancesPending: Bool
}

struct BalanceRow: Identifiable, Equatable {
    enum Direction: Equatable {
        case youOwe
        case owedToYou
    }

    let peerId: Int
    let peerName: String
    let peerAvatarURL: URL?
    let amountCents: Int
    let direction: Direction

    var id: Int { peerId }
    var magnitudeCents: Int { abs(amountCents) }

    var statement: String {
        switch direction {
        case .youOwe:
            "You owe \(peerName) \(Money.formatted(cents: magnitudeCents))"
        case .owedToYou:
            "\(peerName) owes you \(Money.formatted(cents: magnitudeCents))"
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
    @Published private(set) var netCents: Int
    @Published private(set) var balancesPending: Bool

    init(context: BalanceSheetContext) {
        groupId = context.groupId
        netCents = context.initialNetCents
        balancesPending = context.balancesPending
    }

    var rows: [BalanceRow] {
        guard case .balances(let rows) = state else { return [] }
        return rows
    }

    var largestMagnitudeCents: Int {
        rows.map(\.magnitudeCents).max() ?? 1
    }

    func load(currentUserId: Int) async {
        do {
            apply(try await GroupService.shared.getBalanceSummary(groupId: groupId), currentUserId: currentUserId)
        } catch {
            fail(with: error)
        }
    }

    /// Requests a replay, then takes one fresh snapshot. The pending flag explains that the
    /// snapshot may still predate the worker; it is not treated as a lock and is not polled.
    func refresh(currentUserId: Int) async {
        do {
            try await GroupService.shared.requestBalanceRecomputation(groupId: groupId)
            apply(try await GroupService.shared.getBalanceSummary(groupId: groupId), currentUserId: currentUserId)
        } catch {
            fail(with: error)
        }
    }

    /// Display seam: transforms a decoded API snapshot into exactly what the sheet states.
    func apply(_ summary: GroupBalanceSummary, currentUserId: Int) {
        let balances = summary.balances.filter { $0.userId == currentUserId }
        netCents = balances.reduce(0) { $0 + $1.amountCents }
        balancesPending = summary.balancesPending

        let openRows = balances
            .filter { $0.amountCents != 0 }
            .map { balance in
                BalanceRow(
                    peerId: balance.peerId,
                    peerName: balance.peer.name,
                    peerAvatarURL: balance.peer.avatarURL,
                    amountCents: balance.amountCents,
                    direction: balance.amountCents < 0 ? .youOwe : .owedToYou
                )
            }
            .sorted { lhs, rhs in
                if lhs.direction != rhs.direction {
                    return lhs.direction == .youOwe
                }
                return lhs.magnitudeCents > rhs.magnitudeCents
            }

        state = openRows.isEmpty ? .settled : .balances(openRows)
    }

    func fail(with error: Error) {
        state = .error(error.displayMessage)
    }
}
