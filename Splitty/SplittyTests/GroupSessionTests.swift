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
        await session.snapshot.delete(row, groupId: 1)

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

        appState.recordSavedExpense(row, groupId: 1)
        #expect(appState.groupSessions.current?.snapshot.expenses.map(\.id) == [51])
        await data.waitForExpenseCall(1)
        data.release(call: 1)
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
