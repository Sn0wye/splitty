//
//  RecurringExpenseFormTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

/// What the expense form sends once Repeats is in play. Every case reads the request the
/// form built, never the view.
@Suite(.appLanguage(.english))
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
        #expect(request.reach == nil)
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

    @Test func onlyThisOneChangesNothingElse() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.monthly), api)
        viewModel.amount = AmountExpression(cents: 1_200)

        let write = await viewModel.save(scope: .this)

        #expect(try #require(api.updated.first).reach == .this)
        guard case .expenseEdited = write else {
            Issue.record("Expected a plain edit, got \(String(describing: write))")
            return
        }
    }

    // The zone travels with every "this and following" edit, so a member who moved gets
    // the 1st where they are now.
    @Test func thisAndFollowingCarriesTheDevicesZone() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.monthly), api)
        viewModel.amount = AmountExpression(cents: 1_200)

        let write = await viewModel.save(scope: .following)

        #expect(try #require(api.updated.first).reach == .following(repeat: nil, timeZone: Self.zone))
        guard case .expenseEditedWithFollowing = write else {
            Issue.record("Expected a following edit, got \(String(describing: write))")
            return
        }
    }

    @Test func aChangedFrequencySkipsTheChoiceAndReachesFollowing() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.monthly), api)
        viewModel.repeatFrequency = .weekly

        #expect(viewModel.needsScopeChoice == false)
        _ = await viewModel.save()

        #expect(try #require(api.updated.first).reach == .following(repeat: .weekly, timeZone: Self.zone))
    }

    @Test func doesNotRepeatStopsItFromThisExpenseOn() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.fortnightly), api)
        viewModel.repeatFrequency = .never

        #expect(viewModel.needsScopeChoice == false)
        _ = await viewModel.save()

        #expect(try #require(api.updated.first).reach == .following(repeat: .never, timeZone: Self.zone))
    }

    // MARK: - Ends

    @Test func neverEndingIsTheDefaultAndSendsNoEnd() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = newExpense(api)
        viewModel.repeatFrequency = .monthly

        #expect(viewModel.repeatEnd.kind == .never)
        _ = await viewModel.save()

        #expect(try #require(api.created.first).repeats?.endsOn == nil)
    }

    // The server only takes a day: twelve monthly expenses from the 31st end on the day the
    // twelfth comes due, clamped like the server clamps it.
    @Test func afterACountSendsTheDayTheLastOneComesDue() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = newExpense(api, timeZone: Self.utc)
        viewModel.repeatFrequency = .monthly
        viewModel.date = try Self.day(2030, 1, 31)
        viewModel.repeatEnd.kind = .afterCount
        viewModel.repeatEnd.count = 4

        #expect(viewModel.endsOn == "2030-04-30")
        _ = await viewModel.save()

        #expect(try #require(api.created.first).repeats?.endsOn == "2030-04-30")
    }

    @Test func afterACountStartsAtOne() throws {
        let viewModel = newExpense(RecordingExpenseAPI(), timeZone: Self.utc)
        viewModel.repeatFrequency = .monthly
        viewModel.date = try Self.day(2030, 1, 15)
        viewModel.repeatEnd.kind = .afterCount

        #expect(viewModel.repeatEnd.count == 1)
        #expect(viewModel.endsOn == "2030-01-15")
    }

    @Test func aCountOfOneEndsOnTheStartDay() throws {
        let viewModel = newExpense(RecordingExpenseAPI(), timeZone: Self.utc)
        viewModel.repeatFrequency = .weekly
        viewModel.date = try Self.day(2030, 1, 15)
        viewModel.repeatEnd.kind = .afterCount
        viewModel.repeatEnd.count = 1

        #expect(viewModel.endsOn == "2030-01-15")

        viewModel.repeatEnd.count = 3
        #expect(viewModel.endsOn == "2030-01-29")
    }

    @Test func aYearlyCountFromTheTwentyNinthOfFebruaryLandsOnTheTwentyEighth() throws {
        let viewModel = newExpense(RecordingExpenseAPI(), timeZone: Self.utc)
        viewModel.repeatFrequency = .yearly
        viewModel.date = try Self.day(2028, 2, 29)
        viewModel.repeatEnd.kind = .afterCount
        viewModel.repeatEnd.count = 2

        #expect(viewModel.endsOn == "2029-02-28")
    }

    @Test func aCountBelowOneCannotBeSaved() async {
        let api = RecordingExpenseAPI()
        let viewModel = newExpense(api)
        viewModel.repeatFrequency = .monthly
        viewModel.repeatEnd.kind = .afterCount
        viewModel.repeatEnd.count = 0

        #expect(viewModel.repeatEndMessage == "It has to repeat at least once")
        #expect(viewModel.canSave == false)
        #expect(await viewModel.save() == nil)
        #expect(api.created.isEmpty)
    }

    @Test func onADateSendsThatDayInTheDevicesZone() async throws {
        let api = RecordingExpenseAPI()
        let zone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let viewModel = newExpense(api, timeZone: zone)
        viewModel.repeatFrequency = .monthly
        viewModel.date = try Self.day(2030, 1, 10)
        viewModel.repeatEnd.kind = .onDate
        // 01:00 UTC on 1 July is still 30 June in São Paulo.
        viewModel.repeatEnd.date = try #require(ISO8601DateFormatter().date(from: "2030-07-01T01:00:00Z"))

        _ = await viewModel.save()

        #expect(try #require(api.created.first).repeats?.endsOn == "2030-06-30")
    }

    @Test func anEndBeforeTheStartCannotBeSaved() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = newExpense(api, timeZone: Self.utc)
        viewModel.repeatFrequency = .monthly
        viewModel.date = try Self.day(2030, 3, 10)
        viewModel.repeatEnd.kind = .onDate
        viewModel.repeatEnd.date = try Self.day(2030, 3, 9)

        #expect(viewModel.repeatEndMessage == "A repeating expense can't end before it starts")
        #expect(await viewModel.save() == nil)

        viewModel.repeatEnd.date = try Self.day(2030, 3, 10)
        #expect(viewModel.repeatEndMessage == nil)
        #expect(viewModel.canSave)
    }

    @Test func anEndIsIgnoredOnceItDoesNotRepeat() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = newExpense(api)
        viewModel.repeatFrequency = .monthly
        viewModel.repeatEnd.kind = .afterCount
        viewModel.repeatEnd.count = 0
        viewModel.repeatFrequency = .never

        #expect(viewModel.canSave)
        _ = await viewModel.save()
        #expect(try #require(api.created.first).repeats == nil)
    }

    // MARK: - Editing the end

    @Test func aLinkedExpenseWithAnEndShowsItsDay() throws {
        let viewModel = editing(linked(.monthly, endsOn: "2030-12-15"), RecordingExpenseAPI())

        #expect(viewModel.repeatEnd.kind == .onDate)
        #expect(viewModel.endsOn == "2030-12-15")
        #expect(viewModel.needsScopeChoice)
    }

    @Test func anUnchangedEndIsNotSent() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.monthly, endsOn: "2030-12-15"), api)
        viewModel.amount = AmountExpression(cents: 1_200)

        _ = await viewModel.save(scope: .following)

        #expect(try #require(api.updated.first).reach == .following(repeat: nil, timeZone: Self.zone))
    }

    @Test func aChangedEndReachesFollowingWithoutAsking() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.monthly, endsOn: "2030-12-15"), api)
        viewModel.repeatEnd.date = try #require(
            RecurringDueDays.date(fromDay: "2030-06-15", calendar: RecurringDueDays.calendar(in: TimeZone(identifier: Self.zone)!))
        )

        #expect(viewModel.needsScopeChoice == false)
        let write = await viewModel.save()

        #expect(try #require(api.updated.first).reach == .following(repeat: nil, timeZone: Self.zone, end: .on("2030-06-15")))
        guard case .expenseEditedWithFollowing = write else {
            Issue.record("Expected a following edit, got \(String(describing: write))")
            return
        }
    }

    @Test func removingTheEndSendsNever() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.monthly, endsOn: "2030-12-15"), api)
        viewModel.repeatEnd.kind = .never

        _ = await viewModel.save()

        #expect(try #require(api.updated.first).reach == .following(repeat: nil, timeZone: Self.zone, end: .never))
    }

    @Test func anEndCanBeAddedToOneThatHadNone() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.weekly, date: "2030-01-22T12:00:00Z"), api)
        #expect(viewModel.repeatEnd.kind == .never)
        viewModel.repeatEnd.kind = .afterCount
        viewModel.repeatEnd.count = 3

        _ = await viewModel.save()

        // Counted from this expense, in Tokyo, where noon UTC on the 22nd is already evening.
        #expect(try #require(api.updated.first).reach == .following(repeat: nil, timeZone: Self.zone, end: .on("2030-02-05")))
    }

    @Test func stoppingSendsNoEnd() async throws {
        let api = RecordingExpenseAPI()
        let viewModel = editing(linked(.monthly, endsOn: "2030-12-15"), api)
        viewModel.repeatFrequency = .never

        _ = await viewModel.save()

        #expect(try #require(api.updated.first).reach == .following(repeat: .never, timeZone: Self.zone))
    }

    // MARK: - Fixtures

    private static let utc = TimeZone(identifier: "UTC")!

    /// Noon on a day in UTC, so the day reads the same in UTC and São Paulo.
    private static func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(RecurringDueDays.calendar(in: utc).date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

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

    private static let zone = "Asia/Tokyo"

    private func editing(_ expense: Expense, _ api: RecordingExpenseAPI) -> ExpenseFormViewModel {
        ExpenseFormViewModel(
            groupId: 1,
            members: TestExpense.members,
            currentUserId: 1,
            expense: expense,
            dataSource: api.source(),
            timeZone: { TimeZone(identifier: Self.zone)! }
        )
    }

    private func linked(_ frequency: ExpenseRepeat, date: String? = nil, endsOn: String? = nil) -> Expense {
        var expense = TestExpense.make(id: 7, paidBy: 1, amount: 30, splitAmounts: [1: 15, 2: 15], date: date)
        expense.recurringExpenseId = 40
        expense.repeatFrequency = frequency
        expense.endsOn = endsOn
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
