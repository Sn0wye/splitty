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

struct BalanceDataSource {
    var summary: (Int) async throws -> GroupBalanceSummary
    var requestRefresh: (Int) async throws -> Void
    var waitForRetry: (Duration) async throws -> Void

    init(
        summary: @escaping (Int) async throws -> GroupBalanceSummary,
        requestRefresh: @escaping (Int) async throws -> Void,
        waitForRetry: @escaping (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.summary = summary
        self.requestRefresh = requestRefresh
        self.waitForRetry = waitForRetry
    }

    static let live = BalanceDataSource(
        summary: { try await GroupService.shared.getBalanceSummary(groupId: $0) },
        requestRefresh: { try await GroupService.shared.requestBalanceRecomputation(groupId: $0) }
    )
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
            L10n.Balances.youOwePeer(peerName, Money.formatted(cents: magnitudeCents))
        case .owedToYou:
            L10n.Balances.peerOwesYou(peerName, Money.formatted(cents: magnitudeCents))
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
    private let dataSource: BalanceDataSource

    init(context: BalanceSheetContext, dataSource: BalanceDataSource = .live) {
        groupId = context.groupId
        netCents = context.initialNetCents
        balancesPending = context.balancesPending
        self.dataSource = dataSource
    }

    var rows: [BalanceRow] {
        guard case .balances(let rows) = state else { return [] }
        return rows
    }

    func load(currentUserId: Int) async {
        do {
            let summary = try await dataSource.summary(groupId)
            apply(summary, currentUserId: currentUserId)
            await refreshPendingBalance(startingWith: summary, currentUserId: currentUserId)
        } catch {
            fail(with: error)
        }
    }

    /// Requests a replay, then refreshes until the worker returns a settled snapshot or the
    /// view cancels the task.
    func refresh(currentUserId: Int) async {
        do {
            try await dataSource.requestRefresh(groupId)
            let summary = try await dataSource.summary(groupId)
            apply(summary, currentUserId: currentUserId)
            await refreshPendingBalance(startingWith: summary, currentUserId: currentUserId)
        } catch {
            fail(with: error)
        }
    }

    private func refreshPendingBalance(
        startingWith initialSummary: GroupBalanceSummary,
        currentUserId: Int
    ) async {
        guard initialSummary.balancesPending else { return }

        _ = await BalanceRefreshPolicy.waitUntilPendingClears(
            groupId: groupId,
            balancesPending: initialSummary.balancesPending,
            fetch: dataSource.summary,
            wait: dataSource.waitForRetry
        ) { [weak self] summary in
            self?.apply(summary, currentUserId: currentUserId)
            return self != nil
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
