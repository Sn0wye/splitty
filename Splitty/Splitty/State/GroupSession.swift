import Foundation

enum GroupMoneyWrite {
    case expenseCreated(Expense)
    case expenseEdited(Expense)
    case paymentRecorded(payee: GroupMember, amountCents: Int, date: Date, currentUserId: Int)
    case paymentEdited(id: Int, amountCents: Int, date: Date)
}

enum GroupDeleteOutcome: Equatable {
    case deleted
    case alreadyGone
    case failed(String)
}

/// One group's observable state and work, independent of a screen's lifetime.
@MainActor
final class GroupSession: ObservableObject {
    @Published private(set) var group: GroupDetail?
    @Published private(set) var expenses: [Expense] = []
    @Published private(set) var groupedExpenses: [GroupedExpense] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedExpenses = false
    private var hasCompletedInitialRead = false
    @Published private(set) var errorMessage = ""

    /// A failed delete belongs next to the list, not in place of it: `errorMessage` blanks
    /// the timeline, which is the right shape for a load that failed and the wrong one for
    /// an action that did.
    @Published private(set) var actionErrorMessage: String?

    /// True while the balance worker still owes this group a recomputation, so the header
    /// number is known to predate the last write.
    @Published private(set) var balancesPending = false
    @Published private(set) var latestSummary: GroupBalanceSummary?

    /// Negative ids exist until an expense refetch supplies the matching server rows.
    private var pendingPaymentIds: Set<Int> = []
    private var pendingRows: [Int: PendingRowWrite] = [:]
    private var hiddenDeletionIds: Set<Int> = []
    private var successfulDeletionIds: Set<Int> = []
    private var knownServerIdsAtPaymentWrite: [Int: Set<Int>] = [:]
    private var nextPendingPaymentId = -1
    private var pendingNetAdjustmentCents = 0
    private var needsPostWriteSettlement = false

    private let dataSource: GroupDataSource

    /// The refresh this session owns, so a new one can cancel the one it replaces
    /// instead of racing it.
    private var refreshTask: Task<Void, Never>?
    private var balanceWatchTask: Task<Void, Never>?
    private var rowReconciliationTask: Task<Void, Never>?
    private var balanceWatchGeneration = 0

    /// Counts started loads. A load that is no longer the newest publishes nothing:
    /// cancellation is cooperative and a request already past its last suspension point
    /// would otherwise overwrite a fresher snapshot.
    private var loadGeneration = 0

    private enum PendingRowWrite {
        case expense(Expense)
        case payment(Expense)

        var row: Expense {
            switch self {
            case .expense(let row), .payment(let row): row
            }
        }

        func matches(_ stored: Expense) -> Bool {
            let expected = row
            guard stored.type == expected.type,
                  Money.cents(from: stored.amount) == Money.cents(from: expected.amount),
                  stored.date.flatMap(Expense.parseTimestamp) == expected.date.flatMap(Expense.parseTimestamp)
            else { return false }
            switch self {
            case .payment:
                return true
            case .expense:
                return stored.paidBy == expected.paidBy
                    && stored.description == expected.description
                    && stored.category == expected.category
                    && stored.splitMode == expected.splitMode
                    && stored.splits.count == expected.splits.count
                    && expected.splits.allSatisfy { split in
                        stored.splits.contains {
                            $0.userId == split.userId
                                && Money.cents(from: $0.amount) == Money.cents(from: split.amount)
                                && $0.percentage == split.percentage
                        }
                    }
            }
        }

        func isSuperseded(by stored: Expense) -> Bool {
            guard let storedAt = Expense.parseTimestamp(stored.updatedAt),
                  let expectedAt = Expense.parseTimestamp(row.updatedAt)
            else { return false }
            return storedAt > expectedAt
        }
    }

    let groupId: Int
    private var initialLoad: Task<Void, Never>?
    private var finishedInitialLoad = false
    @Published private(set) var summaryErrorMessage: String?

    init(groupId: Int, seed: Group? = nil, dataSource: GroupDataSource = .live) {
        self.groupId = groupId
        self.group = seed
        self.dataSource = dataSource
    }

    func balanceState(currentUserId: Int) -> BalancesDisplayState {
        if let summaryErrorMessage { return .error(summaryErrorMessage) }
        guard let latestSummary else { return .loading }
        return BalancesDisplayState(summary: latestSummary, currentUserId: currentUserId)
    }

    var netBalanceCents: Int? { group?.netBalanceCents }

    @discardableResult
    func appear() -> Task<Void, Never> {
        if !finishedInitialLoad {
            if let initialLoad {
                if !hasCompletedInitialRead { return initialLoad }
                initialLoad.cancel()
                finishedInitialLoad = true
                return beginRefresh()
            }
            let task = Task { [weak self] in
                guard let self else { return }
                await loadGroupData()
                finishedInitialLoad = true
            }
            initialLoad = task
            return task
        }
        return beginRefresh()
    }

    func discard() {
        initialLoad?.cancel()
        cancelRefresh()
    }

