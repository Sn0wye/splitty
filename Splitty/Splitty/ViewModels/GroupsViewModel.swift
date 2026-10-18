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
