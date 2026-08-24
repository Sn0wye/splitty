//
//  SplitConfigurationTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

struct SplitConfigurationTests {

    // MARK: - Equal division

    @Test func dividesEvenlyWhenItDivides() {
        let amounts = SplitConfiguration.equalAmounts(totalCents: 3000, among: [7, 3, 5])
        #expect(amounts == [3: 1000, 5: 1000, 7: 1000])
    }

    // Remainder cents go to the first participants by ascending user id: deterministic,
    // device-independent, and not biased toward whoever happened to pay.
    @Test func givesRemainderCentsToTheLowestUserIds() {
        let amounts = SplitConfiguration.equalAmounts(totalCents: 1000, among: [9, 2, 4])
        #expect(amounts == [2: 334, 4: 333, 9: 333])
        #expect(amounts.values.reduce(0, +) == 1000)
    }

    @Test func alwaysSumsToTheTotal() {
        for total in [1, 2, 7, 99, 100, 101, 1234, 99999] {
            for count in 1...7 {
                let ids = Array(1...count)
                let amounts = SplitConfiguration.equalAmounts(totalCents: total, among: ids)
                #expect(amounts.values.reduce(0, +) == total)
            }
        }
    }

    @Test func dividesNothingAmongNobody() {
        #expect(SplitConfiguration.equalAmounts(totalCents: 1000, among: []).isEmpty)
    }

    // MARK: - Payload

    @Test func buildsOneSplitPerParticipant() {
        let configuration = SplitConfiguration(payerId: 1, mode: .equal(participants: [1, 2]))
        let splits = configuration.splits(totalCents: 1000)
        #expect(splits.map(\.userId) == [1, 2])
        #expect(splits.map(\.amountCents) == [500, 500])
    }

    // The payer need not be a participant: "I paid, you all owe me" is a real expense, and
    // the API only requires the payer to be a group member.
    @Test func allowsAPayerWhoIsNotAParticipant() {
        let configuration = SplitConfiguration(payerId: 1, mode: .equal(participants: [2, 3]))
        let splits = configuration.splits(totalCents: 1000)
        #expect(splits.map(\.userId) == [2, 3])
    }

    // Splits must be greater than zero, so a member who would land on nothing is left out
    // of the array rather than sent as a zero the server rejects.
    @Test func omitsParticipantsWhoLandOnZeroCents() {
        let configuration = SplitConfiguration(payerId: 1, mode: .equal(participants: [1, 2, 3, 4, 5]))
        let splits = configuration.splits(totalCents: 3)
        #expect(splits.map(\.userId) == [1, 2, 3])
        #expect(splits.map(\.amountCents) == [1, 1, 1])
    }

    @Test func omitsCustomAmountsLeftAtZero() {
        let configuration = SplitConfiguration(payerId: 1, mode: .custom(amounts: [1: 0, 2: 1000]))
        #expect(configuration.splits(totalCents: 1000).map(\.userId) == [2])
    }

    // MARK: - Blocking save

    @Test func blocksAnAmountOfZero() {
        let configuration = SplitConfiguration(payerId: 1, mode: .equal(participants: [1, 2]))
        #expect(configuration.blockingReason(totalCents: 0) == .amountNotPositive)
    }

    // Unchecking everyone disables Save rather than sending an empty array.
    @Test func blocksWhenNobodyIsChecked() {
        let configuration = SplitConfiguration(payerId: 1, mode: .equal(participants: []))
        #expect(configuration.blockingReason(totalCents: 1000) == .noParticipants)
    }

    @Test func allowsAnEqualSplitWithAtLeastOneParticipant() {
        let configuration = SplitConfiguration(payerId: 1, mode: .equal(participants: [2]))
        #expect(configuration.blockingReason(totalCents: 1000) == nil)
    }

    @Test func blocksACustomSplitThatDoesNotReachTheTotal() {
        let configuration = SplitConfiguration(payerId: 1, mode: .custom(amounts: [1: 400, 2: 400]))
        #expect(configuration.blockingReason(totalCents: 1000) == .unassigned(cents: 200))
    }

    @Test func blocksACustomSplitThatOvershootsTheTotal() {
        let configuration = SplitConfiguration(payerId: 1, mode: .custom(amounts: [1: 900, 2: 400]))
        #expect(configuration.blockingReason(totalCents: 1000) == .unassigned(cents: -300))
    }

    @Test func allowsACustomSplitThatLandsExactly() {
        let configuration = SplitConfiguration(payerId: 1, mode: .custom(amounts: [1: 600, 2: 400]))
        #expect(configuration.blockingReason(totalCents: 1000) == nil)
    }

