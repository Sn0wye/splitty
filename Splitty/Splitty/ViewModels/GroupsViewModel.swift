//
//  GroupsViewModel.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct CurrencyBalance: Equatable {
    let currency: Currency
    /// Positive when owed.
    let cents: Int
}

/// What the groups header shows when at least one currency is not settled: one line for
/// the primary currency and the rest folded behind a count.
struct OverallSummary: Equatable {
    let primary: CurrencyBalance
    let others: [CurrencyBalance]
}

@MainActor
class GroupsViewModel: ObservableObject {
    @Published var groups: [Group] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    /// When the list on screen was read, while it is this device's copy because the latest
    /// read failed. Nil once a read succeeds.
    @Published private(set) var savedAt: Date?
    /// When the list on screen was saved, shown only once a read fails.
    private var shownCopySavedAt: Date?
    private var prefetchTask: Task<Void, Never>?

    /// One net per currency, in the order the list first shows each. Amounts in different
    /// currencies are never added together (ADR 0007), and a currency that nets to zero is
    /// left out, so an empty list means everything is settled. Nil distinguishes an empty
    /// groups list from a real, all-settled total.
    var overallBalances: [CurrencyBalance]? {
        guard !groups.isEmpty else { return nil }
        var order: [Currency] = []
        var nets: [Currency: Int] = [:]
        for group in groups {
            if nets[group.currency] == nil { order.append(group.currency) }
            nets[group.currency, default: 0] += group.netBalanceCents
        }
        return order.compactMap { currency in
            let cents = nets[currency] ?? 0
            return cents == 0 ? nil : CurrencyBalance(currency: currency, cents: cents)
        }
    }

    /// The primary currency is the one most of the groups are in, counting every group,
    /// settled or not: it is the currency the person lives in, so its net is the figure they
    /// came for. A tie goes to the currency that appears first in the list, which is the
    /// order `overallBalances` already has. Nil when there are no groups or every currency
    /// nets to zero; callers read `overallBalances` to tell those two apart.
    var overallSummary: OverallSummary? {
        guard let balances = overallBalances, !balances.isEmpty else { return nil }
        var groupCounts: [Currency: Int] = [:]
        for group in groups { groupCounts[group.currency, default: 0] += 1 }
        let primaryIndex = balances.indices.max { lhs, rhs in
            let lhsCount = groupCounts[balances[lhs].currency] ?? 0
            let rhsCount = groupCounts[balances[rhs].currency] ?? 0
            // `max` keeps the earlier element on a tie only when the later is not greater,
            // so compare the index the other way round to prefer the earlier one.
            return lhsCount != rhsCount ? lhsCount < rhsCount : lhs > rhs
        } ?? 0
        var others = balances
        let primary = others.remove(at: primaryIndex)
        return OverallSummary(primary: primary, others: others)
    }

    func removeGroup(id: Int) {
        groups.removeAll { $0.id == id }
    }
    
    /// Most recently active first (`Group.recentFirst`). `recentlyOpened` is the session
    /// store's groups opened this launch, newest first.
    ///
    /// With a `cache`, the saved list shows at once and stays when the read fails, and every
    /// group's rows are saved so it opens offline (ADR 0008).
    func loadGroups(recentlyOpened: [Int] = [], cache: GroupCache? = nil) async {
        if PerformanceScenarioLaunch.isEnabled {
            groups = Group.recentFirst(PerformanceScenarios.groups, recentlyOpened: recentlyOpened)
            return
        }
        if groups.isEmpty, let saved = cache?.groups {
            groups = Group.recentFirst(saved.groups, recentlyOpened: recentlyOpened)
            shownCopySavedAt = saved.savedAt
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await GroupService.shared.getGroups()
            groups = Group.recentFirst(loaded, recentlyOpened: recentlyOpened)
            savedAt = nil
            shownCopySavedAt = nil
            if let cache {
                cache.save(groups: loaded)
                prefetch(loaded, into: cache)
            }
        } catch {
            if error.isCancellation { return }
            // The saved list is still the best answer there is; the banner says how old it is.
            if let shownCopySavedAt { savedAt = shownCopySavedAt }
            if savedAt == nil || groups.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    /// Saves the rows of every group this device has no recent copy of, one group at a time,
    /// so a group never opened this launch still opens offline. Reads the expense list and
    /// the summary only: `GET group` catches recurring expenses up (ADR 0006), which opening
    /// the group already does, and the list row carries the group itself.
    private func prefetch(_ groups: [Group], into cache: GroupCache) {
        prefetchTask?.cancel()
        prefetchTask = Task {
            for group in groups {
                if Task.isCancelled { return }
                if let saved = cache.snapshot(groupId: group.id), saved.savedAt > Date().addingTimeInterval(-3600) {
                    continue
                }
                guard let expenses = try? await ExpenseService.shared.getExpenses(groupId: group.id) else { return }
                let summary = try? await GroupService.shared.getBalanceSummary(groupId: group.id)
                if Task.isCancelled { return }
                // A session that read the group in the meantime saved something newer.
                if let saved = cache.snapshot(groupId: group.id), saved.savedAt > Date().addingTimeInterval(-60) {
                    continue
                }
                cache.save(GroupSnapshot(group: group, expenses: expenses, summary: summary, savedAt: Date()), groupId: group.id)
            }
        }
    }
}
