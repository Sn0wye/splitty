//
//  GroupRefreshTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

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
    /// Rows the nth expense request answers with.
    var expensesForCall: (Int) -> [Expense] = { _ in [] }

    /// When true, requests answer immediately instead of waiting for `release(call:)`.
    var autoRelease = false

    private(set) var groupCallCount = 0
    private(set) var expenseCallCount = 0
    private(set) var summaryCallCount = 0

    private var waiting: [Int: CheckedContinuation<Error?, Never>] = [:]
    private var resolved: [Int: Error?] = [:]

    func source() -> GroupDataSource {
        GroupDataSource(
            group: { [self] groupId in await noteGroupCall(id: groupId) },
            expenses: { [self] _ in
                let call = await noteExpenseCall()
                if let error = await gate(call: call) { throw error }
                return await expensesForCall(call)
            },
            summary: { [self] _ in await noteSummaryCall() }
        )
    }

    func release(call: Int) {
        resolve(call: call, with: nil)
    }

    func fail(call: Int, with error: Error) {
        resolve(call: call, with: error)
    }

    /// Waits until the nth expense request has been issued. Bounded, so a wiring mistake
    /// fails the test instead of hanging the suite.
    func waitForExpenseCall(_ call: Int) async {
        for _ in 0..<2_000 where expenseCallCount < call {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(expenseCallCount >= call)
    }

    private func noteGroupCall(id: Int) -> GroupDetail {
        groupCallCount += 1
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
        return expenseCallCount
    }

    private func noteSummaryCall() -> GroupBalanceSummary {
        summaryCallCount += 1
        return GroupBalanceSummary(balances: [], balancesPending: false)
    }

    private func resolve(call: Int, with error: Error?) {
        if let continuation = waiting.removeValue(forKey: call) {
            continuation.resume(returning: error)
        } else {
            resolved[call] = error
        }
    }

    private func gate(call: Int) async -> Error? {
        if autoRelease { return nil }
        if let outcome = resolved.removeValue(forKey: call) { return outcome }
        return await withCheckedContinuation { continuation in
            waiting[call] = continuation
        }
    }
}