    @discardableResult
    func record(_ result: SettleUpResult, currentUserId: Int) -> Task<Void, Never> {
        if let id = result.settlementId {
            return report(.paymentEdited(id: id, amountCents: result.amountCents, date: result.date))
        }
        return report(.paymentRecorded(payee: result.peer, amountCents: result.amountCents,
                                       date: result.date, currentUserId: currentUserId))
    }

    func summaryForSettleUp() async throws -> GroupBalanceSummary {
        try await summary(force: !balancesPending)
    }

    func readSummary() async throws -> GroupBalanceSummary {
        try await summary(force: false)
    }

    func refreshBalances() async {
        do {
            try await dataSource.requestBalanceRefresh(groupId)
            await refresh()
        } catch {
            if !error.isCancellation { summaryErrorMessage = error.displayMessage }
        }
    }

    var members: [GroupMember] { group?.members ?? [] }

    /// Charts only has something to chart once an expense exists, and asks for one until
    /// then: settlements count in neither group spend nor share.
    var hasExpenses: Bool {
        expenses.contains { $0.type == .expense }
    }

    private func loadGroupData() async {
        isLoading = group == nil
        let generation = await load()
        isLoading = false
        hasCompletedInitialRead = true

        if let generation { startBackgroundWork(generation: generation) }
    }

    /// Pull to refresh returns after the three snapshot reads publish. The balance
    /// watcher keeps working after the refresh spinner stops.
    func refresh() async {
        refreshTask?.cancel()
        let generation = await load()
        if let generation { startBackgroundWork(generation: generation) }
    }

    @discardableResult
    func report(_ write: GroupMoneyWrite) -> Task<Void, Never> {
        cancelRefresh()
        needsPostWriteSettlement = true
        balancesPending = true
        switch write {
        case .expenseCreated(let row), .expenseEdited(let row):
            insert(row)
            pendingRows[row.id] = .expense(row)
        case .paymentRecorded(let payee, let amountCents, let date, let currentUserId):
            if let currentUser = members.first(where: { $0.userId == currentUserId }) {
                insertPendingPayment(
                    currentUser: currentUser,
                    peer: payee,
                    amountCents: amountCents,
                    date: date
                )
            }
        case .paymentEdited(let id, let amountCents, let date):
            if let index = expenses.firstIndex(where: { $0.id == id && $0.type == .payment }) {
                let old = expenses[index]
                expenses[index] = Expense(
                    id: old.id, groupId: old.groupId, paidBy: old.paidBy,
                    amount: Money.amount(cents: amountCents), description: old.description,
                    type: old.type, category: old.category, splitMode: old.splitMode,
                    date: ExpenseService.timestamp(from: date), createdAt: old.createdAt,
                    updatedAt: old.updatedAt, paidByUser: old.paidByUser, splits: old.splits
                )
                groupedExpenses = Expense.groupExpensesByDate(expenses)
                pendingRows[id] = .payment(expenses[index])
            }
        }
        return beginRefresh()
    }

    /// Starts a refresh the session owns for callers with nothing to await, such as
    /// group settings, instead of spawning a task nobody can cancel.
    @discardableResult
    private func beginRefresh() -> Task<Void, Never> {
        refreshTask?.cancel()
        let task = Task { [weak self] () -> Void in
            await self?.reloadSnapshot()
        }
        refreshTask = task
        return task
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        rowReconciliationTask?.cancel()
        rowReconciliationTask = nil
        balanceWatchTask?.cancel()
        balanceWatchTask = nil
        balanceWatchGeneration += 1
        loadGeneration += 1
    }

    /// Shows a just-saved expense without waiting for the refetch. The row is real — the
    /// server returned it — while the *balance* it feeds is not, which is what
    /// `balancesPending` says.
    private func insert(_ expense: Expense) {
        expenses.removeAll { $0.id == expense.id }
        expenses.append(expense)
        groupedExpenses = Expense.groupExpensesByDate(expenses)
    }

    private func reloadSnapshot() async {
        guard let generation = await load() else { return }
        startBackgroundWork(generation: generation)
    }

    private func startBackgroundWork(generation: Int) {
        startBalanceWatch()
        rowReconciliationTask?.cancel()
        if !pendingPaymentIds.isEmpty || !pendingRows.isEmpty {
            rowReconciliationTask = Task { [weak self] in
                await self?.reconcilePendingRows(generation: generation)
            }
        }
    }

    private func startBalanceWatch() {
        guard balancesPending, balanceWatchTask == nil else { return }
        balanceWatchGeneration += 1
        let generation = balanceWatchGeneration
        balanceWatchTask = Task { [weak self] in
            await self?.watchBalance(generation: generation)
        }
    }

