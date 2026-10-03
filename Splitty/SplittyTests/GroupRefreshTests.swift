//
//  GroupRefreshTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

private struct ControlledGroupFailure: Error {}

@MainActor
struct GroupRefreshTests {

    @Test func aMoneyWriteRefreshesOnceAndOnlyOnce() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let saved = TestExpense.make(id: 9, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [saved] }
        let session = GroupSession(groupId: 1, dataSource: data.source())
        let task = session.report(.expenseCreated(saved))
        #expect(session.expenses.map(\.id) == [9])
        await task.value

        #expect(session.expenses.map(\.id) == [9])
        #expect(data.expenseCallCount == 1)

        // Dismissal has no write event and does not start another load.
        #expect(data.expenseCallCount == 1)
    }

    // Every request of the snapshot still goes out on a successful money write.
    @Test func aRefreshStillRequestsTheGroupExpensesAndBalanceSummary() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let session = GroupSession(groupId: 1, dataSource: data.source())

        await session.refresh()

        #expect(data.groupCallCount == 1)
        #expect(data.expenseCallCount == 1)
        #expect(data.summaryCallCount == 1)
        #expect(session.group?.id == 1)
    }

    @Test func aPendingBalanceRefreshesUntilTheWorkerSettles() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.groupForCall = { call in
            GroupDetail(
                id: 1,
                name: "Group 1",
                description: nil,
                netBalanceCents: call == 1 ? 1_000 : 2_500,
                createdAt: "2026-01-01T12:00:00Z",
                members: TestExpense.members
            )
        }
        data.summaryForCall = { call in
            GroupBalanceSummary(simplifiedDebts: [], balancesPending: call < 10)
        }
        data.groupFailureCalls = [2]
        let session = GroupSession(groupId: 1, dataSource: data.source())

        await session.refresh()
        for _ in 0..<1_000 where session.balancesPending { await Task.yield() }

        #expect(data.summaryCallCount == 10)
        #expect(data.balanceRetryCount == 10)
        #expect(data.groupCallCount == 3)
        #expect(session.group?.netBalanceCents == 2_500)
        #expect(!session.balancesPending)
    }

    @Test func aRefreshReplacesPreviouslyLoadedRowsWithTheServersRows() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let session = GroupSession(groupId: 1, dataSource: data.source())
        data.expensesForCall = { call in
            call == 1 ? [TestExpense.make(id: 9, paidBy: 1, amount: 10, splitAmounts: [1: 10])] : []
        }
        await session.appear().value

        await session.refresh()

        #expect(session.expenses.isEmpty)
        #expect(session.groupedExpenses.isEmpty)
    }

    @Test func anEditedPaymentRefreshesWithoutAddingAnotherRow() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let session = GroupSession(groupId: 1, dataSource: data.source())
        await session.report(.paymentEdited(id: 18, amountCents: 500, date: Date())).value

        #expect(session.expenses.isEmpty)
        #expect(data.expenseCallCount == 1)
    }

    @Test func aPaymentStaysPendingUntilTheStoredRowArrives() async throws {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.cancelBalanceRetryCalls = [2]
        data.summaryForCall = { call in
            GroupBalanceSummary(simplifiedDebts: [], balancesPending: call == 2)
        }
        let paymentDate = try #require(Expense.parseTimestamp("2026-03-01T12:00:00Z"))
        let stored = TestExpense.make(
            id: 42,
            paidBy: 1,
            amount: 5,
            splitAmounts: [1: 5, 2: -5],
            type: .payment,
            category: .payment,
            date: "2026-03-01T12:00:00Z"
        )
        data.expensesForCall = { call in call < 5 ? [] : [stored] }
        let session = GroupSession(groupId: 1, dataSource: data.source())

        await session.refresh()
        await session.report(.paymentRecorded(payee: TestExpense.members[1], amountCents: 500, date: paymentDate, currentUserId: 1)).value
        let pending = try #require(session.expenses.first)
        #expect(pending.id < 0)
        #expect(session.isPendingPayment(pending))
        #expect(!session.balancesPending)

        await session.refresh()
        await data.waitForExpenseCall(5)
        for _ in 0..<1_000 where session.expenses.contains(where: session.isPendingPayment) { await Task.yield() }
        #expect(session.expenses.map(\.id) == [42])
        #expect(!session.expenses.contains(where: session.isPendingPayment))
    }

    @Test func workerSettlementReplacesTheTemporaryPaymentAndNetBalance() async throws {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.summaryForCall = { call in
            GroupBalanceSummary(simplifiedDebts: [], balancesPending: call == 2)
        }
        data.groupForCall = { call in
            GroupDetail(
                id: 1,
                name: "Group 1",
                description: nil,
                netBalanceCents: call < 3 ? -500 : 0,
                createdAt: "2026-01-01T12:00:00Z",
                members: TestExpense.members
            )
        }
        let paymentDate = try #require(Expense.parseTimestamp("2026-03-01T12:00:00Z"))
        let stored = TestExpense.make(
            id: 42,
            paidBy: 1,
            amount: 5,
            splitAmounts: [1: 5, 2: -5],
            type: .payment,
            category: .payment,
            date: "2026-03-01T12:00:00Z"
        )
        data.expensesForCall = { call in call < 4 ? [] : [stored] }
        let session = GroupSession(groupId: 1, dataSource: data.source())
        await session.refresh()

        await session.report(.paymentRecorded(payee: TestExpense.members[1], amountCents: 500, date: paymentDate, currentUserId: 1)).value

        #expect(session.expenses.map(\.id) == [42])
        #expect(!session.expenses.contains(where: session.isPendingPayment))
        #expect(session.group?.netBalanceCents == 0)
        #expect(!session.balancesPending)
        #expect(data.expenseCallCount == 4)
    }

    @Test(arguments: [0, 200])
    func aSettledSummaryCannotPublishAnOlderGroupBalance(finalNetCents: Int) async throws {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.groupForCall = { call in
            GroupDetail(
                id: 1,
                name: "Group 1",
                description: nil,
                netBalanceCents: call < 3 ? -500 : finalNetCents,
                createdAt: "2026-01-01T12:00:00Z",
                members: TestExpense.members
            )
        }
        let paymentDate = try #require(Expense.parseTimestamp("2026-03-01T12:00:00Z"))
        let stored = TestExpense.make(
            id: 42,
            paidBy: 1,
            amount: 5,
            splitAmounts: [1: 5, 2: -5],
            type: .payment,
            category: .payment,
            date: "2026-03-01T12:00:00Z"
        )
        data.expensesForCall = { call in call == 1 ? [] : [stored] }
        let session = GroupSession(groupId: 1, dataSource: data.source())
        await session.refresh()

        await session.report(.paymentRecorded(payee: TestExpense.members[1], amountCents: 500, date: paymentDate, currentUserId: 1)).value

        #expect(data.groupCallCount == 3)
        #expect(session.group?.netBalanceCents == finalNetCents)
        #expect(!session.balancesPending)
    }

    @Test func anExpenseWriteAlsoGetsAGroupReadAfterTheSummary() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.groupForCall = { call in
            GroupDetail(
                id: 1,
                name: "Group 1",
                description: nil,
                netBalanceCents: call < 3 ? 0 : 400,
                createdAt: "2026-01-01T12:00:00Z",
                members: TestExpense.members
            )
        }
        let row = TestExpense.make(id: 9, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [row] }
        let session = GroupSession(groupId: 1, dataSource: data.source())
        await session.refresh()

        await session.report(.expenseCreated(row)).value

        #expect(data.groupCallCount == 3)
        #expect(session.group?.netBalanceCents == 400)
        #expect(!session.balancesPending)
    }

    @Test func aSummaryFailurePreservesThePendingHeaderAndTimeline() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.cancelBalanceRetry = true
        data.summaryFailureCalls = [2]
        data.summaryForCall = { _ in
            GroupBalanceSummary(simplifiedDebts: [], balancesPending: true)
        }
        let row = TestExpense.make(id: 4, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [row] }
        let session = GroupSession(groupId: 1, dataSource: data.source())

        await session.refresh()
        #expect(session.balancesPending)
        await session.refresh()

        #expect(session.expenses.map(\.id) == [4])
        #expect(session.balancesPending)
    }

    // Balances follow the timeline's rule: a background read cannot blank what is on screen.
    @Test func aFailedBackgroundSummaryReadKeepsBalancesOnScreen() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.summaryFailureCalls = [2]
        let session = GroupSession(groupId: 1, dataSource: data.source())

        await session.refresh()
        #expect(session.balanceState(currentUserId: 1) == .settled)
        await session.refresh()

        #expect(session.balanceState(currentUserId: 1) == .settled)
    }

    @Test func aFailedDeleteKeepsTheTimelineAndShowsAnActionError() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.deleteError = APIError.httpError(500, message: nil)
        let session = GroupSession(groupId: 1, dataSource: data.source())
        let row = TestExpense.make(id: 4, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [row] }
        await session.appear().value

        #expect(await session.delete(row).value == .failed(APIError.httpError(500, message: nil).displayMessage))

        #expect(session.expenses.map(\.id) == [4])
        #expect(session.actionErrorMessage != nil)
        #expect(data.expenseCallCount == 1)
    }

    @Test func aSuccessfulDeleteReturnsAfterTheRouteAndRefreshesInBackground() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.groupForCall = { call in
            GroupDetail(
                id: 1,
                name: "Group 1",
                description: nil,
                netBalanceCents: call == 1 ? 0 : -300,
                createdAt: "2026-01-01T12:00:00Z",
                members: TestExpense.members
            )
        }
        let session = GroupSession(groupId: 1, dataSource: data.source())
        let row = TestExpense.make(id: 4, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        data.expensesForCall = { _ in [row] }
        await session.appear().value

        #expect(await session.delete(row).value == .deleted)

        #expect(session.expenses.isEmpty)
        #expect(data.expenseDeleteCount == 1)
    }

    // Rapid refreshes can finish out of order. Whichever started last is the snapshot the
    // screen keeps, whatever order the responses arrive in.
    @Test func anOlderRefreshCannotOverwriteANewerSnapshot() async {
        let data = ControlledGroupData()
        data.expensesForCall = { call in [TestExpense.make(id: call, paidBy: 1, amount: 10, splitAmounts: [1: 10])] }
        let session = GroupSession(groupId: 1, dataSource: data.source())

        let first = Task { await session.refresh() }
        await data.waitForExpenseCall(1)
        let second = Task { await session.refresh() }
        await data.waitForExpenseCall(2)

        // The newer request answers first, then the older one arrives late.
        data.release(call: 2)
        await second.value
        data.release(call: 1)
        await first.value

        #expect(session.expenses.map(\.id) == [2])
        #expect(session.groupedExpenses.flatMap { $0.expenses }.map(\.id) == [2])
    }

    // Cancellation is control flow: it leaves the rows already on screen alone rather
    // than blanking them or writing an error over them.
    @Test func aCanceledRefreshLeavesTheRowsOnScreenAlone() async {
        let data = ControlledGroupData()
        data.expensesForCall = { call in [TestExpense.make(id: call, paidBy: 1, amount: 10, splitAmounts: [1: 10])] }
        let session = GroupSession(groupId: 1, dataSource: data.source())

        let loaded = Task { await session.refresh() }
        await data.waitForExpenseCall(1)
        data.release(call: 1)
        await loaded.value
        #expect(session.expenses.map(\.id) == [1])

        let canceled = Task { await session.refresh() }
        await data.waitForExpenseCall(2)
        data.fail(call: 2, with: CancellationError())
        await canceled.value

        #expect(session.expenses.map(\.id) == [1])
        #expect(session.errorMessage.isEmpty)
    }

    // A superseded refresh is control flow, not a failure the user should read about.
    @Test func aSupersededRefreshLeavesTheScreenAloneWhenItFails() async {
        let data = ControlledGroupData()
        data.summaryFailureCalls = [1]
        data.expensesForCall = { call in [TestExpense.make(id: call, paidBy: 1, amount: 10, splitAmounts: [1: 10])] }
        let session = GroupSession(groupId: 1, dataSource: data.source())

        let first = Task { await session.refresh() }
        await data.waitForExpenseCall(1)
        let second = Task { await session.refresh() }
        await data.waitForExpenseCall(2)

        data.release(call: 2)
        await second.value
        data.fail(call: 1, with: APIError.httpError(500, message: nil))
        await first.value

        #expect(session.expenses.map(\.id) == [2])
        #expect(session.errorMessage.isEmpty)
        #expect(session.balanceState(currentUserId: 1) == .settled)
    }
}

