//
//  ExpenseFormViewModelTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

@MainActor
struct ExpenseFormViewModelTests {

    private func newExpense(currentUserId: Int = 1) -> ExpenseFormViewModel {
        ExpenseFormViewModel(groupId: 1, members: TestExpense.members, currentUserId: currentUserId)
    }

    // MARK: - Creating

    @Test func startsWithYouPayingAndAnEqualSplit() {
        let viewModel = newExpense()
        #expect(viewModel.configuration == SplitConfiguration(payerId: 1, mode: .equal(participants: [1, 2, 3])))
        #expect(viewModel.splitSummary == "Paid by you and split equally")
    }

    @Test func startsWithNothingSaveable() {
        let viewModel = newExpense()
        #expect(viewModel.canSave == false)
        #expect(viewModel.title == "New expense")
    }

    @Test func needsADescription() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        #expect(viewModel.canSave == false)
        viewModel.description = "Taxi"
        #expect(viewModel.canSave)
    }

    @Test func rejectsADescriptionOfOnlySpaces() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.description = "   "
        #expect(viewModel.canSave == false)
    }

    @Test func blocksWhenEveryMemberIsUnchecked() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.description = "Taxi"
        viewModel.configuration.mode = .equal(participants: [])
        #expect(viewModel.canSave == false)
        #expect(viewModel.blockingMessage == "Select who this is split between")
    }

    @Test func reportsWhatIsLeftToAssignOnACustomSplit() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 1)
        viewModel.amount.type(digit: 0)
        viewModel.description = "Taxi"
        viewModel.configuration.mode = .custom(amounts: [1: 400])
        #expect(viewModel.canSave == false)
        #expect(viewModel.blockingMessage == "$6.00 left to assign")
    }

    @Test func reportsAnOverAssignedCustomSplit() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 1)
        viewModel.amount.type(digit: 0)
        viewModel.description = "Taxi"
        viewModel.configuration.mode = .custom(amounts: [1: 1200])
        #expect(viewModel.blockingMessage == "$2.00 over the total")
    }

    // Refusing to save a number the app can compute is a puzzle, not a safeguard.
    @Test func autoEvaluatesAPendingExpression() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 6)
        viewModel.amount.apply(.divide)
        viewModel.amount.type(digit: 4)
        viewModel.description = "Taxi"
        #expect(viewModel.canSave)
        #expect(viewModel.totalCents == 150)
    }

    @Test func splitsTheResolvedTotal() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 1)
        viewModel.amount.type(digit: 0)
        let splits = viewModel.splits()
        #expect(splits.map(\.userId) == [1, 2, 3])
        #expect(splits.map(\.amountCents) == [334, 333, 333])
    }

    // MARK: - Editing

    @Test func seedsFromAnExistingExpense() {
        let expense = TestExpense.make(
            paidBy: 2,
            amount: 66,
            splitAmounts: [1: 40, 2: 26],
            date: "2026-07-04T10:30:00Z"
        )
        let viewModel = ExpenseFormViewModel(
            groupId: 1,
            members: TestExpense.members,
            currentUserId: 1,
            expense: expense
        )

        #expect(viewModel.title == "Edit expense")
        #expect(viewModel.amount.displayText == "66")
        #expect(viewModel.description == "Dinner")
        #expect(viewModel.configuration == SplitConfiguration(payerId: 2, mode: .custom(amounts: [1: 4000, 2: 2600])))
        #expect(viewModel.date == Expense.parseTimestamp("2026-07-04T10:30:00Z"))
        #expect(viewModel.canSave)
    }

    // Reopening an equal split and changing the total keeps it equal — one gesture, which
    // is the whole reason the mode is inferred rather than stored.
    @Test func rederivesAnEqualSplitWhenTheTotalChanges() {
        let expense = TestExpense.make(paidBy: 1, amount: 60, splitAmounts: [1: 20, 2: 20, 3: 20])
        let viewModel = ExpenseFormViewModel(
            groupId: 1,
            members: TestExpense.members,
            currentUserId: 1,
            expense: expense
        )

        viewModel.amount.clear()
        viewModel.amount.type(digit: 6)
        viewModel.amount.type(digit: 6)

        #expect(viewModel.splits().map(\.amountCents) == [2200, 2200, 2200])
    }

    // A custom split keeps the numbers a person typed and reports the shortfall instead.
    @Test func keepsCustomAmountsWhenTheTotalChanges() {
        let expense = TestExpense.make(paidBy: 1, amount: 60, splitAmounts: [1: 40, 2: 20])
        let viewModel = ExpenseFormViewModel(
            groupId: 1,
            members: TestExpense.members,
            currentUserId: 1,
            expense: expense
        )

        viewModel.amount.clear()
        viewModel.amount.type(digit: 6)
        viewModel.amount.type(digit: 6)

        #expect(viewModel.configuration.mode == .custom(amounts: [1: 4000, 2: 2000]))
        #expect(viewModel.blockingMessage == "$6.00 left to assign")
    }

    // MARK: - Presets

    @Test func applyingAPresetReplacesThePayerAndTheMode() {
        let viewModel = newExpense()
        viewModel.apply(preset: .someoneElsePaidSplitEqually, payerId: 3)
        #expect(viewModel.configuration == SplitConfiguration(payerId: 3, mode: .equal(participants: [1, 2, 3])))
        #expect(viewModel.selectedPreset == .someoneElsePaidSplitEqually)
    }

    // Switching to custom seeds the rows from the equal division rather than from nothing:
    // adjusting two numbers beats typing every one of them.
    @Test func customSeedsFromWhateverTheSplitCurrentlyIs() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.apply(preset: .custom, payerId: nil)
        #expect(viewModel.configuration.mode == .custom(amounts: [1: 300, 2: 300, 3: 300]))
        #expect(viewModel.canSave == false) // description still empty
        #expect(viewModel.blockingMessage == nil)
    }

    @Test func togglingAMemberOffRederivesAcrossTheRest() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.toggleParticipant(2)
        #expect(viewModel.configuration.mode == .equal(participants: [1, 3]))
        #expect(viewModel.splits().map(\.userId) == [1, 3])
    }

    @Test func togglingWithACustomSplitZeroesThatRow() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.apply(preset: .custom, payerId: nil)
        viewModel.toggleParticipant(2)
        #expect(viewModel.configuration.mode == .custom(amounts: [1: 300, 2: 0, 3: 300]))
    }
}