    @Test func blocksACustomSplitOfNothingButZeros() {
        let configuration = SplitConfiguration(payerId: 1, mode: .custom(amounts: [1: 0, 2: 0]))
        #expect(configuration.blockingReason(totalCents: 0) == .amountNotPositive)
    }

    // Changing the total after typing custom amounts keeps the typed numbers and reports
    // the shortfall. Rescaling would silently rewrite figures a person chose deliberately.
    @Test func keepsCustomAmountsWhenTheTotalChanges() {
        let configuration = SplitConfiguration(payerId: 1, mode: .custom(amounts: [1: 3000, 2: 3000]))
        #expect(configuration.blockingReason(totalCents: 6600) == .unassigned(cents: 600))
        #expect(configuration.amounts(totalCents: 6600) == [1: 3000, 2: 3000])
    }

    // MARK: - Inference from a stored expense

    @Test func readsAnEvenlyDividedExpenseAsEqual() {
        let expense = TestExpense.make(paidBy: 1, amount: 30, splitAmounts: [1: 10, 2: 10, 3: 10])
        let configuration = SplitConfiguration(inferredFrom: expense)
        #expect(configuration.payerId == 1)
        #expect(configuration.mode == .equal(participants: [1, 2, 3]))
    }

    // A remainder cent is still an equal split — the whole point of distributing it.
    @Test func readsARemainderCentAsEqual() {
        let expense = TestExpense.make(paidBy: 2, amount: 10, splitAmounts: [1: 3.34, 2: 3.33, 3: 3.33])
        #expect(SplitConfiguration(inferredFrom: expense).mode == .equal(participants: [1, 2, 3]))
    }

    @Test func readsUnevenAmountsAsCustom() {
        let expense = TestExpense.make(paidBy: 1, amount: 30, splitAmounts: [1: 20, 2: 10])
        #expect(SplitConfiguration(inferredFrom: expense).mode == .custom(amounts: [1: 2000, 2: 1000]))
    }

    @Test func readsASingleSplitAsEqual() {
        let expense = TestExpense.make(paidBy: 1, amount: 30, splitAmounts: [2: 30])
        #expect(SplitConfiguration(inferredFrom: expense).mode == .equal(participants: [2]))
    }

    // MARK: - Percentage division

    @Test func dividesByPercentage() {
        let amounts = SplitConfiguration.percentageAmounts(
            totalCents: 10000,
            percentages: [1: 70, 2: 30]
        )
        #expect(amounts == [1: 7000, 2: 3000])
    }

    // Every share is floored and the leftover cents handed out one each by ascending user
    // id — the same rule the equal split uses, so the two never disagree about who is owed
    // the odd cent.
    @Test func givesLeftoverCentsToTheLowestUserIds() {
        let amounts = SplitConfiguration.percentageAmounts(
            totalCents: 1000,
            percentages: [9: 33.34, 2: 33.33, 4: 33.33]
        )
        #expect(amounts == [2: 334, 4: 333, 9: 333])
        #expect(amounts.values.reduce(0, +) == 1000)
    }

    @Test func percentagesAlwaysSumToTheTotal() {
        for total in [1, 2, 7, 99, 100, 101, 1234, 99999] {
            let amounts = SplitConfiguration.percentageAmounts(
                totalCents: total,
                percentages: [1: 33.33, 2: 33.33, 3: 33.34]
            )
            #expect(amounts.values.reduce(0, +) == total)
        }
    }

    // A blank field is not a participant, so a share of zero gets no row at all.
    @Test func leavesOutAShareOfZero() {
        let amounts = SplitConfiguration.percentageAmounts(totalCents: 10000, percentages: [1: 100, 2: 0])
        #expect(amounts == [1: 10000])
    }

    // Unlike a custom split, a percentage one re-derives: the shares are still true of the
    // new total, which is the reason to type them rather than amounts.
    @Test func rederivesPercentagesWhenTheTotalChanges() {
        let configuration = SplitConfiguration(payerId: 1, mode: .percentage(percentages: [1: 70, 2: 30]))
        #expect(configuration.amounts(totalCents: 10000) == [1: 7000, 2: 3000])
        #expect(configuration.amounts(totalCents: 5000) == [1: 3500, 2: 1500])
        #expect(configuration.blockingReason(totalCents: 5000) == nil)
    }

    @Test func sendsThePercentageAlongsideTheAmount() {
        let configuration = SplitConfiguration(payerId: 1, mode: .percentage(percentages: [1: 70, 2: 30]))
        let splits = configuration.splits(totalCents: 10000)
        #expect(splits.map(\.amountCents) == [7000, 3000])
        #expect(splits.map(\.percentage) == [70, 30])
    }

