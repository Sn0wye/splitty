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
    
    func loadGroupData(groupId: Int) {
        isLoading = true
        errorMessage = ""
        
        print("🔄 Loading group data for groupId: \(groupId)")
        
        // Load group details and expenses concurrently
        let dispatchGroup = DispatchGroup()
        
        // Load group details
        dispatchGroup.enter()
        GroupService.fetchGroupDetails(groupId: groupId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let group):
                    print("✅ Group details loaded: \(group.name)")
                    self?.group = group
                case .failure(let error):
                    print("❌ Failed to load group: \(error)")
                    self?.errorMessage = "Failed to load group: \(error.localizedDescription)"
                }
                dispatchGroup.leave()
            }
        }
        
        // Load expenses
        dispatchGroup.enter()
        ExpenseService.fetchGroupExpenses(groupId: groupId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let expenses):
                    print("✅ Expenses loaded: \(expenses.count) expenses")
                    for expense in expenses {
                        print("📝 Expense: \(expense.id) - \(expense.description) - \(expense.amount)")
                    }
                    self?.expenses = expenses
                    self?.groupedExpenses = Expense.groupExpensesByDate(expenses)
                    print("📅 Grouped expenses: \(self?.groupedExpenses.count ?? 0) groups")
                    for group in self?.groupedExpenses ?? [] {
                        print("📅 Group: \(group.dateString) - \(group.expenses.count) expenses")
                    }
                case .failure(let error):
                    print("❌ Failed to load expenses: \(error)")
                    self?.errorMessage = "Failed to load expenses: \(error.localizedDescription)"
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            self?.isLoading = false
            print("🏁 Finished loading group data")
        }
    }
}
