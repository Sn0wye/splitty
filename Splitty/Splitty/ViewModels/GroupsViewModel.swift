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
    
    func loadGroups() async {
        if PerformanceScenarioLaunch.isEnabled {
            groups = PerformanceScenarios.groups
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            groups = try await GroupService.shared.getGroups()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
