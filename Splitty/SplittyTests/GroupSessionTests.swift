import Foundation
import Testing
@testable import Splitty

@MainActor
struct GroupSessionTests {
    @Test func seededOpenShowsHeaderWhileTimelineLoads() async throws {
        let data = ControlledGroupData()
        let store = GroupSessionStore(dataSource: { data.source() })
        let seed = group(id: 1, name: "From list", net: 725)
        let session = store.open(1, seed: seed)

        #expect(session.snapshot.group?.name == "From list")
        #expect(session.snapshot.group?.netBalanceCents == 725)
        #expect(session.snapshot.members.count == seed.members.count)
        #expect(!session.snapshot.hasLoadedExpenses)
        #expect(!session.snapshot.isLoading)

        let load = session.appear()
        await data.waitForExpenseCall(1)
        #expect(!session.snapshot.hasLoadedExpenses)
        #expect(!session.snapshot.isLoading)
        data.release(call: 1)
        await load.value
        #expect(session.snapshot.hasLoadedExpenses)
        #expect(data.groupCallCount == 1)
        #expect(data.expenseCallCount == 1)
        #expect(data.summaryCallCount == 1)
    }

    @Test func returningKeepsPaymentAndNetAndStartsOneBackgroundRefresh() async throws {
        let data = ControlledGroupData()
        data.groupForCall = { _ in self.group(id: 1, net: -500) }
        let store = GroupSessionStore(dataSource: { data.source() })
        let session = store.open(1, seed: group(id: 1, net: -500))
        let first = session.appear()
        await data.waitForExpenseCall(1)
        data.release(call: 1)
        await first.value

        let payment = session.snapshot.insertPendingPayment(
            groupId: 1,
            currentUser: TestExpense.members[0],
            peer: TestExpense.members[1],
            amountCents: 500
        )
        #expect(payment.id < 0)
        #expect(session.snapshot.group?.netBalanceCents == 0)
        #expect(session.snapshot.balancesPending)

        let reopened = store.open(1, seed: group(id: 1, name: "Stale list", net: -500))
        #expect(reopened === session)
        #expect(reopened.snapshot.expenses.map(\.id) == [payment.id])
        #expect(reopened.snapshot.group?.netBalanceCents == 0)

        let refresh = reopened.appear()
        await data.waitForExpenseCall(2)
        #expect(data.expenseCallCount == 2)
        #expect(data.groupCallCount == 2)
        #expect(data.summaryCallCount == 2)
        #expect(!reopened.snapshot.isLoading)
        #expect(reopened.snapshot.expenses.map(\.id) == [payment.id])
        data.fail(call: 2, with: CancellationError())
        await refresh.value
        #expect(reopened.snapshot.expenses.map(\.id) == [payment.id])
        #expect(reopened.snapshot.group?.netBalanceCents == 0)
    }

    @Test func failedBackgroundRefreshKeepsLoadedRowsAndNoLoadError() async {
        let data = ControlledGroupData()
        let row = TestExpense.make(id: 41, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [row] }
        let session = GroupSessionStore(dataSource: { data.source() }).open(1)
        let first = session.appear()
        await data.waitForExpenseCall(1)
        data.release(call: 1)
        await first.value

        let refresh = session.appear()
        await data.waitForExpenseCall(2)
        data.fail(call: 2, with: SessionFailure())
        await refresh.value

        #expect(session.snapshot.expenses.map(\.id) == [41])
        #expect(session.snapshot.errorMessage.isEmpty)
        #expect(session.snapshot.hasLoadedExpenses)
    }

    @Test func returningKeepsActionErrorBesideTheTimeline() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.deleteError = SessionFailure()
        let row = TestExpense.make(id: 42, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [row] }
        let store = GroupSessionStore(dataSource: { data.source() })
        let session = store.open(1)
        await session.appear().value
        #expect(!(await session.delete(row).value))