// MARK: - Fixtures

/// A data source whose expense request can be held open, so a test can decide the order
/// two overlapping refreshes come back in.
@MainActor
final class ControlledGroupData {
    /// How the nth held expense request ends.
    enum Outcome {
        case rows([Expense])
        case failure(Error)
    }

    /// Rows the nth expense request answers with, unless a test fails it instead.
    var expensesForCall: (Int) -> [Expense] = { _ in [] }
    var groupForCall: ((Int) -> GroupDetail)?
    var groupFailureCalls: Set<Int> = []
    var summaryFailureCalls: Set<Int> = []
    var deleteError: Error?
    var holdDelete = false
    var cancelBalanceRetry = false
    var cancelBalanceRetryCalls: Set<Int> = []
    var summaryForCall: (Int) -> GroupBalanceSummary = { _ in
        GroupBalanceSummary(simplifiedDebts: [], balancesPending: false)
    }

    /// When true, requests answer immediately instead of waiting for `release(call:)`.
    var autoRelease = false

    private(set) var groupCallCount = 0
    private(set) var expenseCallCount = 0
    private(set) var summaryCallCount = 0
    private(set) var balanceRetryCount = 0
    private(set) var expenseDeleteCount = 0
    private(set) var paymentDeleteCount = 0

    private var waitingForOutcome: [Int: CheckedContinuation<Outcome, Never>] = [:]
    private var outcomes: [Int: Outcome] = [:]
    private var waitingForCall: [Int: CheckedContinuation<Void, Never>] = [:]
    private var waitingForDelete: CheckedContinuation<Void, Never>?
    private var deleteCallWaiter: CheckedContinuation<Void, Never>?

