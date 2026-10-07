//
//  RecurringExpenseFormTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

/// What the expense form sends once Repeats is in play. Every case reads the request the
/// form built, never the view.
@MainActor
struct RecurringExpenseFormTests {

    // MARK: - Creating

    @Test func defaultsToDoesNotRepeatAndSendsNoRepeatFields() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = newExpense(api)
        #expect(viewModel.repeatFrequency == .never)
        #expect(viewModel.showsRepeatPicker)

        _ = await viewModel.save()

        let request = try #require(api.created.first)
        #expect(request.repeats == nil)
    }

    @Test func aChosenFrequencySendsItWithTheDevicesTimeZone() async throws {
        let api = RecordingExpenseAPI()
        let zone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let viewModel = newExpense(api, timeZone: zone)
        viewModel.repeatFrequency = .monthly

        let write = await viewModel.save()

        let request = try #require(api.created.first)
        #expect(request.repeats == RepeatStart(frequency: .monthly, timeZone: "America/Sao_Paulo"))
        guard case .expenseCreated = write else {
            Issue.record("Expected a created expense, got \(String(describing: write))")
            return
        }
    }

    @Test func aRepeatingExpenseCannotStartBeforeToday() async {
        let api = RecordingExpenseAPI()
        let viewModel = newExpense(api)
        viewModel.repeatFrequency = .weekly
        viewModel.date = Calendar.current.date(byAdding: .day, value: -3, to: Date())!

        #expect(viewModel.canSave == false)
        #expect(viewModel.repeatDateMessage == "A repeating expense can't start before today")
        #expect(await viewModel.save() == nil)
        #expect(api.created.isEmpty)

        viewModel.repeatFrequency = .never
        #expect(viewModel.canSave)
        #expect(viewModel.repeatDateMessage == nil)
    }

    @Test func choosingAFrequencyMovesAPastDateToToday() {
        let viewModel = newExpense(RecordingExpenseAPI())
        viewModel.date = Calendar.current.date(byAdding: .day, value: -3, to: Date())!

        viewModel.repeatFrequency = .yearly

        #expect(Calendar.current.isDateInToday(viewModel.date))
        #expect(viewModel.earliestDate == Calendar.current.startOfDay(for: Date()))
        #expect(viewModel.canSave)
    }

    @Test func aRepeatingExpenseMayStartInTheFuture() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = newExpense(api)
        viewModel.repeatFrequency = .monthly
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        viewModel.date = nextMonth

        #expect(viewModel.canSave)
        _ = await viewModel.save()
        #expect(try #require(api.created.first).date == nextMonth)
    }

    // MARK: - Editing a plain expense

    @Test func aPlainExpenseHidesRepeatsAndEditsAsBefore() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(TestExpense.make(id: 7, paidBy: 1, amount: 9, splitAmounts: [1: 9]), api)

        #expect(viewModel.showsRepeatPicker == false)
        #expect(viewModel.needsScopeChoice == false)

        let write = await viewModel.save()

        let request = try #require(api.updated.first)
        #expect(request.scope == nil)
        #expect(request.repeatFrequency == nil)
        #expect(request.expenseId == 7)
        guard case .expenseEdited = write else {
            Issue.record("Expected a plain edit, got \(String(describing: write))")
            return
        }
    }

    // MARK: - Editing an expense a recurring expense added

    @Test func aLinkedExpenseStartsAtItsFrequencyAndAsksHowFarToReach() {
        let viewModel = editing(linked(.monthly), RecordingExpenseAPI())

        #expect(viewModel.showsRepeatPicker)
        #expect(viewModel.repeatFrequency == .monthly)
        #expect(viewModel.needsScopeChoice)
    }

    // Last month's rent is in the past, and editing it must still be possible.
    @Test func aLinkedExpenseDatedInThePastCanStillBeSaved() {
        let past = linked(.monthly, date: "2026-01-01T12:00:00Z")
        let viewModel = editing(past, RecordingExpenseAPI())

        #expect(viewModel.canSave)
        #expect(viewModel.earliestDate == nil)
    }

    @Test(arguments: [ExpenseScope.this, .following])
    func theChosenScopeTravelsWithoutARepeat(scope: ExpenseScope) async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.monthly), api)
        viewModel.amount = AmountExpression(cents: 1_200)

        let write = await viewModel.save(scope: scope)

        let request = try #require(api.updated.first)
        #expect(request.scope == scope)
        #expect(request.repeatFrequency == nil)
        switch (scope, write) {
        case (.this, .expenseEdited?), (.following, .expenseEditedWithFollowing?): break
        default: Issue.record("Scope \(scope) reported \(String(describing: write))")
        }
    }

    @Test func aChangedFrequencySkipsTheChoiceAndReachesFollowing() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.monthly), api)
        viewModel.repeatFrequency = .weekly

        #expect(viewModel.needsScopeChoice == false)
        _ = await viewModel.save()

        let request = try #require(api.updated.first)
        #expect(request.scope == .following)
        #expect(request.repeatFrequency == .weekly)
    }

    @Test func doesNotRepeatStopsItFromThisExpenseOn() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.fortnightly), api)
        viewModel.repeatFrequency = .never

        #expect(viewModel.needsScopeChoice == false)
        _ = await viewModel.save()

        let request = try #require(api.updated.first)
        #expect(request.scope == .following)
        #expect(request.repeatFrequency == .never)
    }

    // MARK: - Fixtures

    private func newExpense(_ api: RecordingExpenseAPI, timeZone: TimeZone = .current) -> ExpenseFormViewModel {
        let viewModel = ExpenseFormViewModel(
            groupId: 1,
            members: TestExpense.members,
            currentUserId: 1,
            dataSource: api.source(),
            timeZone: { timeZone }
        )
        viewModel.amount = AmountExpression(cents: 3_000)
        viewModel.description = "Rent"
        return viewModel
    }

    private func editing(_ expense: Expense, _ api: RecordingExpenseAPI) -> ExpenseFormViewModel {
        ExpenseFormViewModel(
            groupId: 1,
            members: TestExpense.members,
            currentUserId: 1,
            expense: expense,
            dataSource: api.source()
        )
    }

    private func linked(_ frequency: ExpenseRepeat, date: String? = nil) -> Expense {
        var expense = TestExpense.make(id: 7, paidBy: 1, amount: 30, splitAmounts: [1: 15, 2: 15], date: date)
        expense.recurringExpenseId = 40
        expense.repeatFrequency = frequency
        return expense
    }
}

/// Records what the form asked for and answers with a plausible row.
@MainActor
final class RecordingExpenseAPI {
    private(set) var created: [NewExpenseRequest] = []
    private(set) var updated: [ExpenseUpdateRequest] = []

    func source() -> ExpenseFormDataSource {
        ExpenseFormDataSource(
            create: { [self] request in
                created.append(request)
                return TestExpense.make(id: 99, paidBy: request.paidBy, amount: 30, splitAmounts: [1: 30])
            },
            update: { [self] request in
                updated.append(request)
                return TestExpense.make(id: request.expenseId, paidBy: 1, amount: 30, splitAmounts: [1: 30])
            }
        )
    }
}
