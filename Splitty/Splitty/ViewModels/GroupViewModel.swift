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
    
    // This should be set from the current user's ID from AuthService
    private let currentUserId = 1 // TODO: Get from AuthService
    
    func loadGroupData(groupId: Int) async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        
        async let groupResult = GroupService.shared.getGroup(id: groupId)
        async let expensesResult = ExpenseService.shared.getExpenses(groupId: groupId)
        
        // Both loads run to completion even if one fails; the later failure wins the
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
    }
}