    func source() -> GroupDataSource {
        GroupDataSource(
            group: { [self] groupId in try await noteGroupCall(id: groupId) },
            expenses: { [self] _ in
                let call = await noteExpenseCall()
                switch await outcome(of: call) {
                case .rows(let rows): return rows
                case .failure(let error): throw error
                }
            },
            summary: { [self] _ in try await noteSummaryCall() },
            waitForBalanceRetry: { [self] _ in try await noteBalanceRetry() },
            deleteExpense: { [self] _, _ in try await noteDelete(payment: false) },
            deletePayment: { [self] _, _ in try await noteDelete(payment: true) }
        )
    }

    func release(call: Int) {
        resolve(call: call, with: .rows(expensesForCall(call)))
    }

    func fail(call: Int, with error: Error) {
        resolve(call: call, with: .failure(error))
    }

    /// Suspends until the nth expense request has been issued, so a test can interleave
    /// two refreshes without sleeping on a timer.
    func waitForExpenseCall(_ call: Int) async {
        guard expenseCallCount < call else { return }
        await withCheckedContinuation { continuation in
            waitingForCall[call] = continuation
        }
    }

    func waitForDeleteCall() async {
        if expenseDeleteCount + paymentDeleteCount > 0 { return }
        await withCheckedContinuation { deleteCallWaiter = $0 }
    }

