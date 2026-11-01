//
//  ExpenseFormViewModelTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

@Suite(.appLanguage(.english))
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

    @Test func saveAttemptExplainsMissingDescriptionUntilItIsFilled() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)

        #expect(viewModel.descriptionRequiredMessage == nil)
        #expect(viewModel.attemptSave() == false)
        #expect(viewModel.descriptionRequiredMessage == "Enter what this expense was for")

        viewModel.description = "   "
        #expect(viewModel.descriptionRequiredMessage != nil)

        viewModel.description = "Taxi"
        #expect(viewModel.descriptionRequiredMessage == nil)
        #expect(viewModel.attemptSave())
    }

    @Test func saveAttemptStillBlocksAnInvalidSplit() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.description = "Taxi"
        viewModel.configuration.mode = .equal(participants: [])

        #expect(viewModel.attemptSave() == false)
        #expect(viewModel.descriptionRequiredMessage == nil)
        #expect(viewModel.blockingMessage == "Select who this is split between")
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

    // Switching carries the split over: the reason to switch is usually to adjust one
    // share, and retyping every other one to get there is the cost this removes.
    @Test func prefillsAmountsFromTheEqualSplit() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 1)
        viewModel.amount.type(digit: 0)

        viewModel.selectMode(.custom)

        // $10.00 three ways: the remainder cent lands where the equal split puts it.
        #expect(viewModel.configuration.mode == .custom(amounts: [1: 334, 2: 333, 3: 333]))
        #expect(viewModel.customText == [1: "3.34", 2: "3.33", 3: "3.33"])
        #expect(viewModel.configuration.unassignedCents(totalCents: viewModel.totalCents) == 0)
        #expect(viewModel.blockingMessage == nil)
    }

    @Test func prefillsPercentagesFromTheEqualSplit() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 1)
        viewModel.amount.type(digit: 0)

        viewModel.selectMode(.percentage)

        #expect(viewModel.configuration.mode == .percentage(percentages: [
            1: Decimal(string: "33.34")!, 2: Decimal(string: "33.33")!, 3: Decimal(string: "33.33")!
        ]))
        #expect(viewModel.percentageText == [1: "33.34", 2: "33.33", 3: "33.33"])
        #expect(viewModel.configuration.unassignedPercent == 0)
        #expect(viewModel.blockingMessage == nil)
        #expect(viewModel.perParticipantAmounts.values.reduce(0, +) == 1000)
    }

    @Test func convertsTypedAmountsToPercentages() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 1)
        viewModel.amount.type(digit: 0)
        viewModel.selectMode(.custom)
        viewModel.setCustomText("5", for: 1)
        viewModel.setCustomText("3", for: 2)
        viewModel.setCustomText("2", for: 3)

        viewModel.selectMode(.percentage)

        #expect(viewModel.configuration.mode == .percentage(percentages: [1: 50, 2: 30, 3: 20]))
        #expect(viewModel.percentageText == [1: "50", 2: "30", 3: "20"])
    }

    @Test func convertsTypedPercentagesToAmounts() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 1)
        viewModel.amount.type(digit: 0)
        viewModel.selectMode(.percentage)
        viewModel.setPercentageText("70", for: 1)
        viewModel.setPercentageText("30", for: 2)
        viewModel.setPercentageText("", for: 3)

        viewModel.selectMode(.custom)

        #expect(viewModel.configuration.mode == .custom(amounts: [1: 700, 2: 300]))
        #expect(viewModel.customText == [1: "7", 2: "3"])
        #expect(viewModel.blockingMessage == nil)
    }

    // Going back to equal keeps who is in and forgets the numbers; leaving it again seeds
    // from the equal division, not from the numbers it forgot.
    @Test func switchingToEqualKeepsTheParticipantsAndDropsTheValues() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 1)
        viewModel.amount.type(digit: 0)
        viewModel.selectMode(.custom)
        viewModel.setCustomText("7", for: 1)
        viewModel.setCustomText("", for: 2)

        viewModel.selectMode(.equal)
        #expect(viewModel.configuration.mode == .equal(participants: [1, 3]))

        viewModel.selectMode(.custom)
        #expect(viewModel.configuration.mode == .custom(amounts: [1: 500, 3: 500]))
    }

    @Test func keepsAnEditToAPrefilledValue() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 1)
        viewModel.amount.type(digit: 0)
        viewModel.selectMode(.custom)

        viewModel.setCustomText("4", for: 2)
        viewModel.selectMode(.custom) // the selector re-sending the same mode

        #expect(viewModel.customText == [1: "3.34", 2: "4", 3: "3.33"])
        #expect(viewModel.configuration.mode == .custom(amounts: [1: 334, 2: 400, 3: 333]))
        #expect(viewModel.blockingMessage == "$0.67 over the total")
    }

    @Test func allNoneAndTheCheckboxesStillWorkAfterARoundTrip() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.selectMode(.custom)
        viewModel.selectMode(.percentage)
        viewModel.selectMode(.equal)

        #expect(viewModel.includesEveryParticipant)
        viewModel.toggleParticipant(2)
        #expect(viewModel.configuration.mode == .equal(participants: [1, 3]))
        viewModel.setEveryParticipant(included: false)
        #expect(viewModel.configuration.mode == .equal(participants: []))
        viewModel.setEveryParticipant(included: true)
        #expect(viewModel.configuration.mode == .equal(participants: [1, 2, 3]))
    }

    // With no total yet there are no amounts to carry over, so the fields start blank and
    // going back finds the checkboxes as they were; percentages need no total.
    @Test func prefillsNoAmountsBeforeThereIsATotal() {
        let viewModel = newExpense()
        viewModel.toggleParticipant(2)

        viewModel.selectMode(.custom)
        #expect(viewModel.configuration.mode == .custom(amounts: [:]))

        viewModel.selectMode(.equal)
        #expect(viewModel.configuration.mode == .equal(participants: [1, 3]))

        viewModel.selectMode(.percentage)
        #expect(viewModel.configuration.mode == .percentage(percentages: [1: 50, 3: 50]))
        #expect(viewModel.configuration.unassignedPercent == 0)
    }

    // Clearing a field removes the row rather than zeroing it: zero is a share the API
    // refuses, blank is someone left out.
    @Test func clearingAFieldDropsThatParticipant() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.selectMode(.custom)
        viewModel.setCustomText("9", for: 1)
        viewModel.setCustomText("", for: 2)
        viewModel.setCustomText("", for: 3)
        #expect(viewModel.configuration.mode == .custom(amounts: [1: 900]))
        #expect(viewModel.canSave == false) // description still empty
        #expect(viewModel.blockingMessage == nil)
    }

    @Test func reportsWhatIsLeftOnAPercentageSplit() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.selectMode(.percentage)
        viewModel.setPercentageText("80", for: 1)
        viewModel.setPercentageText("", for: 2)
        viewModel.setPercentageText("", for: 3)
        #expect(viewModel.blockingMessage == "20% left to assign")
        #expect(viewModel.splitSummary == "Paid by you, 20% left to assign")
    }

    @Test func namesTheShareThatRoundsDownToNothing() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 1) // $1.00, small enough that 0.4% floors to nothing
        viewModel.selectMode(.percentage)
        viewModel.setPercentageText("99.6", for: 1)
        viewModel.setPercentageText("0.4", for: 2)
        viewModel.setPercentageText("", for: 3)
        #expect(viewModel.blockingMessage == "Bob's share rounds down to nothing")
    }

    @Test func togglingAMemberOffRederivesAcrossTheRest() {
        let viewModel = newExpense()
        viewModel.amount.type(digit: 9)
        viewModel.toggleParticipant(2)
        #expect(viewModel.configuration.mode == .equal(participants: [1, 3]))
        #expect(viewModel.splits().map(\.userId) == [1, 3])
    }

    @Test func allAndNoneTickEveryoneOrNoOne() {
        let viewModel = newExpense()
        #expect(viewModel.includesEveryParticipant)
        viewModel.setEveryParticipant(included: false)
        #expect(viewModel.configuration.mode == .equal(participants: []))
        #expect(viewModel.includesEveryParticipant == false)
        viewModel.setEveryParticipant(included: true)
        #expect(viewModel.configuration.mode == .equal(participants: [1, 2, 3]))
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

    // MARK: - Removed members

    private static let membersWithRemoved = TestExpense.members + [TestExpense.removedMember]

    // A tombstone only carries a balance. Billing it is a 403, so a new expense must
    // neither default to it nor offer it.
    @Test func leavesRemovedMembersOutOfANewExpense() {
        let viewModel = ExpenseFormViewModel(
            groupId: 1,
            members: Self.membersWithRemoved,
            currentUserId: 1
        )

        #expect(viewModel.configuration == SplitConfiguration(payerId: 1, mode: .equal(participants: [1, 2, 3])))
        #expect(viewModel.payerChoices.map(\.userId) == [1, 2, 3])
        #expect(viewModel.participantChoices.map(\.userId) == [1, 2, 3])
        #expect(viewModel.splitSummary == "Paid by you and split equally")
    }

    @Test func keepsRemovedMembersOutOfTheEqualSplitAfterASwitch() {
        let viewModel = ExpenseFormViewModel(
            groupId: 1,
            members: Self.membersWithRemoved,
            currentUserId: 1
        )

        viewModel.selectMode(.custom)
        viewModel.selectMode(.equal)

        #expect(viewModel.configuration.mode == .equal(participants: [1, 2, 3]))
    }

    // The server decides whether an edit that keeps a removed member is allowed, so the
    // form shows the split rather than dropping it silently.
    @Test func showsARemovedMembersExistingSplitWhenEditing() {
        let removedId = TestExpense.removedMember.userId
        let expense = TestExpense.make(paidBy: 1, amount: 30, splitAmounts: [1: 15, removedId: 15])
        let viewModel = ExpenseFormViewModel(
            groupId: 1,
            members: Self.membersWithRemoved,
            currentUserId: 1,
            expense: expense
        )

        #expect(viewModel.participantChoices.map(\.userId) == [1, 2, 3, removedId])
        #expect(viewModel.payerChoices.map(\.userId) == [1, 2, 3])
        #expect(viewModel.isParticipant(removedId))
        #expect(viewModel.name(for: removedId) == "Removed member")
        #expect(viewModel.splits().map(\.userId) == [1, removedId])
    }

    @Test func namesARemovedPayerOnAnExistingExpense() {
        let removedId = TestExpense.removedMember.userId
        let expense = TestExpense.make(paidBy: removedId, amount: 30, splitAmounts: [1: 30])
        let viewModel = ExpenseFormViewModel(
            groupId: 1,
            members: Self.membersWithRemoved,
            currentUserId: 1,
            expense: expense
        )

        #expect(viewModel.name(for: removedId) == "Removed member")
        #expect(viewModel.splitSummary.contains("Removed member"))
        #expect(viewModel.payerChoices.map(\.userId) == [1, 2, 3])
    }
}
