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

    // A canceled sheet wrote nothing, so its dismissal owes the server no questions.
    @Test func aCanceledSheetDoesNotRefresh() {
        let data = ControlledGroupData()
        let viewModel = GroupViewModel(dataSource: data.source())

        #expect(viewModel.refreshAfterSheetDismissal(groupId: 1) == nil)
        #expect(data.expenseCallCount == 0)
    }

    @Test func aSavedSheetRefreshesOnceAndOnlyOnce() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.expensesForCall = { call in [TestExpense.make(id: call, paidBy: 1, amount: 10, splitAmounts: [1: 10])] }
        let viewModel = GroupViewModel(dataSource: data.source())

        viewModel.noteSheetWrite()
        let task = viewModel.refreshAfterSheetDismissal(groupId: 1)
        #expect(task != nil)
        await task?.value

        #expect(viewModel.expenses.map(\.id) == [1])
        #expect(data.expenseCallCount == 1)

        // That write has been answered. Dismissing again without a new save must not
        // refetch a second time.
        #expect(viewModel.refreshAfterSheetDismissal(groupId: 1) == nil)
        #expect(data.expenseCallCount == 1)
    }

    // Every request of the snapshot still goes out on a successful money write.
    @Test func aRefreshStillRequestsTheGroupExpensesAndBalanceSummary() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let viewModel = GroupViewModel(dataSource: data.source())

        await viewModel.refresh(groupId: 1)

        #expect(data.groupCallCount == 1)
        #expect(data.expenseCallCount == 1)
        #expect(data.summaryCallCount == 1)
        #expect(viewModel.group?.id == 1)
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
            GroupBalanceSummary(balances: [], balancesPending: call < 10)
        }
        data.groupFailureCalls = [2]
        let viewModel = GroupViewModel(dataSource: data.source())

        await viewModel.refresh(groupId: 1)

        #expect(data.summaryCallCount == 10)
        #expect(data.balanceRetryCount == 10)
        #expect(data.groupCallCount == 3)
        #expect(viewModel.group?.netBalanceCents == 2_500)
        #expect(!viewModel.balancesPending)
    }

    @Test func aRefreshReplacesLocallyInsertedRowsWithTheServersRows() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        let viewModel = GroupViewModel(dataSource: data.source())
        viewModel.insert(TestExpense.make(id: 9, paidBy: 1, amount: 10, splitAmounts: [1: 10]))

        await viewModel.refresh(groupId: 1)

        #expect(viewModel.expenses.isEmpty)
        #expect(viewModel.groupedExpenses.isEmpty)
    }

    // Rapid refreshes can finish out of order. Whichever started last is the snapshot the
    // screen keeps, whatever order the responses arrive in.
    @Test func anOlderRefreshCannotOverwriteANewerSnapshot() async {
        let data = ControlledGroupData()
        data.expensesForCall = { call in [TestExpense.make(id: call, paidBy: 1, amount: 10, splitAmounts: [1: 10])] }
        let viewModel = GroupViewModel(dataSource: data.source())

        let first = viewModel.beginRefresh(groupId: 1)
        await data.waitForExpenseCall(1)
        let second = viewModel.beginRefresh(groupId: 1)
        await data.waitForExpenseCall(2)

        // The newer request answers first, then the older one arrives late.
        data.release(call: 2)
        await second.value
        data.release(call: 1)
        await first.value

        #expect(viewModel.expenses.map(\.id) == [2])
        #expect(viewModel.groupedExpenses.flatMap { $0.expenses }.map(\.id) == [2])
    }

    // Cancellation is control flow: it leaves the rows already on screen alone rather
    // than blanking them or writing an error over them.
    @Test func aCanceledRefreshLeavesTheRowsOnScreenAlone() async {
        let data = ControlledGroupData()
        data.expensesForCall = { call in [TestExpense.make(id: call, paidBy: 1, amount: 10, splitAmounts: [1: 10])] }
        let viewModel = GroupViewModel(dataSource: data.source())

        let loaded = viewModel.beginRefresh(groupId: 1)
        await data.waitForExpenseCall(1)
        data.release(call: 1)
        await loaded.value
        #expect(viewModel.expenses.map(\.id) == [1])

        let canceled = viewModel.beginRefresh(groupId: 1)
        await data.waitForExpenseCall(2)
        data.fail(call: 2, with: CancellationError())
        await canceled.value

        #expect(viewModel.expenses.map(\.id) == [1])
        #expect(viewModel.errorMessage.isEmpty)
    }

    // A superseded refresh is control flow, not a failure the user should read about.
    @Test func aSupersededRefreshLeavesTheScreenAloneWhenItFails() async {
        let data = ControlledGroupData()
        data.expensesForCall = { call in [TestExpense.make(id: call, paidBy: 1, amount: 10, splitAmounts: [1: 10])] }
        let viewModel = GroupViewModel(dataSource: data.source())

        let first = viewModel.beginRefresh(groupId: 1)
        await data.waitForExpenseCall(1)
        let second = viewModel.beginRefresh(groupId: 1)
        await data.waitForExpenseCall(2)

        data.release(call: 2)
        await second.value
        data.fail(call: 1, with: APIError.httpError(500, message: nil))
        await first.value

        #expect(viewModel.expenses.map(\.id) == [2])
        #expect(viewModel.errorMessage.isEmpty)
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
    var summaryForCall: (Int) -> GroupBalanceSummary = { _ in
        GroupBalanceSummary(balances: [], balancesPending: false)
    }

    /// When true, requests answer immediately instead of waiting for `release(call:)`.
    var autoRelease = false

    private(set) var groupCallCount = 0
    private(set) var expenseCallCount = 0
    private(set) var summaryCallCount = 0
    private(set) var balanceRetryCount = 0

    private var waitingForOutcome: [Int: CheckedContinuation<Outcome, Never>] = [:]
    private var outcomes: [Int: Outcome] = [:]
    private var waitingForCall: [Int: CheckedContinuation<Void, Never>] = [:]

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
            summary: { [self] _ in await noteSummaryCall() },
            waitForBalanceRetry: { [self] _ in await noteBalanceRetry() }
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

    private func noteSummaryCall() -> GroupBalanceSummary {
        summaryCallCount += 1
        return summaryForCall(summaryCallCount)
    }

    private func noteBalanceRetry() {
        balanceRetryCount += 1
    }
}