    func releaseDelete() {
        waitingForDelete?.resume()
        waitingForDelete = nil
    }

    private func noteDelete(payment: Bool) async throws {
        if payment { paymentDeleteCount += 1 }
        else { expenseDeleteCount += 1 }
        deleteCallWaiter?.resume()
        deleteCallWaiter = nil
        if holdDelete {
            await withCheckedContinuation { waitingForDelete = $0 }
        }
        if let deleteError { throw deleteError }
    }

    private func resolve(call: Int, with outcome: Outcome) {
        if let continuation = waitingForOutcome.removeValue(forKey: call) {
            continuation.resume(returning: outcome)
        } else {
            outcomes[call] = outcome
        }
    }

    private func outcome(of call: Int) async -> Outcome {
        if autoRelease { return .rows(expensesForCall(call)) }
        if let outcome = outcomes.removeValue(forKey: call) { return outcome }
        return await withCheckedContinuation { continuation in
            waitingForOutcome[call] = continuation
        }
    }

    private func noteGroupCall(id: Int) throws -> GroupDetail {
        groupCallCount += 1
        if groupFailureCalls.contains(groupCallCount) { throw ControlledGroupFailure() }
        if let groupForCall { return groupForCall(groupCallCount) }
        return GroupDetail(
            id: id,
            name: "Group \(id)",
            description: nil,
            netBalanceCents: 0,
            createdAt: "2026-01-01T12:00:00Z",
            members: TestExpense.members
        )
    }

    private func noteExpenseCall() -> Int {
        expenseCallCount += 1
        waitingForCall.removeValue(forKey: expenseCallCount)?.resume()
        return expenseCallCount
    }

    private func noteSummaryCall() throws -> GroupBalanceSummary {
        summaryCallCount += 1
        if summaryFailureCalls.contains(summaryCallCount) { throw ControlledGroupFailure() }
        return summaryForCall(summaryCallCount)
    }

    private func noteBalanceRetry() throws {
        balanceRetryCount += 1
        if cancelBalanceRetry || cancelBalanceRetryCalls.contains(balanceRetryCount) {
            throw CancellationError()
        }
    }
}