    // Only a percentage split carries them: the API nulls a percentage sent under any
    // other mode, and sending one would claim a share nobody typed.
    @Test func sendsNoPercentageUnderAnyOtherMode() {
        let configuration = SplitConfiguration(payerId: 1, mode: .equal(participants: [1, 2]))
        #expect(configuration.splits(totalCents: 1000).allSatisfy { $0.percentage == nil })
    }

    // MARK: - Blocking a percentage split

    @Test func blocksPercentagesThatFallShortOfAHundred() {
        let configuration = SplitConfiguration(payerId: 1, mode: .percentage(percentages: [1: 50, 2: 30]))
        #expect(configuration.blockingReason(totalCents: 10000) == .unassignedPercent(20))
    }

    @Test func blocksPercentagesThatOvershootAHundred() {
        let configuration = SplitConfiguration(payerId: 1, mode: .percentage(percentages: [1: 80, 2: 30]))
        #expect(configuration.blockingReason(totalCents: 10000) == .unassignedPercent(-10))
    }

    @Test func blocksAPercentageSplitWithNothingTyped() {
        let configuration = SplitConfiguration(payerId: 1, mode: .percentage(percentages: [:]))
        #expect(configuration.blockingReason(totalCents: 10000) == .noParticipants)
    }

    // 0.4% of $1.00 floors to nothing, and the API rejects a split that is not greater
    // than zero — on grounds the person typing "0.4" cannot see.
    @Test func blocksAShareThatRoundsDownToNothing() {
        let configuration = SplitConfiguration(
            payerId: 1,
            mode: .percentage(percentages: [1: 99.6, 2: 0.4])
        )
        #expect(configuration.blockingReason(totalCents: 100) == .percentageRoundsToZero(userId: 2))
    }

    // The same share of a bigger total is a real cent, so nothing blocks.
    @Test func allowsASmallShareOfALargeTotal() {
        let configuration = SplitConfiguration(
            payerId: 1,
            mode: .percentage(percentages: [1: 99.6, 2: 0.4])
        )
        #expect(configuration.blockingReason(totalCents: 100000) == nil)
    }

    // Checked against the derived amounts rather than the raw share: a share that floors
    // to nothing may still be handed a leftover cent, and then it is a real row.
    @Test func allowsAFlooredShareThatCatchesALeftoverCent() {
        let configuration = SplitConfiguration(
            payerId: 1,
            mode: .percentage(percentages: [1: 0.5, 2: 99.5])
        )
        #expect(configuration.amounts(totalCents: 100) == [1: 1, 2: 99])
        #expect(configuration.blockingReason(totalCents: 100) == nil)
    }

    // MARK: - Restoring a stored mode

    @Test func restoresAStoredPercentageSplit() {
        let expense = TestExpense.make(
            paidBy: 1,
            amount: 100,
            splitAmounts: [1: 70, 2: 30],
            splitMode: .percentage,
            percentages: [1: 70, 2: 30]
        )
        let configuration = SplitConfiguration(restoredFrom: expense)
        #expect(configuration.mode == .percentage(percentages: [1: 70, 2: 30]))
    }

    // The stored mode is what says how to read the rows: an evenly divided expense the
    // user typed by hand reopens as custom, not as the equal split the numbers resemble.
    @Test func restoresAStoredCustomSplitThatLooksEqual() {
        let expense = TestExpense.make(
            paidBy: 1,
            amount: 60,
            splitAmounts: [1: 30, 2: 30],
            splitMode: .custom
        )
        #expect(SplitConfiguration(restoredFrom: expense).mode == .custom(amounts: [1: 3000, 2: 3000]))
    }

    @Test func restoresAStoredEqualSplit() {
        let expense = TestExpense.make(
            paidBy: 1,
            amount: 60,
            splitAmounts: [1: 40, 2: 20],
            splitMode: .equal
        )
        #expect(SplitConfiguration(restoredFrom: expense).mode == .equal(participants: [1, 2]))
    }

    // A row with no mode — a settlement, or one written before the column existed — falls
    // back to inference, which keeps the stored amounts either way.
    @Test func fallsBackToInferenceWithoutAMode() {
        let expense = TestExpense.make(paidBy: 1, amount: 60, splitAmounts: [1: 40, 2: 20])
        #expect(SplitConfiguration(restoredFrom: expense).mode == .custom(amounts: [1: 4000, 2: 2000]))
    }

