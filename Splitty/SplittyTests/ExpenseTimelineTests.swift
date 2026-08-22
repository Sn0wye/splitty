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
}
