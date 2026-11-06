import Combine
import Foundation
import SwiftUI

enum GroupMoneyWrite {
    case expenseCreated(Expense)
    case expenseEdited(Expense)
    /// A "this and following" edit. The server also rewrote or removed the later expenses
    /// the same recurring expense added, so only a refetch can show them.
    case expenseEditedWithFollowing(Expense)
    /// `clientId` matches the payment to the server's row; `queued` says it has not been
    /// sent yet, so its net comes from the outbox until it is (ADR 0008).
    case paymentRecorded(payerId: Int, payeeId: Int, amountCents: Int, date: Date, currentUserId: Int,
                         clientId: UUID? = nil, queued: Bool = false)
    case paymentEdited(id: Int, amountCents: Int, date: Date)
}

enum GroupDeleteOutcome: Equatable {
    case deleted
    case alreadyGone
    case failed(String)

    /// What the screen the delete came from shows; nil when the row is gone either way.
    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// How a row stands with the server, when this device has a write for it not yet confirmed.
enum RowSyncState: Equatable {
    /// Kept to send; nothing is wrong.
    case waiting
    /// The server refused it in a way only the member can resolve.
    case needsAttention
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
    /// Where this group's last snapshot is kept, so it opens without a network.
    private let cache: GroupCache?
    /// The writes made on this device and not confirmed yet (ADR 0008).
    let outbox: Outbox?
    private var outboxSubscriptions: Set<AnyCancellable> = []
    /// The outbox writes this session shows as not yet sent. A write a screen is still
    /// waiting on is not in here: that screen reports it once it knows how it went.
    private var queuedWriteIds: Set<UUID> = []
    /// When the rows on screen were read, once a read has failed and they are this device's
    /// copy. Nil while the server's answer is still coming, and once a read succeeds.
    @Published private(set) var savedAt: Date?
    /// When the copy on screen was saved, shown only after a read fails.
    private var shownCopySavedAt: Date?

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

    init(
        groupId: Int,
        seed: Group? = nil,
        dataSource: GroupDataSource = .live,
        cache: GroupCache? = nil,
        outbox: Outbox? = nil
    ) {
        self.groupId = groupId
        self.group = seed
        self.dataSource = dataSource
        self.cache = cache
        self.outbox = outbox
        // The scenario's rows are local, so they are already in hand when the session is
        // made: the first frame shows them instead of a loader waiting for `.task`.
        if PerformanceScenarioLaunch.isEnabled {
            publishPerformanceScenario()
            return
        }
        if let snapshot = cache?.snapshot(groupId: groupId) { restore(snapshot) }
        if let outbox {
            restoreQueuedWrites(from: outbox)
            outbox.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &outboxSubscriptions)
            outbox.events
                .filter { [groupId] in $0.write.groupId == groupId }
                .sink { [weak self] in self?.handle($0) }
                .store(in: &outboxSubscriptions)
        }
    }

    /// A failed read cannot replace balances already on screen, the same rule the timeline
    /// follows.
    func balanceState(currentUserId: Int) -> BalancesDisplayState {
        if let displaySummary { return BalancesDisplayState(summary: displaySummary, currentUserId: currentUserId) }
        if let summaryErrorMessage { return .error(summaryErrorMessage) }
        return .loading
    }

    /// The signed-in member's net as shown: the server's, plus what this device's unsent
    /// writes will move it by.
    var netBalanceCents: Int? { group.map { $0.netBalanceCents + queuedNetCents } }

    /// The server's simplified debts with this device's unsent writes added and simplified
    /// again, the way the server will once it has them. An estimate while `hasUnsentWrites`.
    var displaySummary: GroupBalanceSummary? {
        guard let latestSummary else { return nil }
        let nets = queuedWrites.reduce(into: [Int: Int]()) { $0 = LedgerMath.adding($0, $1.nets) }
        return LedgerMath.projected(latestSummary, adding: nets, members: members)
    }

    /// True while the figures on screen count writes the server has not seen.
    var hasUnsentWrites: Bool { !queuedWrites.isEmpty }

    /// Every write of this group the outbox holds, problems first.
    var unsentWrites: [PendingWrite] {
        let writes = outbox?.writes(for: groupId) ?? []
        return writes.filter { $0.problem != nil } + writes.filter { $0.problem == nil }
    }

    var isOffline: Bool { outbox.map { !$0.isOnline } ?? false }