    // A mode this build does not recognise decodes as nil rather than throwing, so the row
    // is still readable — one unknown value must not fail a whole group's expense list.
    @Test func readsAnUnknownModeAsNoMode() throws {
        let json = """
        {"id":1,"groupId":1,"paidBy":1,"amount":60,"description":"Dinner","type":"expense",
         "splitMode":"shares","createdAt":"2026-08-20T12:00:00Z","updatedAt":"2026-08-20T12:00:00Z",
         "paidByUser":{"id":1,"name":"Alice","email":"alice@example.com","createdAt":"","updatedAt":""},
         "splits":[{"id":1,"expenseId":1,"userId":1,"amount":40,
                    "user":{"id":1,"name":"Alice","email":"alice@example.com","createdAt":"","updatedAt":""}},
                   {"id":2,"expenseId":1,"userId":2,"amount":20,
                    "user":{"id":2,"name":"Bob","email":"bob@example.com","createdAt":"","updatedAt":""}}]}
        """
        let expense = try JSONDecoder().decode(Expense.self, from: Data(json.utf8))

        #expect(expense.splitMode == nil)
        #expect(SplitConfiguration(restoredFrom: expense).mode == .custom(amounts: [1: 4000, 2: 2000]))
    }

    // MARK: - Summary line

    @Test func summarisesTheDefault() {
        let configuration = SplitConfiguration(payerId: 1, mode: .equal(participants: [1, 2, 3]))
        #expect(configuration.summary(members: TestExpense.members, currentUserId: 1)
                == "Paid by you and split equally")
    }

    @Test func namesAnotherPayer() {
        let configuration = SplitConfiguration(payerId: 2, mode: .equal(participants: [1, 2, 3]))
        #expect(configuration.summary(members: TestExpense.members, currentUserId: 1)
                == "Paid by Bob and split equally")
    }

    @Test func summarisesAPartialEqualSplit() {
        let configuration = SplitConfiguration(payerId: 1, mode: .equal(participants: [1, 2]))
        #expect(configuration.summary(members: TestExpense.members, currentUserId: 1)
                == "Paid by you and split equally between 2 people")
    }

    @Test func summarisesOneOtherPersonOwingEverything() {
        let configuration = SplitConfiguration(payerId: 1, mode: .equal(participants: [2]))
        #expect(configuration.summary(members: TestExpense.members, currentUserId: 1)
                == "Paid by you, Bob owes the full amount")
    }

    @Test func summarisesYouOwingEverything() {
        let configuration = SplitConfiguration(payerId: 2, mode: .equal(participants: [1]))
        #expect(configuration.summary(members: TestExpense.members, currentUserId: 1)
                == "Paid by Bob, you owe the full amount")
    }

    @Test func summarisesAPercentageSplit() {
        let configuration = SplitConfiguration(payerId: 1, mode: .percentage(percentages: [1: 70, 2: 30]))
        #expect(configuration.summary(members: TestExpense.members, currentUserId: 1)
                == "Paid by you and split by percentages")
    }

    // Leaving the split screen at 80% is allowed; Save is what refuses, and the line says
    // what Save will not.
    @Test func summarisesAnIncompletePercentageSplit() {
        let configuration = SplitConfiguration(payerId: 1, mode: .percentage(percentages: [1: 50, 2: 30]))
        #expect(configuration.summary(members: TestExpense.members, currentUserId: 1)
                == "Paid by you, 20% left to assign")
    }

    @Test func summarisesACustomSplit() {
        let configuration = SplitConfiguration(payerId: 1, mode: .custom(amounts: [1: 600, 2: 400]))
        #expect(configuration.summary(members: TestExpense.members, currentUserId: 1)
                == "Paid by you and split by amounts")
    }
}

// MARK: - Fixtures

enum TestExpense {
    static let members = [
        GroupMember(id: 11, userId: 1, name: "Alice", email: "alice@example.com", avatarUrl: ""),
        GroupMember(id: 12, userId: 2, name: "Bob", email: "bob@example.com", avatarUrl: ""),
        GroupMember(id: 13, userId: 3, name: "Cara", email: "cara@example.com", avatarUrl: "")
    ]

    static func user(_ id: Int) -> User {
        User(id: id, name: "User \(id)", email: "user\(id)@example.com", createdAt: "", updatedAt: "")
    }

    static func make(
        id: Int = 1,
        paidBy: Int,
        amount: Double,
        splitAmounts: [Int: Double],
        splitMode: ExpenseSplitMode? = nil,
        percentages: [Int: Double] = [:],
        type: ExpenseType = .expense,
        date: String? = nil
    ) -> Expense {
        Expense(
            id: id,
            groupId: 1,
            paidBy: paidBy,
            amount: amount,
            description: "Dinner",
            type: type,
            splitMode: splitMode,
            date: date,
            createdAt: "2026-08-20T12:00:00Z",
            updatedAt: "2026-08-20T12:00:00Z",
            paidByUser: user(paidBy),
            splits: splitAmounts.sorted { $0.key < $1.key }.enumerated().map { index, entry in
                ExpenseSplit(
                    id: index + 1,
                    expenseId: id,
                    userId: entry.key,
                    amount: entry.value,
                    percentage: percentages[entry.key],
                    user: user(entry.key)
                )
            }
        )
    }
}
