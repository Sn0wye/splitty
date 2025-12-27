//
//  ExpenseService.swift
//  Splitty
//
//  Created by Snowye on 19/11/25.
//

import Foundation

class ExpenseService {
    static let shared = ExpenseService()
    
    private init() {}
    
    // MARK: - Modern async/await methods
    func getExpenses(groupId: Int) async throws -> [Expense] {
        return try await APIClient.shared.getExpenses(groupId: groupId)
    }
    
    func getExpense(groupId: Int, expenseId: Int) async throws -> Expense {
        return try await APIClient.shared.getExpense(groupId: groupId, expenseId: expenseId)
    }
    
    func createExpense(
        groupId: Int,
        description: String,
        amount: Double,
        paidBy: Int,
        splits: [ExpenseSplitRequest]
    ) async throws -> Expense {
        return try await APIClient.shared.createExpense(
            groupId: groupId,
            description: description,
            amount: amount,
            paidBy: paidBy,
            splits: splits
        )
    }
    
    func updateExpense(
        groupId: Int,
        expenseId: Int,
        description: String? = nil,
        amount: Double? = nil,
        splits: [ExpenseSplitRequest]? = nil
    ) async throws -> Expense {
        return try await APIClient.shared.updateExpense(
            groupId: groupId,
            expenseId: expenseId,
            description: description,
            amount: amount,
            splits: splits
        )
    }
    
    func deleteExpense(groupId: Int, expenseId: Int) async throws {
        return try await APIClient.shared.deleteExpense(groupId: groupId, expenseId: expenseId)
    }
    
    // MARK: - Legacy callback methods for existing code
    static func fetchGroupExpenses(groupId: Int, completion: @escaping (Result<[Expense], Error>) -> Void) {
        Task {
            do {
                let expenses = try await shared.getExpenses(groupId: groupId)
                completion(.success(expenses))
            } catch {
                completion(.failure(error))
            }
        }
    }
}