    func syncState(for expense: Expense) -> RowSyncState? {
        guard let write = write(for: expense) else { return nil }
        return write.problem == nil ? .waiting : .needsAttention
    }

    private var queuedWrites: [PendingWrite] {
        guard let outbox, !queuedWriteIds.isEmpty else { return [] }
        return outbox.writes(for: groupId).filter { queuedWriteIds.contains($0.id) }
    }

    private var queuedNetCents: Int {
        guard let me = outbox?.userId else { return 0 }
        return queuedWrites.reduce(0) { $0 + ($1.nets[me] ?? 0) }
    }

    /// The outbox write behind a row: by the id it was created under, then by the row it touches.
    private func write(for expense: Expense) -> PendingWrite? {
        guard let outbox else { return nil }
        if let clientId = expense.clientId, let write = outbox.writes.first(where: { $0.id == clientId }) {
            return write
        }
        return outbox.write(touching: expense.id).flatMap { $0.groupId == groupId ? $0 : nil }
    }

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
        return report(.paymentRecorded(payerId: result.payerId, payeeId: result.payeeId,
                                       amountCents: result.amountCents, date: result.date,
                                       currentUserId: currentUserId,
                                       clientId: result.clientId, queued: result.queued))
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

    /// Where the expense sheet sends its writes: through the outbox when there is one.
    func expenseFormDataSource() -> ExpenseFormDataSource {
        guard let outbox else { return .live }
        return .queued(outbox: outbox, members: members, currency: currency) { [weak self] id in
            self?.expenses.first { $0.id == id }
        }
    }

