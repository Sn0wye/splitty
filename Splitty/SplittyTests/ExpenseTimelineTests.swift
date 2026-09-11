//
//  ExpenseTimelineTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

@MainActor
struct ExpenseTimelineTests {

    // The saved row is real — the server returned it — so it appears without waiting for
    // the refetch that follows the sheet's dismissal.
    @Test func insertingAnExpenseShowsItImmediately() {
        let viewModel = GroupViewModel()
        viewModel.insert(TestExpense.make(id: 9, paidBy: 1, amount: 30, splitAmounts: [1: 30]))

        #expect(viewModel.expenses.map(\.id) == [9])
        #expect(viewModel.groupedExpenses.flatMap { $0.expenses }.map(\.id) == [9])
    }

    @Test func insertingAnEditedExpenseReplacesTheRowRatherThanDoublingIt() {
        let viewModel = GroupViewModel()
        viewModel.insert(TestExpense.make(id: 9, paidBy: 1, amount: 30, splitAmounts: [1: 30]))
        viewModel.insert(TestExpense.make(id: 9, paidBy: 1, amount: 45, splitAmounts: [1: 45]))

        #expect(viewModel.expenses.map(\.amount) == [45])
    }
}

struct ExpenseReadingTests {

    // A settlement's splits are [+amount, -amount], so the counterparty is the one that is
    // not the payer's.
    @Test func readsTheCounterpartyOffASettlement() {
        let settlement = TestExpense.make(paidBy: 2, amount: 10, splitAmounts: [2: 10, 3: -10], type: .payment)
        #expect(settlement.peer?.id == 3)
    }

    @Test func hasNoCounterpartyWhenNobodyElseCarriesASplit() {
        let expense = TestExpense.make(paidBy: 2, amount: 10, splitAmounts: [2: 10])
        #expect(expense.peer == nil)
    }

    // The payer lent the total less their own share; everyone else borrowed theirs.
    @Test func readsWhatThePayerLent() {
        let expense = TestExpense.make(paidBy: 1, amount: 30, splitAmounts: [1: 10, 2: 20])
        #expect(expense.getUserSplit(currentUserId: 1) == 20)
        #expect(expense.getUserSplit(currentUserId: 2) == -20)
    }

    // Files under the user-supplied date when there is one, the audit timestamp otherwise.
    @Test func fallsBackToTheAuditTimestampWithoutADate() {
        let undated = TestExpense.make(paidBy: 1, amount: 10, splitAmounts: [1: 10])
        #expect(undated.effectiveDate == Expense.parseTimestamp("2026-08-20T12:00:00Z"))

        let dated = TestExpense.make(paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2026-07-04T10:30:00Z")
        #expect(dated.effectiveDate == Expense.parseTimestamp("2026-07-04T10:30:00Z"))
    }
}

struct APIErrorMessageTests {

    // The server's own 400 is the only thing that knows why a split the client believed in
    // was refused, so it is what goes on screen.
    @Test func prefersTheServersOwnExplanation() {
        let error = APIError.httpError(400, message: "Expense splits must sum to the total.")
        #expect(error.displayMessage == "Expense splits must sum to the total.")
    }

    @Test func fallsBackToCopyOfItsOwnWhenTheServerSaidNothing() {
        #expect(APIError.httpError(403, message: nil).displayMessage == "You are not a member of this group.")
        #expect(APIError.httpError(500, message: nil).displayMessage == "Something went wrong (500). Try again.")
    }

    @Test func readsAnErrorThatIsNotAnAPIError() {
        struct Sad: LocalizedError { var errorDescription: String? { "Sad" } }
        #expect(Sad().displayMessage == "Sad")
    }

    @Test func recognisesCancellationAsControlFlowRatherThanANetworkFailure() {
        #expect(CancellationError().isCancellation)
        #expect(URLError(.cancelled).isCancellation)
        #expect(APIError.networkError(URLError(.cancelled)).isCancellation)
        #expect(!URLError(.notConnectedToInternet).isCancellation)
    }

