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
        
        print("🔄 Loading group data for groupId: \(groupId)")
        
        // Load group details and expenses concurrently
        async let groupDetail = GroupService.shared.getGroup(id: groupId)
        async let groupExpenses = ExpenseService.shared.getExpenses(groupId: groupId)
        
        // Both loads run to completion even if one fails; the later failure wins the
        // single errorMessage slot.
        do {
            let group = try await groupDetail
            print("✅ Group details loaded: \(group.name)")
            self.group = group
        } catch {
            print("❌ Failed to load group: \(error)")
            errorMessage = "Failed to load group: \(error.localizedDescription)"
        }
        
        do {
            let expenses = try await groupExpenses
            print("✅ Expenses loaded: \(expenses.count) expenses")
            for expense in expenses {
                print("📝 Expense: \(expense.id) - \(expense.description) - \(expense.amount)")
            }
            self.expenses = expenses
            groupedExpenses = Expense.groupExpensesByDate(expenses)
            print("📅 Grouped expenses: \(groupedExpenses.count) groups")
            for group in groupedExpenses {
                print("📅 Group: \(group.dateString) - \(group.expenses.count) expenses")
            }
        } catch {
            print("❌ Failed to load expenses: \(error)")
            errorMessage = "Failed to load expenses: \(error.localizedDescription)"
        }
        
        print("🏁 Finished loading group data")
    }
}
