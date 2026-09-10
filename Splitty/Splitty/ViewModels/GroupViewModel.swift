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

    /// A failed delete belongs next to the list, not in place of it: `errorMessage` blanks
    /// the timeline, which is the right shape for a load that failed and the wrong one for
    /// an action that did.
    @Published var actionErrorMessage: String?

    /// True while the balance worker still owes this group a recomputation, so the header
    /// number is known to predate the last write.
    @Published var balancesPending = false

    /// Negative ids exist only until a successful expense refetch replaces fabricated
    /// payment rows with the server's rows.
    @Published private(set) var pendingPaymentIds: Set<Int> = []
    private var nextPendingPaymentId = -1
    private var pendingNetAdjustmentCents = 0

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

    /// Shows a just-saved expense without waiting for the refetch. The row is real — the
    /// server returned it — while the *balance* it feeds is not, which is what
    /// `balancesPending` says.
    func insert(_ expense: Expense) {
        expenses.removeAll { $0.id == expense.id }
        expenses.append(expense)
        groupedExpenses = Expense.groupExpensesByDate(expenses)
    }

    private func load(groupId: Int) async {
        errorMessage = ""

        async let groupResult = GroupService.shared.getGroup(id: groupId)
        async let expensesResult = ExpenseService.shared.getExpenses(groupId: groupId)
        async let summaryResult = GroupService.shared.getBalanceSummary(groupId: groupId)

        // Every load runs to completion even if one fails; the later failure wins the
        // single errorMessage slot.
        let loadedGroup: GroupDetail?
        do {
            loadedGroup = try await groupResult
        } catch {
            loadedGroup = nil
            errorMessage = "Failed to load group: \(error.localizedDescription)"
        }

        do {
            let loadedExpenses = try await expensesResult
            expenses = loadedExpenses
            groupedExpenses = Expense.groupExpensesByDate(loadedExpenses)
            pendingPaymentIds.removeAll()
        } catch {
            errorMessage = "Failed to load expenses: \(error.localizedDescription)"
        }

        // Preserve locally-known payment arithmetic while the worker still reports the
        // fetched net as stale. Once pending clears, the server owns the number again.
        let summary = try? await summaryResult
        balancesPending = summary?.balancesPending ?? (pendingNetAdjustmentCents != 0)
        if var loadedGroup {
            if balancesPending {
                loadedGroup.netBalanceCents += pendingNetAdjustmentCents
            } else {
                pendingNetAdjustmentCents = 0
            }
            group = loadedGroup
        }
    }

    /// The settle route returns no row, so make the one piece of UI it cannot return. Its
    /// negative id keeps navigation and deletion away from a resource that does not exist.
    @discardableResult
    func insertPendingPayment(
        groupId: Int,
        currentUser: GroupMember,
        peer: GroupMember,
        amountCents: Int,
        now: Date = Date()
    ) -> Expense {
        let id = nextPendingPaymentId
        nextPendingPaymentId -= 1
        let timestamp = ExpenseService.timestamp(from: now)
        let payer = Self.user(from: currentUser, timestamp: timestamp)
        let payee = Self.user(from: peer, timestamp: timestamp)
        let amount = Money.amount(cents: amountCents)

        let payment = Expense(
            id: id,
            groupId: groupId,
            paidBy: currentUser.userId,
            amount: amount,
            description: "Payment to \(peer.name)",
            type: .payment,
            splitMode: nil,
            date: nil,
            createdAt: timestamp,
            updatedAt: timestamp,
            paidByUser: payer,
            splits: [
                ExpenseSplit(id: id * 10, expenseId: id, userId: currentUser.userId, amount: amount, percentage: nil, user: payer),
                ExpenseSplit(id: id * 10 - 1, expenseId: id, userId: peer.userId, amount: -amount, percentage: nil, user: payee)
            ]
        )

        pendingPaymentIds.insert(id)
        insert(payment)
        pendingNetAdjustmentCents += amountCents
        group?.netBalanceCents += amountCents
        balancesPending = true
        return payment
    }

    func isPendingPayment(_ expense: Expense) -> Bool {
        pendingPaymentIds.contains(expense.id)
    }

    private static func user(from member: GroupMember, timestamp: String) -> User {
        User(
            id: member.userId,
            name: member.name,
            email: member.email,
            avatarURL: member.avatarUrl.isEmpty ? nil : URL(string: member.avatarUrl),
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    /// Deletes an expense or a settlement, whichever the row is. They do not share a route:
    /// the expense route refuses payment rows rather than branching on a type the client
    /// never sent.
    func delete(_ expense: Expense, groupId: Int) async {
        actionErrorMessage = nil

        do {
            switch expense.type {
            case .expense:
                try await ExpenseService.shared.deleteExpense(groupId: groupId, expenseId: expense.id)
            case .payment:
                try await SettlementService.shared.deleteSettlement(groupId: groupId, expenseId: expense.id)
            }
            await refresh(groupId: groupId)
        } catch {
            actionErrorMessage = error.displayMessage
        }
    }
}
