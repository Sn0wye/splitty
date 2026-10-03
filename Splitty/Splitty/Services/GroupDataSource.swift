import Foundation

/// The group reads and delete routes behind closures so a test can control their timing.
/// Each snapshot still issues its three reads concurrently.
struct GroupDataSource {
    var group: (Int) async throws -> GroupDetail
    var expenses: (Int) async throws -> [Expense]
    var summary: (Int) async throws -> GroupBalanceSummary
    var waitForBalanceRetry: (Duration) async throws -> Void
    var requestBalanceRefresh: (Int) async throws -> Void
    var deleteExpense: (Int, Int) async throws -> Void
    var deletePayment: (Int, Int) async throws -> Void

    init(
        group: @escaping (Int) async throws -> GroupDetail,
        expenses: @escaping (Int) async throws -> [Expense],
        summary: @escaping (Int) async throws -> GroupBalanceSummary,
        waitForBalanceRetry: @escaping (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        requestBalanceRefresh: @escaping (Int) async throws -> Void = { groupId in
            try await GroupService.shared.requestBalanceRecomputation(groupId: groupId)
        },
        deleteExpense: @escaping (Int, Int) async throws -> Void = { groupId, expenseId in
            try await ExpenseService.shared.deleteExpense(groupId: groupId, expenseId: expenseId)
        },
        deletePayment: @escaping (Int, Int) async throws -> Void = { groupId, expenseId in
            try await SettlementService.shared.deleteSettlement(groupId: groupId, expenseId: expenseId)
        }
    ) {
        self.requestBalanceRefresh = requestBalanceRefresh
        self.group = group
        self.expenses = expenses
        self.summary = summary
        self.waitForBalanceRetry = waitForBalanceRetry
        self.deleteExpense = deleteExpense
        self.deletePayment = deletePayment
    }

    static let live = GroupDataSource(
        group: { try await GroupService.shared.getGroup(id: $0) },
        expenses: { try await ExpenseService.shared.getExpenses(groupId: $0) },
        summary: { try await GroupService.shared.getBalanceSummary(groupId: $0) }
    )
}
