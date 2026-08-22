//
//  GroupViewModel.swift
//  Splitty
//
//  Created by Snowye on 19/11/25.
//

import Foundation

@MainActor
class GroupViewModel: ObservableObject {
    @Published var group: GroupDetail?
    @Published var expenses: [Expense] = []
    @Published var groupedExpenses: [GroupedExpense] = []
    @Published var isLoading = false
    @Published var errorMessage = ""

    /// True while the balance worker still owes this group a recomputation, so the header
    /// number is known to predate the last write.
    @Published var balancesPending = false

    var members: [GroupMember] { group?.members ?? [] }

    func loadGroupData(groupId: Int) async {
        isLoading = true
        defer { isLoading = false }
        await load(groupId: groupId)
    }

    /// Reloads after a write without blanking the screen. Called **once**, on the sheet's
    /// dismissal: `balancesPending` exists so a client can show a spinner instead of
    /// polling, and the worker usually finishes inside the dismiss animation.
    func refresh(groupId: Int) async {
        await load(groupId: groupId)
    }

    private func load(groupId: Int) async {
        errorMessage = ""

        async let groupResult = GroupService.shared.getGroup(id: groupId)
        async let expensesResult = ExpenseService.shared.getExpenses(groupId: groupId)
        async let summaryResult = GroupService.shared.getBalanceSummary(groupId: groupId)

        // Every load runs to completion even if one fails; the later failure wins the
        // single errorMessage slot.
        do {
            group = try await groupResult
        } catch {
            errorMessage = "Failed to load group: \(error.localizedDescription)"
        }

        do {
            let loadedExpenses = try await expensesResult
            expenses = loadedExpenses
            groupedExpenses = Expense.groupExpensesByDate(loadedExpenses)
        } catch {
            errorMessage = "Failed to load expenses: \(error.localizedDescription)"
        }

        // A summary that fails to load is not worth an error line: the flag it carries only
        // decides whether the header renders as provisional.
        balancesPending = (try? await summaryResult)?.balancesPending ?? false
    }

    /// Deletes an expense or a settlement, whichever the row is. They do not share a route:
    /// the expense route refuses payment rows rather than branching on a type the client
    /// never sent.
    func delete(_ expense: Expense, groupId: Int) async {
        do {
            switch expense.type {
            case .expense:
                try await ExpenseService.shared.deleteExpense(groupId: groupId, expenseId: expense.id)
            case .payment:
                try await SettlementService.shared.deleteSettlement(groupId: groupId, expenseId: expense.id)
            }
            await refresh(groupId: groupId)
        } catch {
            errorMessage = ExpenseFormViewModel.message(for: error)
        }
    }
}
