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

    // MARK: - Presets

    @Test func offersTheFullAmountPresetsOnlyToTwoPersonGroups() {
        let pair = SplitPreset.available(memberIds: [1, 2], currentUserId: 1)
        #expect(pair.contains(.youPaidTheyOweFull))
        #expect(pair.contains(.theyPaidYouOweFull))

        let trio = SplitPreset.available(memberIds: [1, 2, 3], currentUserId: 1)
        #expect(!trio.contains(.youPaidTheyOweFull))
        #expect(!trio.contains(.theyPaidYouOweFull))
        #expect(trio == [.youPaidSplitEqually, .someoneElsePaidSplitEqually, .custom])
    }

    @Test func youPaidSplitEquallyPaysAndParticipates() {
        let configuration = SplitPreset.youPaidSplitEqually.configuration(memberIds: [1, 2, 3], currentUserId: 2)
        #expect(configuration == SplitConfiguration(payerId: 2, mode: .equal(participants: [1, 2, 3])))
    }

    @Test func youPaidTheyOweTheFullAmountLeavesYouOutOfTheSplits() {
        let configuration = SplitPreset.youPaidTheyOweFull.configuration(memberIds: [1, 2], currentUserId: 1)
        #expect(configuration == SplitConfiguration(payerId: 1, mode: .equal(participants: [2])))
    }

    @Test func theyPaidYouOweTheFullAmountPutsThePayerOutOfTheSplits() {
        let configuration = SplitPreset.theyPaidYouOweFull.configuration(memberIds: [1, 2], currentUserId: 1)
        #expect(configuration == SplitConfiguration(payerId: 2, mode: .equal(participants: [1])))
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
            date: date,
            createdAt: "2026-08-20T12:00:00Z",
            updatedAt: "2026-08-20T12:00:00Z",
            paidByUser: user(paidBy),
            splits: splitAmounts.sorted { $0.key < $1.key }.enumerated().map { index, entry in
                ExpenseSplit(id: index + 1, expenseId: id, userId: entry.key, amount: entry.value, user: user(entry.key))
            }
        )
    }
}