    @Test func recognisesOnlyANotFoundResponseAsAlreadyGone() {
        #expect(APIError.httpError(404, message: nil).isAlreadyGone)
        #expect(APIError.httpError(404, message: "This no longer exists.").isAlreadyGone)
        #expect(APIError.networkError(APIError.httpError(404, message: nil)).isAlreadyGone)

        #expect(!APIError.httpError(400, message: nil).isAlreadyGone)
        #expect(!APIError.httpError(403, message: nil).isAlreadyGone)
        #expect(!APIError.httpError(500, message: nil).isAlreadyGone)
        #expect(!URLError(.notConnectedToInternet).isAlreadyGone)
        #expect(!CancellationError().isAlreadyGone)
    }
}

// MARK: - Timeline construction

struct TimelineGroupingTests {

    @Test func ordersDaysAndRowsWithinADayNewestFirst() {
        let grouped = Expense.groupExpensesByDate([
            TestExpense.make(id: 1, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2026-04-10T09:00:00Z"),
            TestExpense.make(id: 2, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2026-04-12T08:00:00Z"),
            TestExpense.make(id: 3, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2026-04-12T20:00:00Z")
        ])

        #expect(grouped.map(\.date) == grouped.map(\.date).sorted(by: >))
        #expect(grouped.flatMap { $0.expenses }.map(\.id) == [3, 2, 1])
    }

    // Same label, different years. Identity is the normalized day, so SwiftUI cannot
    // reuse one section for the other.
    @Test func sectionsInDifferentYearsSharingALabelStillHaveDistinctIdentities() {
        let grouped = Expense.groupExpensesByDate([
            TestExpense.make(id: 1, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2021-04-12T09:00:00Z"),
            TestExpense.make(id: 2, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2027-04-12T09:00:00Z")
        ])

        #expect(grouped.count == 2)
        #expect(Set(grouped.map(\.dateString)).count == 1)
        #expect(Set(grouped.map(\.id)).count == 2)
    }

    @Test func filesAnUndatedRowUnderItsAuditTimestamp() {
        let grouped = Expense.groupExpensesByDate([
            TestExpense.make(id: 1, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        ])

        #expect(grouped.count == 1)
        #expect(grouped[0].date == Calendar.current.startOfDay(for: Expense.parseTimestamp("2026-08-20T12:00:00Z")!))
    }

    @Test func keepsARowWhoseTimestampCannotBeParsed() {
        let grouped = Expense.groupExpensesByDate([
            TestExpense.make(id: 1, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "not a date"),
            TestExpense.make(id: 2, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2026-04-12T09:00:00Z")
        ])

        #expect(grouped.flatMap { $0.expenses }.map(\.id) == [2, 1])
        #expect(grouped.last?.dateString == "Unknown")
    }

    @Test func readsTheAcceptedTimestampFormats() {
        let withFractionalSeconds = Expense.parseTimestamp("2026-04-12T09:00:00.123Z")
        let withoutFractionalSeconds = Expense.parseTimestamp("2026-04-12T09:00:00Z")
        let withoutAZone = Expense.parseTimestamp("2026-04-12T09:00:00")
        let withoutAZoneButFractional = Expense.parseTimestamp("2026-04-12T09:00:00.123")

        #expect(withoutFractionalSeconds == withoutAZone)
        #expect(withoutFractionalSeconds == withoutAZoneButFractional)
        #expect(withFractionalSeconds != nil)
        #expect(withFractionalSeconds! > withoutFractionalSeconds!)
        #expect(Expense.parseTimestamp("nonsense") == nil)
    }

    // Parsing is shared, so repeating a parse must not leak formatter state between the
    // formats — the old implementation mutated one formatter's options in place.
    @Test func repeatedParsesOfMixedFormatsStayStable() {
        let values = ["2026-04-12T09:00:00.123Z", "2026-04-12T09:00:00Z", "2026-04-12T09:00:00"]
        let first = values.map(Expense.parseTimestamp)
        let second = values.map(Expense.parseTimestamp)
        #expect(first == second)
        #expect(first.allSatisfy { $0 != nil })
    }

    @Test func labelsTodayAndYesterdayRelativeToNow() {
        let now = Expense.parseTimestamp("2026-04-12T09:00:00Z")!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let older = Calendar.current.date(byAdding: .day, value: -8, to: now)!

        #expect(Expense.dayLabel(for: now, now: now) == "Today")
        #expect(Expense.dayLabel(for: yesterday, now: now) == "Yesterday")
        #expect(Expense.dayLabel(for: older, now: now) != "Yesterday")
        #expect(Expense.dayLabel(for: nil, now: now) == "Unknown")
    }
}
