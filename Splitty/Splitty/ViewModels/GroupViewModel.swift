//
//  GroupViewModel.swift
//  Splitty
//
//  Created by Snowye on 19/11/25.
//

import Foundation

/// The group reads and delete routes behind closures so a test can control their timing.
/// Each snapshot still issues its three reads concurrently.
struct GroupDataSource {
    var group: (Int) async throws -> GroupDetail
    var expenses: (Int) async throws -> [Expense]
    var summary: (Int) async throws -> GroupBalanceSummary
    var waitForBalanceRetry: (Duration) async throws -> Void
    var deleteExpense: (Int, Int) async throws -> Void
    var deletePayment: (Int, Int) async throws -> Void

    init(
        group: @escaping (Int) async throws -> GroupDetail,
        expenses: @escaping (Int) async throws -> [Expense],
        summary: @escaping (Int) async throws -> GroupBalanceSummary,
        waitForBalanceRetry: @escaping (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        deleteExpense: @escaping (Int, Int) async throws -> Void = { groupId, expenseId in
            try await ExpenseService.shared.deleteExpense(groupId: groupId, expenseId: expenseId)
        },
        deletePayment: @escaping (Int, Int) async throws -> Void = { groupId, expenseId in
            try await SettlementService.shared.deleteSettlement(groupId: groupId, expenseId: expenseId)
        }
    ) {
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

    /// Negative ids exist until an expense refetch supplies the matching server rows.
    @Published private(set) var pendingPaymentIds: Set<Int> = []
    private var knownServerIdsAtPaymentWrite: [Int: Set<Int>] = [:]
    private var nextPendingPaymentId = -1
    private var pendingNetAdjustmentCents = 0
    private var needsPostWriteSettlement = false

    private let dataSource: GroupDataSource

    /// The refresh this view model owns, so a new one can cancel the one it replaces
    /// instead of racing it.
    private var refreshTask: Task<Void, Never>?

    /// Counts started loads. A load that is no longer the newest publishes nothing:
    /// cancellation is cooperative and a request already past its last suspension point
    /// would otherwise overwrite a fresher snapshot.
    private var loadGeneration = 0

    init(dataSource: GroupDataSource = .live) {
        self.dataSource = dataSource
    }

    var members: [GroupMember] { group?.members ?? [] }

    func loadGroupData(groupId: Int) async {
        isLoading = true
        let generation = await load(groupId: groupId)
        isLoading = false

        if let generation {
            await refreshPendingBalance(groupId: groupId, generation: generation)
            await refreshPendingPayments(groupId: groupId, generation: generation)
        }
    }

    /// Reloads after a write without blanking the screen. A pending balance keeps its
    /// spinner while bounded polling waits for the worker's settled snapshot.
    ///
    /// Structured: a caller that can wait — pull-to-refresh, a delete — keeps the load in
    /// its own task tree, so SwiftUI cancelling that task cancels the requests underneath
    /// it. Any owned refresh it supersedes is cancelled first.
    func refresh(groupId: Int) async {
        refreshTask?.cancel()
        await reloadThroughBalanceSettlement(groupId: groupId)
    }

    /// A completed write is the screen's only money-entry event. Invalidate an older
    /// load before showing the saved row, then own the refetch and balance settlement.
    @discardableResult
    func completedExpenseWrite(_ expense: Expense, groupId: Int) -> Task<Void, Never> {
        cancelRefresh()
        needsPostWriteSettlement = true
        insert(expense)
        return beginRefresh(groupId: groupId)
    }

    @discardableResult
    func completedPaymentWrite(_ result: SettleUpResult, currentUserId: Int, groupId: Int) -> Task<Void, Never> {
        cancelRefresh()
        needsPostWriteSettlement = true
        if !result.isEditing,
           let currentUser = members.first(where: { $0.userId == currentUserId }) {
            insertPendingPayment(
                groupId: groupId,
                currentUser: currentUser,
                peer: result.peer,
                amountCents: result.amountCents,
                date: result.date
            )
        }
        return beginRefresh(groupId: groupId)
    }

    @discardableResult
    func completedMoneyWrite(groupId: Int) -> Task<Void, Never> {
        cancelRefresh()
        needsPostWriteSettlement = true
        return beginRefresh(groupId: groupId)
    }

    /// Starts a refresh the view model owns for callers with nothing to await, such as
    /// group settings, instead of spawning a task nobody can cancel.
    @discardableResult
    func beginRefresh(groupId: Int) -> Task<Void, Never> {
        refreshTask?.cancel()
        let task = Task { [weak self] () -> Void in
            await self?.reloadThroughBalanceSettlement(groupId: groupId)
        }
        refreshTask = task
        return task
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        loadGeneration += 1
    }

    /// Shows a just-saved expense without waiting for the refetch. The row is real — the
    /// server returned it — while the *balance* it feeds is not, which is what
    /// `balancesPending` says.
    func insert(_ expense: Expense) {
        expenses.removeAll { $0.id == expense.id }
        expenses.append(expense)
        groupedExpenses = Expense.groupExpensesByDate(expenses)
    }

    private func reloadThroughBalanceSettlement(groupId: Int) async {
        guard let generation = await load(groupId: groupId) else { return }
        await refreshPendingBalance(groupId: groupId, generation: generation)
        await refreshPendingPayments(groupId: groupId, generation: generation)
    }

    private func load(groupId: Int) async -> Int? {
        loadGeneration += 1
        let generation = loadGeneration

        if PerformanceScenarioLaunch.isEnabled {
            group = PerformanceScenarios.groups.first { $0.id == groupId }
                ?? PerformanceScenarios.groups[0]
            expenses = PerformanceScenarios.timeline
            groupedExpenses = Expense.groupExpensesByDate(expenses)
            errorMessage = ""
            return nil
        }
        async let groupResult = dataSource.group(groupId)
        async let expensesResult = dataSource.expenses(groupId)
        async let summaryResult = dataSource.summary(groupId)

        // Gather before publishing. If SwiftUI cancels its refresh task, none of a
        // three-request snapshot should replace the data already on screen.
        let loadedGroup: GroupDetail?
        let groupError: String?
        do {
            loadedGroup = try await groupResult
            groupError = nil
        } catch {
            if error.isCancellation { return nil }
            loadedGroup = nil
            groupError = L10n.Group.failedToLoadGroup(error.localizedDescription)
        }

        let loadedExpenses: [Expense]?
        let expensesError: String?
        do {
            loadedExpenses = try await expensesResult
            expensesError = nil
        } catch {
            if error.isCancellation { return nil }
            loadedExpenses = nil
            expensesError = L10n.Group.failedToLoadExpenses(error.localizedDescription)
        }

        let summary: GroupBalanceSummary?
        do {
            summary = try await summaryResult
        } catch {
            if error.isCancellation { return nil }
            summary = nil
        }

        // A newer load started while this one was in flight. Its snapshot is the current
        // one, and an older answer arriving late must not replace it.
        guard generation == loadGeneration else { return nil }

        errorMessage = expensesError ?? groupError ?? ""

        if let loadedExpenses {
            publishExpenses(loadedExpenses)
        }

        let displayedNetCents = group?.netBalanceCents
        // These requests began together. Even a settled summary may have raced ahead
        // of the group read, so finish a write with a group read after the summary.
        balancesPending = (summary?.balancesPending ?? balancesPending) || needsPostWriteSettlement
        if var loadedGroup {
            if balancesPending,
               pendingNetAdjustmentCents != 0,
               let displayedNetCents
            {
                // The pending flag cannot say whether this snapshot already includes our
                // payment. Keep the locally-correct displayed number instead of risking a
                // second adjustment or restoring the known-stale server value.
                loadedGroup.netBalanceCents = displayedNetCents
            } else if !balancesPending {
                pendingNetAdjustmentCents = 0
            }
            group = loadedGroup
        }

        return generation
    }

    private func publishExpenses(_ loadedExpenses: [Expense]) {
        var visibleExpenses = loadedExpenses
        var availableRows = loadedExpenses.filter { $0.type == .payment }
        for pending in expenses where pendingPaymentIds.contains(pending.id) {
            let knownIds = knownServerIdsAtPaymentWrite[pending.id] ?? []
            if let index = availableRows.firstIndex(where: { stored in
                !knownIds.contains(stored.id)
                    && stored.paidBy == pending.paidBy
                    && stored.amount == pending.amount
                    && stored.date.flatMap(Expense.parseTimestamp)
                        == pending.date.flatMap(Expense.parseTimestamp)
                    && Set(stored.splits.map(\.userId)) == Set(pending.splits.map(\.userId))
            }) {
                availableRows.remove(at: index)
                pendingPaymentIds.remove(pending.id)
                knownServerIdsAtPaymentWrite.removeValue(forKey: pending.id)
            } else {
                visibleExpenses.append(pending)
            }
        }
        expenses = visibleExpenses
        groupedExpenses = Expense.groupExpensesByDate(visibleExpenses)
    }

    /// The summary endpoint carries the worker's display hint. Fast retries taper to a
    /// low-frequency check and stop when this task is canceled or the hint clears.
    private func refreshPendingBalance(groupId: Int, generation: Int) async {
        guard balancesPending, generation == loadGeneration else { return }

        let pendingCleared = await BalanceRefreshPolicy.waitUntilPendingClears(
            groupId: groupId,
            balancesPending: true,
            fetch: dataSource.summary,
            wait: dataSource.waitForBalanceRetry
        ) { [weak self] summary in
            guard let self, generation == loadGeneration else { return false }
            if summary.balancesPending { balancesPending = true }
            return true
        }
        guard pendingCleared else { return }

        var retryIndex = 0
        while generation == loadGeneration {
            do {
                let refreshedGroup = try await dataSource.group(groupId)
                guard generation == loadGeneration else { return }

                pendingNetAdjustmentCents = 0
                needsPostWriteSettlement = false
                group = refreshedGroup
                balancesPending = false
                return
            } catch {
                if error.isCancellation { return }
            }

            let delay = BalanceRefreshPolicy.retryDelays[
                min(retryIndex, BalanceRefreshPolicy.retryDelays.count - 1)
            ]
            retryIndex += 1

            do {
                try await dataSource.waitForBalanceRetry(delay)
            } catch {
                if error.isCancellation { return }
            }
        }
    }

    /// A newer load takes over this retry when pull to refresh cancels its predecessor.
    /// The expense endpoint may lag the settled summary and group reads.
    private func refreshPendingPayments(groupId: Int, generation: Int) async {
        var retryIndex = 0
        while !pendingPaymentIds.isEmpty, generation == loadGeneration {
            do {
                let settledExpenses = try await dataSource.expenses(groupId)
                guard generation == loadGeneration else { return }
                publishExpenses(settledExpenses)
            } catch {
                if error.isCancellation { return }
            }
            guard !pendingPaymentIds.isEmpty else { return }
            let delay = BalanceRefreshPolicy.retryDelays[
                min(retryIndex, BalanceRefreshPolicy.retryDelays.count - 1)
            ]
            retryIndex += 1
            do {
                try await dataSource.waitForBalanceRetry(delay)
            } catch {
                if error.isCancellation { return }
            }
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
        date: Date? = nil,
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
            // Server-owned data, not copy: BalanceService writes this exact English
            // string and the refresh overwrites whatever we put here. The row title
            // is localized at render time instead.
            description: "Payment to \(peer.name)",
            type: .payment,
            category: .payment,
            splitMode: nil,
            date: date.map(ExpenseService.timestamp(from:)),
            createdAt: timestamp,
            updatedAt: timestamp,
            paidByUser: payer,
            splits: [
                ExpenseSplit(id: id * 10, expenseId: id, userId: currentUser.userId, amount: amount, percentage: nil, user: payer),
                ExpenseSplit(id: id * 10 - 1, expenseId: id, userId: peer.userId, amount: -amount, percentage: nil, user: payee)
            ]
        )

        pendingPaymentIds.insert(id)
        knownServerIdsAtPaymentWrite[id] = Set(expenses.filter { $0.id > 0 }.map(\.id))
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
                try await dataSource.deleteExpense(groupId, expense.id)
            case .payment:
                try await dataSource.deletePayment(groupId, expense.id)
            }
            needsPostWriteSettlement = true
            await refresh(groupId: groupId)
        } catch {
            if !error.isCancellation { actionErrorMessage = error.displayMessage }
        }
    }
}