    private func load() async -> Int? {
        guard !Task.isCancelled else { return nil }
        loadGeneration += 1
        let generation = loadGeneration

        if PerformanceScenarioLaunch.isEnabled {
            group = PerformanceScenarios.groups.first { $0.id == groupId }
                ?? PerformanceScenarios.groups[0]
            expenses = PerformanceScenarios.timeline
            groupedExpenses = Expense.groupExpensesByDate(expenses)
            hasLoadedExpenses = true
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
        let summaryError: String?
        do {
            summary = try await summaryResult
            summaryError = nil
        } catch {
            if error.isCancellation { return nil }
            summary = nil
            summaryError = error.displayMessage
        }

        // A newer load started while this one was in flight. Its snapshot is the current
        // one, and an older answer arriving late must not replace it.
        guard generation == loadGeneration, !Task.isCancelled else { return nil }
        summaryErrorMessage = summaryError

        // A failed background read cannot replace a timeline already on screen.
        errorMessage = hasLoadedExpenses ? "" : (expensesError ?? (group == nil ? groupError : nil) ?? "")

        if let loadedExpenses {
            publishExpenses(loadedExpenses)
            hasLoadedExpenses = true
        }

        let displayedNetCents = group?.netBalanceCents
        // These requests began together. Even a settled summary may have raced ahead
        // of the group read, so finish a write with a group read after the summary.
        if let summary {
            latestSummary = summary
        }
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
        var visibleExpenses = loadedExpenses.filter { !hiddenDeletionIds.contains($0.id) }
        for (id, pending) in Array(pendingRows) {
            if let stored = loadedExpenses.first(where: { $0.id == id }),
               pending.matches(stored) || pending.isSuperseded(by: stored) {
                pendingRows.removeValue(forKey: id)
            } else {
                visibleExpenses.removeAll { $0.id == id }
                visibleExpenses.append(pending.row)
            }
        }
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
        let serverIds = Set(loadedExpenses.map(\.id))
        let confirmedAbsent = successfulDeletionIds.filter { !serverIds.contains($0) }
        hiddenDeletionIds.subtract(confirmedAbsent)
        successfulDeletionIds.subtract(confirmedAbsent)
    }

    private func summary(force: Bool) async throws -> GroupBalanceSummary {
        if !force, let latestSummary { return latestSummary }
        let summary: GroupBalanceSummary
        do {
            summary = try await dataSource.summary(groupId)
            summaryErrorMessage = nil
        } catch {
            if !error.isCancellation { summaryErrorMessage = error.displayMessage }
            throw error
        }
        latestSummary = summary
        balancesPending = summary.balancesPending || needsPostWriteSettlement
        if balancesPending { startBalanceWatch() }
        return summary
    }

    private func watchBalance(generation: Int) async {
        defer {
            if generation == balanceWatchGeneration { balanceWatchTask = nil }
        }
        let pendingCleared = await BalanceRefreshPolicy.waitUntilPendingClears(
            groupId: groupId,
            balancesPending: true,
            fetch: dataSource.summary,
            wait: dataSource.waitForBalanceRetry
        ) { [weak self] summary in
            guard let self, generation == balanceWatchGeneration else { return false }
            latestSummary = summary
            summaryErrorMessage = nil
            return true
        }
        guard pendingCleared else { return }

        var retryIndex = 0
        while generation == balanceWatchGeneration {
            do {
                let refreshedGroup = try await dataSource.group(groupId)
                guard generation == balanceWatchGeneration else { return }

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
    private func reconcilePendingRows(generation: Int) async {
        var retryIndex = 0
        while (!pendingPaymentIds.isEmpty || !pendingRows.isEmpty), generation == loadGeneration {
            do {
                let settledExpenses = try await dataSource.expenses(groupId)
                guard generation == loadGeneration else { return }
                publishExpenses(settledExpenses)
            } catch {
                if error.isCancellation { return }
            }
            guard !pendingPaymentIds.isEmpty || !pendingRows.isEmpty else { return }
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
    private func insertPendingPayment(
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
    func delete(_ expense: Expense) -> Task<GroupDeleteOutcome, Never> {
        guard expense.id > 0 else {
            return Task { .failed(CancellationError().displayMessage) }
        }
        let index = expenses.firstIndex(where: { $0.id == expense.id })
        actionErrorMessage = nil
        cancelRefresh()
        hiddenDeletionIds.insert(expense.id)
        let pendingWrite = pendingRows.removeValue(forKey: expense.id)
        if let index { expenses.remove(at: index) }
        groupedExpenses = Expense.groupExpensesByDate(expenses)

        return Task { [weak self] in
            guard let self else { return .failed(CancellationError().displayMessage) }
            var outcome = GroupDeleteOutcome.deleted
            do {
                switch expense.type {
                case .expense:
                    try await dataSource.deleteExpense(groupId, expense.id)
                case .payment:
                    try await dataSource.deletePayment(groupId, expense.id)
                }
            } catch {
                if !error.isAlreadyGone {
                    hiddenDeletionIds.remove(expense.id)
                    if let pendingWrite { pendingRows[expense.id] = pendingWrite }
                    if let index {
                        expenses.insert(pendingWrite?.row ?? expense, at: min(index, expenses.count))
                        groupedExpenses = Expense.groupExpensesByDate(expenses)
                    }
                    if !error.isCancellation { actionErrorMessage = error.displayMessage }
                    startBackgroundWork(generation: loadGeneration)
                    return .failed(error.displayMessage)
                }
                outcome = .alreadyGone
            }
            needsPostWriteSettlement = true
            balancesPending = true
            successfulDeletionIds.insert(expense.id)
            beginRefresh()
            return outcome
        }
    }
}