    /// Where the settle-up sheet sends a new payment.
    func settleUpDataSource() -> SettleUpDataSource {
        outbox.map { .queued(outbox: $0, currency: currency) } ?? .live
    }
    var currency: Currency { group?.currency ?? .usd }

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
        // A write still on this device moves no server figure, so nothing is pending for it:
        // the outbox's estimate covers it until it is sent.
        let queued = markQueued(write)
        if !queued {
            needsPostWriteSettlement = true
            balancesPending = true
        }
        switch write {
        case .expenseCreated(let row), .expenseEdited(let row):
            insert(row)
            pendingRows[row.id] = .expense(row)
        case .expenseEditedWithFollowing(let row):
            // Shown at once like any saved row, but not held against the refetch: the
            // edit committed with the later rows it rewrote, so the next read is current.
            insert(row)
            pendingRows.removeValue(forKey: row.id)
        case .paymentRecorded(let payerId, let payeeId, let amountCents, let date, let currentUserId, let clientId, let queued):
            if let payer = members.first(where: { $0.userId == payerId }),
               let payee = members.first(where: { $0.userId == payeeId }) {
                insertPendingPayment(
                    payer: payer,
                    payee: payee,
                    amountCents: amountCents,
                    currentUserId: currentUserId,
                    date: date,
                    clientId: clientId,
                    adjustsNet: !queued
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
    func beginRefresh() -> Task<Void, Never> {
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
            publishPerformanceScenario()
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
        save(group: loadedGroup, expenses: loadedExpenses, summary: summary)
        if loadedExpenses == nil, let shownCopySavedAt { savedAt = shownCopySavedAt }

        // A failed background read cannot replace a timeline already on screen.
        errorMessage = hasLoadedExpenses ? "" : (expensesError ?? (group == nil ? groupError : nil) ?? "")

        if let loadedExpenses {
            publishExpenses(loadedExpenses)
            if !hasLoadedExpenses { hasLoadedExpenses = true }
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

    // MARK: - This device's copy

    /// What a read returned, kept so the group opens without a network. A read that failed
    /// keeps the part it had before.
    private func save(group loadedGroup: GroupDetail?, expenses loadedExpenses: [Expense]?, summary: GroupBalanceSummary?) {
        guard let cache, loadedGroup != nil || loadedExpenses != nil || summary != nil else { return }
        let previous = cache.snapshot(groupId: groupId)
        guard let expenses = loadedExpenses ?? previous?.expenses else { return }
        cache.save(GroupSnapshot(
            group: loadedGroup ?? previous?.group,
            expenses: expenses,
            summary: summary ?? previous?.summary,
            savedAt: loadedExpenses == nil ? previous?.savedAt ?? Date() : Date()
        ), groupId: groupId)
        if loadedExpenses != nil {
            savedAt = nil
            shownCopySavedAt = nil
        }
    }

    /// Shows the copy this device kept, before any read. The seed from the groups list is
    /// newer than the copy's group, so it wins.
    private func restore(_ snapshot: GroupSnapshot) {
        if group == nil { group = snapshot.group }
        latestSummary = snapshot.summary
        publishExpenses(snapshot.expenses)
        hasLoadedExpenses = true
        shownCopySavedAt = snapshot.savedAt
    }

    /// Shows every write the outbox still holds for this group, as it was shown when it was
    /// made: a session opened later, or after a relaunch, picks up where the last one was.
    private func restoreQueuedWrites(from outbox: Outbox) {
        for write in outbox.writes(for: groupId) {
            queuedWriteIds.insert(write.id)
            switch write.action {
            case .createExpense(_, let row), .editExpense(_, _, let row):
                insert(row)
                pendingRows[row.id] = .expense(row)
            case .deleteExpense(let base), .deleteSettlement(let base):
                hiddenDeletionIds.insert(base.id)
                expenses.removeAll { $0.id == base.id }
                groupedExpenses = Expense.groupExpensesByDate(expenses)
            case .settle(let draft, _):
                guard let me = outbox.userId,
                      let payer = members.first(where: { $0.userId == draft.payerId ?? me }),
                      let payee = members.first(where: { $0.userId == draft.payeeId })
                else { continue }
                insertPendingPayment(payer: payer, payee: payee, amountCents: draft.amountCents,
                                     currentUserId: me, date: draft.date, clientId: write.id,
                                     adjustsNet: false)
            }
        }
    }

    /// Whether `write` is one the outbox is still holding, and if so, remembers it so its
    /// estimate shows until the outbox says how it went.
    private func markQueued(_ write: GroupMoneyWrite) -> Bool {
        guard let outbox else { return false }
        switch write {
        case .expenseCreated(let row), .expenseEdited(let row):
            guard let queued = self.write(for: row) else { return false }
            queuedWriteIds.insert(queued.id)
            return true
        case .paymentRecorded(_, _, _, _, _, let clientId, let queued):
            guard queued, let clientId, outbox.writes.contains(where: { $0.id == clientId }) else { return false }
            queuedWriteIds.insert(clientId)
            return true
        case .expenseEditedWithFollowing, .paymentEdited:
            return false
        }
    }

    private func handle(_ event: OutboxEvent) {
        let write = event.write
        // A write a screen was still waiting on is that screen's to report.
        guard queuedWriteIds.remove(write.id) != nil else { return }

        switch event {
        case .confirmed(_, let row):
            // The server has it now but its figures may not yet: hold the estimate the
            // way a payment made online is held, until the next settled read.
            if let me = outbox?.userId, let mine = write.nets[me], mine != 0 {
                group?.netBalanceCents += mine
                pendingNetAdjustmentCents += mine
            }
            needsPostWriteSettlement = true
            balancesPending = true
            switch write.action {
            case .createExpense(_, let local):
                pendingRows.removeValue(forKey: local.id)
                expenses.removeAll { $0.id == local.id }
                if let row {
                    insert(row)
                    pendingRows[row.id] = .expense(row)
                }
            case .editExpense(_, _, let local):
                if let row {
                    insert(row)
                    pendingRows[row.id] = .expense(row)
                } else {
                    pendingRows.removeValue(forKey: local.id)
                }
            case .deleteExpense(let base), .deleteSettlement(let base):
                successfulDeletionIds.insert(base.id)
            case .settle:
                // The payment on screen matches the server's row by client id on the next read.
                break
            }
        case .dropped:
            switch write.action {
            case .createExpense(_, let local):
                pendingRows.removeValue(forKey: local.id)
                expenses.removeAll { $0.id == local.id }
            case .editExpense(_, let base, let local):
                pendingRows.removeValue(forKey: local.id)
                switch write.problem {
                // A delete wins: the row is not coming back, whatever is done with the edit.
                case .deletedElsewhere: expenses.removeAll { $0.id == base.id }
                case .conflict(let theirs): insert(theirs)
                default: insert(base)
                }
            case .deleteExpense(let base), .deleteSettlement(let base):
                hiddenDeletionIds.remove(base.id)
                if !expenses.contains(where: { $0.id == base.id }) { insert(base) }
            case .settle:
                let shown = expenses.filter { $0.clientId == write.id && pendingPaymentIds.contains($0.id) }
                for payment in shown {
                    pendingPaymentIds.remove(payment.id)
                    knownServerIdsAtPaymentWrite.removeValue(forKey: payment.id)
                }
                expenses.removeAll { row in shown.contains { $0.id == row.id } }
            }
        }
        groupedExpenses = Expense.groupExpensesByDate(expenses)
        beginRefresh()
    }

    private func publishExpenses(_ loadedExpenses: [Expense]) {
        var visibleExpenses = loadedExpenses.filter { !hiddenDeletionIds.contains($0.id) }
        let heldIds = Set(queuedWrites.filter { !$0.isDelete }.map(\.row.id))
        for (id, pending) in Array(pendingRows) {
            // A write not sent yet holds its row: the server's copy cannot match or supersede
            // an edit it has never seen.
            if !heldIds.contains(id),
               let stored = loadedExpenses.first(where: { $0.id == id }),
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
                // The id it was sent under is exact; the shape below is a guess for a
                // payment recorded without one.
                if let clientId = pending.clientId { return stored.clientId == clientId }
                return !knownIds.contains(stored.id)
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
        if !hasLoadedExpenses {
            expenses = visibleExpenses
            groupedExpenses = Expense.groupExpensesByDate(visibleExpenses)
        } else if visibleExpenses != expenses {
            // Rows already on screen stay put: the fresh read changes only those that
            // differ, and new rows slide in rather than the list redrawing.
            let grouped = Expense.groupExpensesByDate(visibleExpenses)
            withAnimation(.snappy) {
                expenses = visibleExpenses
                groupedExpenses = grouped
            }
        }
        let serverIds = Set(loadedExpenses.map(\.id))
        let confirmedAbsent = successfulDeletionIds.filter { !serverIds.contains($0) }
        hiddenDeletionIds.subtract(confirmedAbsent)
        successfulDeletionIds.subtract(confirmedAbsent)
    }

    private func publishPerformanceScenario() {
        if group == nil {
            group = PerformanceScenarios.groups.first { $0.id == groupId }
                ?? PerformanceScenarios.groups[0]
        }
        publishExpenses(PerformanceScenarios.timeline)
        if !hasLoadedExpenses { hasLoadedExpenses = true }
        if !errorMessage.isEmpty { errorMessage = "" }
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
        payer: GroupMember,
        payee: GroupMember,
        amountCents: Int,
        currentUserId: Int,
        date: Date? = nil,
        clientId: UUID? = nil,
        adjustsNet: Bool = true,
        now: Date = Date()
    ) -> Expense {
        let id = nextPendingPaymentId
        nextPendingPaymentId -= 1
        let timestamp = ExpenseService.timestamp(from: now)
        let payerUser = Self.user(from: payer, timestamp: timestamp)
        let payeeUser = Self.user(from: payee, timestamp: timestamp)
        let amount = Money.amount(cents: amountCents)

        let payment = Expense(
            id: id,
            groupId: groupId,
            paidBy: payer.userId,
            amount: amount,
            // Server-owned data, not copy: BalanceService writes this exact English
            // string and the refresh overwrites whatever we put here. The row title
            // is localized at render time instead.
            description: "Payment to \(payee.name)",
            type: .payment,
            category: .payment,
            splitMode: nil,
            date: date.map(ExpenseService.timestamp(from:)),
            createdAt: timestamp,
            updatedAt: timestamp,
            paidByUser: payerUser,
            splits: [
                ExpenseSplit(id: id * 10, expenseId: id, userId: payer.userId, amount: amount, percentage: nil, user: payerUser),
                ExpenseSplit(id: id * 10 - 1, expenseId: id, userId: payee.userId, amount: -amount, percentage: nil, user: payeeUser)
            ],
            clientId: clientId
        )

        pendingPaymentIds.insert(id)
        knownServerIdsAtPaymentWrite[id] = Set(expenses.filter { $0.id > 0 }.map(\.id))
        insert(payment)
        // A payment still on this device is counted by the outbox until it is sent. Paying
        // raises the current user's net, being paid lowers it, and a payment between two
        // others leaves it alone.
        if adjustsNet {
            let netChange = payer.userId == currentUserId ? amountCents
                : payee.userId == currentUserId ? -amountCents : 0
            pendingNetAdjustmentCents += netChange
            group?.netBalanceCents += netChange
            balancesPending = true
        }
        return payment
    }

    /// A queued payment the member lowered to the cap the server gave.
    func resizeQueuedPayment(clientId: UUID, toCents cents: Int) {
        guard let index = expenses.firstIndex(where: { $0.clientId == clientId && pendingPaymentIds.contains($0.id) }) else { return }
        let old = expenses[index]
        let amount = Money.amount(cents: cents)
        expenses[index] = Expense(
            id: old.id, groupId: old.groupId, paidBy: old.paidBy, amount: amount,
            description: old.description, type: old.type, category: old.category, splitMode: old.splitMode,
            date: old.date, createdAt: old.createdAt, updatedAt: old.updatedAt, paidByUser: old.paidByUser,
            splits: old.splits.map { split in
                ExpenseSplit(id: split.id, expenseId: split.expenseId, userId: split.userId,
                             amount: split.userId == old.paidBy ? amount : -amount,
                             percentage: nil, user: split.user)
            },
            clientId: old.clientId
        )
        groupedExpenses = Expense.groupExpensesByDate(expenses)
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
    ///
    /// `scope` matters only for an expense a recurring expense added. `.following` also
    /// takes the later expenses the same recurring expense added off the list at once,
    /// since the server deletes them with this one.
    func delete(_ expense: Expense, scope: ExpenseScope? = nil) -> Task<GroupDeleteOutcome, Never> {
        let scope = expense.isRecurring ? scope : nil
        // A row that exists only on this device is deleted by dropping the write behind it.
        if expense.id < 0, let outbox, let write = write(for: expense) {
            guard !outbox.isSending(write) else { return Task { .failed(L10n.Sync.stillSending) } }
            outbox.discard(write.id)
            return Task { .deleted }
        }
        guard expense.id > 0 else {
            return Task { .failed(L10n.Errors.generic) }
        }
        let removedIds = Set([expense.id] + (scope == .following ? laterRows(than: expense).map(\.id) : []))
        // Kept in list order, so a failure can put every row back where it was.
        let removed = expenses.enumerated().filter { removedIds.contains($0.element.id) }
        actionErrorMessage = nil
        cancelRefresh()
        hiddenDeletionIds.formUnion(removedIds)
        var pendingWrites: [Int: PendingRowWrite] = [:]
        for id in removedIds {
            pendingWrites[id] = pendingRows.removeValue(forKey: id)
        }
        expenses.removeAll { removedIds.contains($0.id) }
        groupedExpenses = Expense.groupExpensesByDate(expenses)

        return Task { [weak self] in
            guard let self else { return .failed(L10n.Errors.generic) }
            var outcome = GroupDeleteOutcome.deleted
            do {
                if let outbox, scope != .following {
                    let write = PendingWrite(
                        id: UUID(),
                        groupId: groupId,
                        action: expense.type == .payment ? .deleteSettlement(base: expense) : .deleteExpense(base: expense)
                    )
                    switch await outbox.submit(write) {
                    case .confirmed:
                        break
                    case .queued:
                        // Hidden until the outbox sends it; nothing on the server moved yet.
                        queuedWriteIds.insert(write.id)
                        return .deleted
                    case .refused(let error):
                        throw error
                    }
                } else {
                    switch expense.type {
                    case .expense:
                        try await dataSource.deleteExpense(groupId, expense.id, scope)
                    case .payment:
                        try await dataSource.deletePayment(groupId, expense.id)
                    }
                }
            } catch {
                if !error.isAlreadyGone {
                    hiddenDeletionIds.subtract(removedIds)
                    pendingRows.merge(pendingWrites) { _, restored in restored }
                    if !removed.isEmpty {
                        for (index, row) in removed {
                            expenses.insert(pendingWrites[row.id]?.row ?? row, at: min(index, expenses.count))
                        }
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
            successfulDeletionIds.formUnion(removedIds)
            beginRefresh()
            return outcome
        }
    }

    /// The rows the same recurring expense added after `expense`, by the date each is
    /// filed under — the same "after" the server deletes by.
    private func laterRows(than expense: Expense) -> [Expense] {
        guard let recurringExpenseId = expense.recurringExpenseId,
              let date = expense.effectiveDate
        else { return [] }
        return expenses.filter { row in
            row.recurringExpenseId == recurringExpenseId
                && row.id != expense.id
                && (row.effectiveDate.map { $0 > date } ?? false)
        }
    }
}
