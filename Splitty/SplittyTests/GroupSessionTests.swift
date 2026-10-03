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

        #expect(session.group?.name == "From list")
        #expect(session.group?.netBalanceCents == 725)
        #expect(session.members.count == seed.members.count)
        #expect(!session.hasLoadedExpenses)
        #expect(!session.isLoading)

        let load = session.appear()
        await data.waitForExpenseCall(1)
        #expect(!session.hasLoadedExpenses)
        #expect(!session.isLoading)
        data.release(call: 1)
        await load.value
        #expect(session.hasLoadedExpenses)
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

        session.report(.paymentRecorded(payee: TestExpense.members[1], amountCents: 500,
                                        date: Date(), currentUserId: 1))
        let payment = try #require(session.expenses.first)
        #expect(payment.id < 0)
        #expect(session.group?.netBalanceCents == 0)
        #expect(session.balancesPending)

        let reopened = store.open(1, seed: group(id: 1, name: "Stale list", net: -500))
        #expect(reopened === session)
        #expect(reopened.expenses.map(\.id) == [payment.id])
        #expect(reopened.group?.netBalanceCents == 0)

        let refresh = reopened.appear()
        await data.waitForExpenseCall(2)
        #expect(data.expenseCallCount == 2)
        #expect(data.groupCallCount == 2)
        #expect(data.summaryCallCount == 2)
        #expect(!reopened.isLoading)
        #expect(reopened.expenses.map(\.id) == [payment.id])
        data.fail(call: 2, with: CancellationError())
        await refresh.value
        #expect(reopened.expenses.map(\.id) == [payment.id])
        #expect(reopened.group?.netBalanceCents == 0)
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

        #expect(session.expenses.map(\.id) == [41])
        #expect(session.errorMessage.isEmpty)
        #expect(session.hasLoadedExpenses)
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
        #expect((await session.delete(row).value) == .failed(SessionFailure().displayMessage))

        #expect(session.actionErrorMessage != nil)
        #expect(session.expenses.map(\.id) == [42])
        #expect(store.open(1) === session)
        #expect(store.current?.actionErrorMessage != nil)
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
        #expect(!session.isLoading)
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
        #expect(new.expenses.isEmpty)
        let newLoad = new.appear()
        await data.waitForExpenseCall(2)
        data.release(call: 2)
        await newLoad.value
        data.release(call: 1)
        await oldLoad.value

        #expect(new.expenses.map(\.id) == [2])
        #expect(store.current?.expenses.map(\.id) == [2])
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
        #expect(reopened.expenses.map(\.id) == [1])
        #expect(reopened.hasLoadedExpenses)

        let refresh = reopened.appear()
        await data.waitForExpenseCall(3)
        #expect(!reopened.isLoading)
        #expect(reopened.expenses.map(\.id) == [1])
        data.release(call: 3)
        await refresh.value
        #expect(reopened.expenses.map(\.id) == [3])
    }

    @Test func signOutAndLeaveDiscardTheCurrentGroup() {
        let appState = AppState(groupSessions: GroupSessionStore(defaults: isolatedDefaults(), dataSource: {
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
        let appState = AppState(groupSessions: GroupSessionStore(defaults: isolatedDefaults(), dataSource: {
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
        let appState = AppState(groupSessions: GroupSessionStore(defaults: isolatedDefaults(), dataSource: { data.source() }))
        appState.openGroup(1, seed: group(id: 1))
        appState.selectedTab = .people

        appState.groupSessions.report(.expenseCreated(row), groupId: 1)
        #expect(appState.groupSessions.current?.expenses.map(\.id) == [51])
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
        let published = session.expenses.first
        #expect(published?.amount == 25)
        #expect(published?.description == "Train")
        #expect(published?.paidBy == 2)
        #expect(published?.splits.map(\.userId) == [1])
        #expect(session.balancesPending)
        await data.waitForExpenseCall(2)
        data.release(call: 2)
        await reload.value
        #expect(session.expenses.first?.description == "Train")
        await data.waitForExpenseCall(3)
        data.release(call: 3)
        for _ in 0..<1_000 where data.expenseCallCount < 3 { await Task.yield() }
        #expect(session.expenses.first?.description == "Train")
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
        #expect(session.expenses.first?.amount == 25)
        #expect(session.expenses.first?.date == "2026-09-10T12:00:00Z")
        await data.waitForExpenseCall(2)
        data.release(call: 2)
        await reload.value
        #expect(session.expenses.first?.amount == 25)
        await data.waitForExpenseCall(3)
        data.release(call: 3)
        #expect(session.expenses.first?.amount == 25)
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
        #expect(session.expenses.isEmpty)
        await data.waitForDeleteCall()
        #expect(data.expenseDeleteCount == 1)
        #expect(data.paymentDeleteCount == 0)
        data.releaseDelete()
        let succeeded = await deletion.value
        #expect(succeeded == (status == 404 ? .alreadyGone : .failed(APIError.httpError(500, message: nil).displayMessage)))
        #expect(session.expenses.map(\.id) == (status == 404 ? [] : [7]))
        #expect((session.actionErrorMessage == nil) == (status == 404))
    }

    @Test func settlementDeleteUsesItsRouteAndPendingRowsCannotDelete() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let row = TestExpense.make(id: 8, paidBy: 1, amount: 10,
                                   splitAmounts: [1: 10, 2: -10], type: .payment)
        data.expensesForCall = { _ in [row] }
        let session = GroupSessionStore(dataSource: { data.source() }).open(1)
        await session.appear().value
        #expect(await session.delete(row).value == .deleted)
        #expect(data.paymentDeleteCount == 1)
        #expect(data.expenseDeleteCount == 0)

        session.report(.paymentRecorded(payee: TestExpense.members[1], amountCents: 500,
                                        date: Date(), currentUserId: 1))
        guard let pending = session.expenses.first(where: session.isPendingPayment) else {
            Issue.record("Expected a pending payment")
            return
        }
        #expect(await session.delete(pending).value == .failed(L10n.Errors.generic))
        #expect(data.paymentDeleteCount == 1)
    }

    @Test func aChartsRowAbsentFromTheTimelineStillUsesSessionDelete() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let session = GroupSessionStore(dataSource: { data.source() }).open(1)
        await session.appear().value
        let fetched = TestExpense.make(id: 91, paidBy: 1, amount: 10, splitAmounts: [1: 10])

        #expect(await session.delete(fetched).value == .deleted)
        #expect(data.expenseDeleteCount == 1)
        #expect(data.paymentDeleteCount == 0)
        #expect(session.expenses.isEmpty)
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

        _ = try await session.readSummary()
        _ = try await session.summaryForSettleUp()
        #expect(session.balancesPending)
        #expect(data.summaryCallCount == 1)

        gate.unblock()
        for _ in 0..<1_000 where session.balancesPending { await Task.yield() }
        #expect(data.summaryCallCount == 2)
        #expect(!session.balancesPending)
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

        let summary = try await session.summaryForSettleUp()
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

        await session.refresh()
        #expect(data.summaryCallCount == 2)
        #expect(session.balancesPending)
        gate.unblock()
        for _ in 0..<1_000 where session.balancesPending { await Task.yield() }
        #expect(data.summaryCallCount == 3)
        #expect(!session.balancesPending)
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
        for _ in 0..<1_000 where session.expenses.contains(where: session.isPendingPayment) { await Task.yield() }

        #expect(session.expenses.map(\.id) == [42])
        #expect(session.balancesPending)
        session.discard()
        gate.unblock()
    }

    @Test func aWriteUpdatesACachedGroupThatIsNotCurrent() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let store = GroupSessionStore(dataSource: { data.source() })
        let cached = store.open(1, seed: group(id: 1))
        let current = store.open(2, seed: group(id: 2))
        let row = TestExpense.make(id: 71, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [row] }

        store.report(.expenseCreated(row), groupId: 1)

        #expect(cached.expenses.map(\.id) == [71])
        #expect(cached.balancesPending)
        #expect(current.expenses.isEmpty)
        #expect(store.current === current)
        store.discard()
    }

    @Test func settleUpResultRecordsANewPendingPayment() throws {
        let data = ControlledGroupData()
        let session = GroupSessionStore(dataSource: { data.source() }).open(1, seed: group(id: 1, net: -5_000))
        let date = try #require(Expense.parseTimestamp("2026-03-01T12:00:00Z"))
        session.record(SettleUpResult(peer: TestExpense.members[1], amountCents: 2_350,
                                     date: date, settlementId: nil), currentUserId: 1)

        let payment = try #require(session.expenses.first)
        #expect(payment.id < 0)
        #expect(payment.groupId == 1)
        #expect(payment.amount == 23.50)
        #expect(payment.effectiveDate == date)
        #expect(session.groupedExpenses.first?.date == Calendar.current.startOfDay(for: date))
        #expect(session.groupedExpenses.first?.expenses.map(\.id) == [payment.id])
        #expect(session.isPendingPayment(payment))
        #expect(session.netBalanceCents == -2_650)
        #expect(session.balancesPending)
        session.discard()
    }

    @Test func settleUpResultEditsTheExistingPayment() async throws {
        let data = ControlledGroupData()
        data.autoRelease = true
        let original = TestExpense.make(id: 8, paidBy: 1, amount: 10,
                                        splitAmounts: [1: 10, 2: -10], type: .payment)
        data.expensesForCall = { _ in [original] }
        let session = GroupSession(groupId: 1, dataSource: data.source())
        await session.appear().value
        data.autoRelease = false
        let date = try #require(Expense.parseTimestamp("2026-09-10T12:00:00Z"))

        session.record(SettleUpResult(peer: TestExpense.members[1], amountCents: 2_500,
                                     date: date, settlementId: 8), currentUserId: 1)
        #expect(session.expenses.map(\.id) == [8])
        #expect(session.expenses.first?.amount == 25)
        #expect(session.expenses.first?.effectiveDate == date)
        #expect(session.balancesPending)
        session.discard()
    }

    @Test func aWriteWithoutACachedSessionIsDroppedAndFirstOpenReadsFresh() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let store = GroupSessionStore(dataSource: { data.source() })
        let current = store.open(2, seed: group(id: 2))
        let row = TestExpense.make(id: 72, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [row] }
        store.report(.expenseCreated(row), groupId: 1)
        #expect(store.session(for: 1) == nil)
        #expect(store.liveBalance(for: 1) == nil)
        #expect(current.expenses.isEmpty)
        #expect(data.expenseCallCount == 0)

        let firstOpen = store.open(1)
        await firstOpen.appear().value
        #expect(firstOpen.expenses.map(\.id) == [72])
        #expect(data.expenseCallCount == 1)
        store.discard()
    }

    @Test func cardsUseTheSessionsAdjustedPendingNetAndThenItsSettledNet() async throws {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.groupForCall = { call in self.group(id: 1, net: call < 3 ? -5_000 : -2_400) }
        data.summaryForCall = { call in
            GroupBalanceSummary(simplifiedDebts: [], balancesPending: call == 2)
        }
        let gate = BalanceRetryGate()
        let store = GroupSessionStore(dataSource: {
            var source = data.source()
            source.waitForBalanceRetry = { _ in try await gate.wait() }
            return source
        })
        let session = store.open(1, seed: group(id: 1, net: -5_000))
        await session.appear().value
        let date = try #require(Expense.parseTimestamp("2026-03-01T12:00:00Z"))
        let stored = TestExpense.make(id: 73, paidBy: 1, amount: 23.50,
                                      splitAmounts: [1: 23.50, 2: -23.50], type: .payment,
                                      category: .payment, date: "2026-03-01T12:00:00Z")
        data.expensesForCall = { _ in [stored] }
        let refresh = session.record(SettleUpResult(peer: TestExpense.members[1], amountCents: 2_350,
                                                    date: date, settlementId: nil), currentUserId: 1)
        #expect(store.liveBalance(for: 1) == GroupLiveBalance(netBalanceCents: -2_650, balancesPending: true))
        #expect(store.liveBalance(for: 99) == nil)
        await refresh.value
        await gate.waitForStart()
        // The current group can change while the previous group's watcher finishes.
        store.open(2, seed: group(id: 2))
        #expect(store.liveBalance(for: 1)?.netBalanceCents == session.netBalanceCents)
        #expect(store.liveBalance(for: 1)?.balancesPending == true)

        gate.unblock()
        for _ in 0..<1_000 where session.balancesPending { await Task.yield() }
        #expect(store.liveBalance(for: 1) == GroupLiveBalance(netBalanceCents: -2_400, balancesPending: false))
        #expect(store.liveBalance(for: 1)?.netBalanceCents == session.netBalanceCents)
        store.discard()
    }

    @Test func currentGroupPersistsPerUserAndClearsOnLeave() async {
        let defaults = isolatedDefaults()
        let data = ControlledGroupData()
        data.autoRelease = true
        let store = GroupSessionStore(defaults: defaults, dataSource: { data.source() })
        store.setSignedInUser(1)
        store.open(11, seed: group(id: 11))
        store.open(12, seed: group(id: 12))
        store.setSignedInUser(nil)
        #expect(store.currentGroupId == nil)
        #expect(store.session(for: 11) == nil)
        #expect(store.session(for: 12) == nil)

        store.setSignedInUser(2)
        #expect(store.currentGroupId == nil)
        store.open(22, seed: group(id: 22))
        store.setSignedInUser(nil)

        let relaunched = GroupSessionStore(defaults: defaults, dataSource: { data.source() })
        relaunched.setSignedInUser(1)
        let restored = relaunched.current
        #expect(relaunched.currentGroupId == 12)
        await restored?.appear().value
        #expect(restored?.group?.id == 12)
        relaunched.remove(12)
        #expect(relaunched.currentGroupId == nil)
        #expect(relaunched.session(for: 12) == nil)
        relaunched.setSignedInUser(nil)
        relaunched.setSignedInUser(1)
        #expect(relaunched.currentGroupId == nil)
        relaunched.setSignedInUser(2)
        #expect(relaunched.currentGroupId == 22)
        relaunched.discard()
    }

    @Test func deleteRoutesToACachedNonCurrentSession() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let row = TestExpense.make(id: 74, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [row] }
        let store = GroupSessionStore(dataSource: { data.source() })
        let cached = store.open(1)
        await cached.appear().value
        let current = store.open(2, seed: group(id: 2))
        #expect(await store.delete(row, groupId: 1).value == .deleted)
        #expect(cached.expenses.isEmpty)
        #expect(store.current === current)
        #expect(await store.delete(row, groupId: 99).value == .failed(L10n.Errors.generic))
        store.discard()
    }

    @Test func eightRecentGroupsKeepTheirCacheAndTheNinthEvictsTheOldest() {
        let store = GroupSessionStore(dataSource: { ControlledGroupData().source() })
        let oldest = store.open(1, seed: group(id: 1))
        for id in 2...8 { store.open(id, seed: group(id: id)) }
        #expect(store.session(for: 1) === oldest)
        let mostRecent = store.open(1)
        #expect(mostRecent === oldest)
        store.open(9, seed: group(id: 9))
        #expect(store.session(for: 2) == nil)
        #expect(store.session(for: 1) === oldest)
        #expect(store.currentGroupId == 9)
        store.discard()
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "GroupSessionTests.\(UUID().uuidString)")!
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
