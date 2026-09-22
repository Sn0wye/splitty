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

    // MARK: - Modes and drafts

    // Each mode keeps its own draft for as long as the sheet is open — the split screen is
    // popped and pushed constantly while composing, so the drafts cannot live there.
    @Test func keepsEachModesDraftAcrossASwitch() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)

        viewModel.selectMode(.custom)
        viewModel.setCustomText("4", for: 1)
        viewModel.setCustomText("5", for: 2)

        viewModel.selectMode(.percentage)
        viewModel.setPercentageText("70", for: 1)
        viewModel.setPercentageText("30", for: 3)
        #expect(viewModel.configuration.mode == .percentage(percentages: [1: 70, 3: 30]))

        viewModel.selectMode(.equal)
        #expect(viewModel.configuration.mode == .equal(participants: [1, 2, 3]))

        viewModel.selectMode(.custom)
        #expect(viewModel.configuration.mode == .custom(amounts: [1: 400, 2: 500]))
        #expect(viewModel.customText[1] == "4")

        viewModel.selectMode(.percentage)
        #expect(viewModel.configuration.mode == .percentage(percentages: [1: 70, 3: 30]))
        #expect(viewModel.percentageText[3] == "30")
    }

    // A new expense starts both typed modes empty: a blank field is what says "not
    // participating", and seeding it from the equal division would say the opposite.
    @Test func startsTheTypedModesEmpty() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)

        viewModel.selectMode(.custom)
        #expect(viewModel.configuration.mode == .custom(amounts: [:]))
        #expect(viewModel.blockingMessage == "$9.00 left to assign")

        viewModel.selectMode(.percentage)
        #expect(viewModel.configuration.mode == .percentage(percentages: [:]))
        #expect(viewModel.blockingMessage == "Select who this is split between")
    }

    // Clearing a field removes the row rather than zeroing it: zero is a share the API
    // refuses, blank is someone left out.
    @Test func clearingAFieldDropsThatParticipant() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.selectMode(.custom)
        viewModel.setCustomText("9", for: 1)
        viewModel.setCustomText("", for: 2)
        #expect(viewModel.configuration.mode == .custom(amounts: [1: 900]))
        #expect(viewModel.canSave == false) // description still empty
        #expect(viewModel.blockingMessage == nil)
    }

    @Test func reportsWhatIsLeftOnAPercentageSplit() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.selectMode(.percentage)
        viewModel.setPercentageText("80", for: 1)
        #expect(viewModel.blockingMessage == "20% left to assign")
        #expect(viewModel.splitSummary == "Paid by you, 20% left to assign")
    }

    @Test func namesTheShareThatRoundsDownToNothing() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 1) // $1.00, small enough that 0.4% floors to nothing
        viewModel.selectMode(.percentage)
        viewModel.setPercentageText("99.6", for: 1)
        viewModel.setPercentageText("0.4", for: 2)
        #expect(viewModel.blockingMessage == "Bob's share rounds down to nothing")
    }

    @Test func togglingAMemberOffRederivesAcrossTheRest() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.toggleParticipant(2)
        #expect(viewModel.configuration.mode == .equal(participants: [1, 3]))
        #expect(viewModel.splits().map(\.userId) == [1, 3])
    }

    // The checkbox set is a draft like any other: unchecking someone, wandering through
    // the other two modes and coming back finds the same boxes ticked.
    @Test func keepsTheCheckboxSetAcrossASwitch() {
        let viewModel = newExpense()
        viewModel.toggleParticipant(2)
        viewModel.selectMode(.custom)
        viewModel.selectMode(.equal)
        #expect(viewModel.configuration.mode == .equal(participants: [1, 3]))
    }

    // MARK: - Editing a stored mode

    @Test func loadsBothTypedDraftsFromAStoredExpense() {
        let expense = TestExpense.make(
            paidBy: 1,
            amount: 100,
            splitAmounts: [1: 70, 2: 30],
            splitMode: .percentage,
            percentages: [1: 70, 2: 30]
        )
        let viewModel = ExpenseFormViewModel(
            groupId: 1,
            members: TestExpense.members,
            currentUserId: 1,
            expense: expense
        )

        #expect(viewModel.configuration.mode == .percentage(percentages: [1: 70, 2: 30]))
        #expect(viewModel.percentageText == [1: "70", 2: "30"])

        viewModel.selectMode(.custom)
        #expect(viewModel.configuration.mode == .custom(amounts: [1: 7000, 2: 3000]))
        #expect(viewModel.customText == [1: "70", 2: "30"])
    }

    // A percentage split re-derives when the total moves, which is the reason to type
    // shares instead of amounts.
    @Test func rederivesAPercentageSplitWhenTheTotalChanges() {
        let expense = TestExpense.make(
            paidBy: 1,
            amount: 100,
            splitAmounts: [1: 70, 2: 30],
            splitMode: .percentage,
            percentages: [1: 70, 2: 30]
        )
        let viewModel = ExpenseFormViewModel(
            groupId: 1,
            members: TestExpense.members,
            currentUserId: 1,
            expense: expense
        )

        viewModel.amount.clear()
        viewModel.amount.type(digit: 5)
        viewModel.amount.type(digit: 0)

        #expect(viewModel.splits().map(\.amountCents) == [3500, 1500])
        #expect(viewModel.splits().map(\.percentage) == [70, 30])
    }
}