        #expect(session.snapshot.actionErrorMessage != nil)
        #expect(session.snapshot.expenses.map(\.id) == [42])
        #expect(store.open(1) === session)
        #expect(store.current?.snapshot.actionErrorMessage != nil)
    }

    @Test func returningDuringPendingPollingStartsOneFreshRead() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.summaryForCall = { call in
            GroupBalanceSummary(simplifiedDebts: [], balancesPending: call == 1)
        }
        let gate = BalanceRetryGate()
        let store = GroupSessionStore(dataSource: {
            var source = data.source()
            source.waitForBalanceRetry = { _ in try await gate.wait() }
            return source
        })
        let session = store.open(1)
        let first = session.appear()
        await gate.waitForStart()

        let second = session.appear()
        await second.value
        gate.unblock()
        await first.value

        #expect(data.groupCallCount == 2)
        #expect(data.expenseCallCount == 2)
        #expect(data.summaryCallCount == 2)
        #expect(!session.snapshot.isLoading)
    }

    @Test func switchingGroupsRejectsOldRowsAndDiscardRemovesSession() async {
        let data = ControlledGroupData()
        data.expensesForCall = { call in
            [TestExpense.make(id: call, paidBy: 1, amount: 10, splitAmounts: [1: 10])]
        }
        let store = GroupSessionStore(dataSource: { data.source() })
        let old = store.open(1)
        let oldLoad = old.appear()
        await data.waitForExpenseCall(1)

        let new = store.open(2, seed: group(id: 2))
        #expect(store.current === new)
        #expect(new.snapshot.expenses.isEmpty)
        let newLoad = new.appear()
        await data.waitForExpenseCall(2)
        data.release(call: 2)
        await newLoad.value
        data.release(call: 1)
        await oldLoad.value

        #expect(new.snapshot.expenses.map(\.id) == [2])
        #expect(store.current?.snapshot.expenses.map(\.id) == [2])
        store.discard()
        #expect(store.current == nil)
    }

    @Test func reopeningEarlierGroupShowsCachedRowsWhileRefreshing() async {
        let data = ControlledGroupData()
        data.expensesForCall = { call in
            [TestExpense.make(id: call, paidBy: 1, amount: 10, splitAmounts: [1: 10])]
        }
        let store = GroupSessionStore(dataSource: { data.source() })

        let first = store.open(1)
        let firstLoad = first.appear()
        await data.waitForExpenseCall(1)
        data.release(call: 1)
        await firstLoad.value

        let secondLoad = store.open(2).appear()
        await data.waitForExpenseCall(2)
        data.release(call: 2)
        await secondLoad.value

        let reopened = store.open(1)
        #expect(reopened === first)
        #expect(reopened.snapshot.expenses.map(\.id) == [1])
        #expect(reopened.snapshot.hasLoadedExpenses)

        let refresh = reopened.appear()
        await data.waitForExpenseCall(3)
        #expect(!reopened.snapshot.isLoading)
        #expect(reopened.snapshot.expenses.map(\.id) == [1])
        data.release(call: 3)
        await refresh.value
        #expect(reopened.snapshot.expenses.map(\.id) == [3])
    }

    @Test func signOutAndLeaveDiscardTheCurrentGroup() {
        let appState = AppState(groupSessions: GroupSessionStore(dataSource: {
            ControlledGroupData().source()
        }))
        appState.setSignedInUser(700_122)
        appState.openGroup(1, seed: group(id: 1))
        appState.exitGroup(1)
        #expect(appState.groupSessions.current == nil)
        #expect(appState.currentGroupId == nil)

        appState.openGroup(2, seed: group(id: 2))
        appState.setSignedInUser(nil)
        #expect(appState.groupSessions.current == nil)
        #expect(appState.currentGroupId == nil)
    }

    @Test func addExpenseUsesLoadedSessionWithoutAListReadAndFallsBackWithoutOne() async throws {
        let appState = AppState(groupSessions: GroupSessionStore(dataSource: {
            ControlledGroupData().source()
        }))
        appState.setSignedInUser(700_123)
        let selected = group(id: 1)
        appState.openGroup(1, seed: selected)
        var reads = 0
        let direct = try await appState.resolveAddExpenseDestination {
            reads += 1
            return []
        }
        #expect(direct == .expense(selected))
        #expect(reads == 0)

        appState.leaveUnavailableGroup(message: "Left")
        let fallback = try await appState.resolveAddExpenseDestination {
            reads += 1
            return [selected]
        }
        #expect(fallback == .expense(selected))
        #expect(reads == 1)
    }

    @Test func savedExpenseUpdatesSessionWhileGroupTabIsAway() async {
        let data = ControlledGroupData()
        let row = TestExpense.make(id: 51, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [row] }
        let appState = AppState(groupSessions: GroupSessionStore(dataSource: { data.source() }))
        appState.openGroup(1, seed: group(id: 1))
        appState.selectedTab = .people

        appState.groupSessions.report(.expenseCreated(row), groupId: 1)
        #expect(appState.groupSessions.current?.snapshot.expenses.map(\.id) == [51])
        await data.waitForExpenseCall(1)
        data.release(call: 1)
    }

    @Test func editedExpensePublishesReturnedFieldsBeforeReload() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let original = TestExpense.make(id: 7, paidBy: 1, amount: 10, splitAmounts: [1: 5, 2: 5])
        data.expensesForCall = { _ in [original] }
        let session = GroupSessionStore(dataSource: { data.source() }).open(1)
        await session.appear().value

        data.autoRelease = false
        let edited = Expense(
            id: 7, groupId: 1, paidBy: 2, amount: 25, description: "Train",
            type: .expense, category: .busTrain, splitMode: .custom,
            date: "2026-09-01T12:00:00Z", createdAt: original.createdAt,
            updatedAt: original.updatedAt, paidByUser: TestExpense.user(2),
            splits: [ExpenseSplit(id: 9, expenseId: 7, userId: 1, amount: 25,
                                  percentage: nil, user: TestExpense.user(1))]
        )
        data.expensesForCall = { call in call < 3 ? [original] : [edited] }
        let reload = session.report(.expenseEdited(edited))
        let published = session.snapshot.expenses.first
        #expect(published?.amount == 25)
        #expect(published?.description == "Train")
        #expect(published?.paidBy == 2)
        #expect(published?.splits.map(\.userId) == [1])
        #expect(session.snapshot.balancesPending)
        await data.waitForExpenseCall(2)
        data.release(call: 2)
        await reload.value
        #expect(session.snapshot.expenses.first?.description == "Train")
        await data.waitForExpenseCall(3)
        data.release(call: 3)
        for _ in 0..<1_000 where data.expenseCallCount < 3 { await Task.yield() }
        #expect(session.snapshot.expenses.first?.description == "Train")
    }

    @Test func editedPaymentPublishesAmountAndDateBeforeReload() async throws {
        let data = ControlledGroupData()
        data.autoRelease = true
        let row = TestExpense.make(id: 8, paidBy: 1, amount: 10,
                                   splitAmounts: [1: 10, 2: -10], type: .payment)
        data.expensesForCall = { _ in [row] }
        let session = GroupSessionStore(dataSource: { data.source() }).open(1)
        await session.appear().value

        data.autoRelease = false
        let date = try #require(Expense.parseTimestamp("2026-09-10T12:00:00Z"))
        let edited = Expense(
            id: row.id, groupId: row.groupId, paidBy: row.paidBy, amount: 25,
            description: row.description, type: row.type, category: row.category,
            splitMode: row.splitMode, date: "2026-09-10T12:00:00Z",
            createdAt: row.createdAt, updatedAt: row.updatedAt,
            paidByUser: row.paidByUser, splits: row.splits
        )
        data.expensesForCall = { call in call < 3 ? [row] : [edited] }
        let reload = session.report(.paymentEdited(id: 8, amountCents: 2_500, date: date))
        #expect(session.snapshot.expenses.first?.amount == 25)
        #expect(session.snapshot.expenses.first?.date == "2026-09-10T12:00:00Z")
        await data.waitForExpenseCall(2)
        data.release(call: 2)
        await reload.value
        #expect(session.snapshot.expenses.first?.amount == 25)
        await data.waitForExpenseCall(3)
        data.release(call: 3)
        #expect(session.snapshot.expenses.first?.amount == 25)
    }

    @Test(arguments: [404, 500])
    func deleteRemovesImmediatelyAndEitherKeepsGoneOrRestoresWithError(status: Int) async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.holdDelete = true
        data.deleteError = APIError.httpError(status, message: nil)
        let row = TestExpense.make(id: 7, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [row] }
        let session = GroupSessionStore(dataSource: { data.source() }).open(1)
        await session.appear().value

        let deletion = session.delete(row)
        #expect(session.snapshot.expenses.isEmpty)
        await data.waitForDeleteCall()
        #expect(data.expenseDeleteCount == 1)
        #expect(data.paymentDeleteCount == 0)
        data.releaseDelete()
        let succeeded = await deletion.value
        #expect(succeeded == (status == 404))
        #expect(session.snapshot.expenses.map(\.id) == (status == 404 ? [] : [7]))
        #expect((session.snapshot.actionErrorMessage == nil) == (status == 404))
    }

    @Test func settlementDeleteUsesItsRouteAndPendingRowsCannotDelete() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let row = TestExpense.make(id: 8, paidBy: 1, amount: 10,
                                   splitAmounts: [1: 10, 2: -10], type: .payment)
        data.expensesForCall = { _ in [row] }
        let session = GroupSessionStore(dataSource: { data.source() }).open(1)
        await session.appear().value
        #expect(await session.delete(row).value)
        #expect(data.paymentDeleteCount == 1)
        #expect(data.expenseDeleteCount == 0)

        let pending = session.snapshot.insertPendingPayment(
            groupId: 1, currentUser: TestExpense.members[0],
            peer: TestExpense.members[1], amountCents: 500
        )
        #expect(!(await session.delete(pending).value))
        #expect(data.paymentDeleteCount == 1)
    }

    @Test func aChartsRowAbsentFromTheTimelineStillUsesSessionDelete() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let session = GroupSessionStore(dataSource: { data.source() }).open(1)
        await session.appear().value
        let fetched = TestExpense.make(id: 91, paidBy: 1, amount: 10, splitAmounts: [1: 10])

        #expect(await session.delete(fetched).value)
        #expect(data.expenseDeleteCount == 1)
        #expect(data.paymentDeleteCount == 0)
        #expect(session.snapshot.expenses.isEmpty)
    }

    @Test func cachedSummaryFeedsSheetsWithoutStartingAnotherPoller() async throws {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.summaryForCall = { call in
            GroupBalanceSummary(simplifiedDebts: [], balancesPending: call == 1)
        }
        let gate = BalanceRetryGate()
        let store = GroupSessionStore(dataSource: {
            var source = data.source()
            source.waitForBalanceRetry = { _ in try await gate.wait() }
            return source
        })
        let session = store.open(1)
        await session.appear().value
        await gate.waitForStart()

        _ = try await session.snapshot.summary(groupId: 1)
        _ = try await session.snapshot.summary(groupId: 1, force: !session.snapshot.balancesPending)
        #expect(session.snapshot.balancesPending)
        #expect(data.summaryCallCount == 1)

        gate.unblock()
        for _ in 0..<1_000 where session.snapshot.balancesPending { await Task.yield() }
        #expect(data.summaryCallCount == 2)
        #expect(!session.snapshot.balancesPending)
    }

    @Test func settledCacheGetsASettleUpDebtReadThroughTheSession() async throws {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.summaryForCall = { call in
            GroupBalanceSummary(
                simplifiedDebts: [SimplifiedDebt(
                    from: DebtMember(id: 1, name: "You", avatarUrl: ""),
                    to: DebtMember(id: 2, name: "Bob", avatarUrl: ""),
                    amountCents: call == 1 ? 1_000 : 2_000
                )],
                balancesPending: false
            )
        }
        let session = GroupSessionStore(dataSource: { data.source() }).open(1)
        await session.appear().value
        #expect(data.summaryCallCount == 1)

        let summary = try await session.snapshot.summary(
            groupId: 1, force: !session.snapshot.balancesPending
        )
        #expect(summary.simplifiedDebts.first?.amountCents == 2_000)
        #expect(data.summaryCallCount == 2)
    }

    @Test func pullRefreshPublishesBeforeThePendingWorkerSettles() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.summaryForCall = { call in
            GroupBalanceSummary(simplifiedDebts: [], balancesPending: call < 3)
        }
        let gate = BalanceRetryGate()
        let store = GroupSessionStore(dataSource: {
            var source = data.source()
            source.waitForBalanceRetry = { _ in try await gate.wait() }
            return source
        })
        let session = store.open(1)
        await session.appear().value
        await gate.waitForStart()

        await session.snapshot.refresh(groupId: 1)
        #expect(data.summaryCallCount == 2)
        #expect(session.snapshot.balancesPending)
        gate.unblock()
        for _ in 0..<1_000 where session.snapshot.balancesPending { await Task.yield() }
        #expect(data.summaryCallCount == 3)
        #expect(!session.snapshot.balancesPending)
    }

    @Test func paymentReconcilesWhileBalanceWatcherIsStillWaiting() async throws {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.summaryForCall = { call in
            GroupBalanceSummary(simplifiedDebts: [], balancesPending: call > 1)
        }
        let paymentDate = try #require(Expense.parseTimestamp("2026-03-01T12:00:00Z"))
        let stored = TestExpense.make(id: 42, paidBy: 1, amount: 5,
                                      splitAmounts: [1: 5, 2: -5], type: .payment,
                                      category: .payment, date: "2026-03-01T12:00:00Z")
        data.expensesForCall = { call in call >= 3 ? [stored] : [] }
        let gate = BalanceRetryGate()
        let store = GroupSessionStore(dataSource: {
            var source = data.source()
            source.waitForBalanceRetry = { _ in try await gate.wait() }
            return source
        })
        let session = store.open(1)
        await session.appear().value
        await session.report(.paymentRecorded(
            payee: TestExpense.members[1], amountCents: 500,
            date: paymentDate, currentUserId: 1
        )).value
        await gate.waitForStart()
        await data.waitForExpenseCall(3)
        for _ in 0..<1_000 where !session.snapshot.pendingPaymentIds.isEmpty { await Task.yield() }

        #expect(session.snapshot.expenses.map(\.id) == [42])
        #expect(session.snapshot.balancesPending)
        session.discard()
        gate.unblock()
    }

    private func group(id: Int, name: String? = nil, net: Int = 0) -> Group {
        Group(
            id: id,
            name: name ?? "Group \(id)",
            description: nil,
            netBalanceCents: net,
            createdAt: "2026-01-01T12:00:00Z",
            members: TestExpense.members
        )
    }
}

private struct SessionFailure: Error {}

@MainActor
private final class BalanceRetryGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var retryWaiter: CheckedContinuation<Void, Never>?

    func wait() async throws {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { continuation in retryWaiter = continuation }
        try Task.checkCancellation()
    }

    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { continuation in startWaiter = continuation }
    }

    func unblock() {
        retryWaiter?.resume()
        retryWaiter = nil
    }
}
