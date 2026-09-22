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
        netCents = summary.simplifiedDebts.reduce(0) { total, debt in
            if debt.from.id == currentUserId { return total - debt.amountCents }
            if debt.to.id == currentUserId { return total + debt.amountCents }
            return total
        }
        balancesPending = summary.balancesPending

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
