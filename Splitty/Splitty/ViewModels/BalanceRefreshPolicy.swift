//
//  BalanceRefreshPolicy.swift
//  Splitty
//

import Foundation

enum BalanceRefreshPolicy {
    /// Fast retries cover the normal worker path. The final low-frequency delay repeats
    /// while the view remains active, so a slow worker can still update the screen.
    static let retryDelays: [Duration] = [
        .milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2),
        .seconds(4), .seconds(10), .seconds(30)
    ]

    /// Repeats the last delay until the worker's display hint clears. `receive` publishes
    /// each snapshot and can stop an obsolete load before it writes any more state.
    @MainActor
    static func waitUntilPendingClears(
        groupId: Int,
        balancesPending: Bool,
        fetch: (Int) async throws -> GroupBalanceSummary,
        wait: (Duration) async throws -> Void,
        receive: (GroupBalanceSummary) -> Bool
    ) async -> Bool {
        var balancesPending = balancesPending
        var retryIndex = 0

        while balancesPending {
            let delay = retryDelays[min(retryIndex, retryDelays.count - 1)]
            retryIndex += 1

            do {
                try await wait(delay)
                let summary = try await fetch(groupId)
                guard receive(summary) else { return false }
                balancesPending = summary.balancesPending
            } catch {
                if error.isCancellation { return false }
            }
        }

        return true
    }
}
