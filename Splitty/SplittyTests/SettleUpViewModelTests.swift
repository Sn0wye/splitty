//
//  SettleUpViewModelTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

@MainActor
struct SettleUpViewModelTests {
    @Test func preselectingABalanceRowStillStartsAtZero() {
        let row = BalanceRow(
            peerId: 2,
            peerName: "Bob",
            peerAvatarURL: nil,
            amountCents: -2_350,
            direction: .youOwe
        )

        let viewModel = SettleUpViewModel(
            groupId: 7,
            members: members,
            currentUserId: 1,
            preselectedRow: row
        )

        #expect(viewModel.selectedPeer?.userId == 2)
        #expect(viewModel.amountCents == 0)
        #expect(viewModel.payAllTitle == "Pay all $23.50")
    }

    @Test(arguments: [nil, 0])
    func payAllIsHiddenWhenDebtIsUnknownOrZero(debtCents: Int?) {
        let viewModel = makeViewModel()
        viewModel.select(peerId: 2)
        viewModel.setDebt(debtCents, for: 2)

        #expect(viewModel.payAllTitle == nil)
    }

    @Test func payAllShowsTheKnownDebt() {
        let viewModel = makeViewModel()
        viewModel.select(peerId: 2)
        viewModel.setDebt(1_200, for: 2)

        #expect(viewModel.payAllTitle == "Pay all $12.00")
    }

    @Test func duplicateBalanceRowsKeepTheLargestDebtInsteadOfCrashing() {
        let viewModel = makeViewModel()
        viewModel.apply(GroupBalanceSummary(
            balances: [
                balance(peerId: 2, cents: -1_200),
                balance(peerId: 2, cents: -2_350)
            ],
            balancesPending: false
        ))

        #expect(viewModel.debtCents(for: 2) == 2_350)
    }

    @Test func rejectionNamesTheKnownLowerDebt() {
        let viewModel = makeViewModel()
        viewModel.select(peerId: 2)
        viewModel.setDebt(1_200, for: 2)
        viewModel.amount.replaceEntry(cents: 1_201)

        viewModel.recordSubmissionFailure(TestError())

        #expect(viewModel.errorMessage == "You only owe Bob $12.00.")
    }

    @Test func rejectionIsGenericWithoutAConflictingKnownDebt() {
        let viewModel = makeViewModel()
        viewModel.select(peerId: 2)
        viewModel.amount.replaceEntry(cents: 1_200)

        viewModel.recordSubmissionFailure(TestError())

        #expect(viewModel.errorMessage == "Couldn't record that payment. Pull down to refresh and try again.")
    }

    @Test func editingAlwaysUsesTheGenericRejection() {
        let settlement = TestExpense.make(
            id: 18,
            paidBy: 1,
            amount: 12,
            splitAmounts: [1: 12, 2: -12],
            type: .payment,
            date: "2026-03-01T12:00:00Z"
        )
        let viewModel = SettleUpViewModel(
            groupId: 7,
            members: members,
            currentUserId: 1,
            settlement: settlement
        )
        viewModel.setDebt(1, for: 2)

        viewModel.recordSubmissionFailure(TestError())

        #expect(viewModel.date == Expense.parseTimestamp("2026-03-01T12:00:00Z"))
        #expect(viewModel.errorMessage == "Couldn't record that payment. Pull down to refresh and try again.")
    }

    @Test func pendingPaymentUsesTheSelectedDate() throws {
        let viewModel = GroupViewModel()
        let selectedDate = try #require(Expense.parseTimestamp("2026-03-01T12:00:00Z"))

        let payment = viewModel.insertPendingPayment(
            groupId: 7,
            currentUser: members[0],
            peer: members[1],
            amountCents: 2_350,
            date: selectedDate
        )

        #expect(payment.date == "2026-03-01T12:00:00Z")
        #expect(payment.effectiveDate == selectedDate)
    }

    @Test func fabricatedPaymentLandsInTodaysGroupAndCannotBeOpened() throws {
        let viewModel = GroupViewModel()
        viewModel.group = Group(
            id: 7,
            name: "Trip",
            description: nil,
            netBalanceCents: -5_000,
            createdAt: "2026-01-01",
            members: members
        )
        let now = try #require(Expense.parseTimestamp("2026-09-10T12:00:00Z"))

        let payment = viewModel.insertPendingPayment(
            groupId: 7,
            currentUser: members[0],
            peer: members[1],
            amountCents: 2_350,
            now: now
        )

        #expect(viewModel.groupedExpenses.count == 1)
        #expect(viewModel.groupedExpenses[0].expenses.map(\.id) == [payment.id])
        #expect(viewModel.groupedExpenses[0].date == Calendar.current.startOfDay(for: now))
        #expect(viewModel.isPendingPayment(payment))
        #expect(viewModel.group?.netBalanceCents == -2_650)
        #expect(viewModel.balancesPending)
    }

    private func makeViewModel() -> SettleUpViewModel {
        SettleUpViewModel(groupId: 7, members: members, currentUserId: 1)
    }

    private func balance(peerId: Int, cents: Int) -> Balance {
        Balance(
            userId: 1,
            peerId: peerId,
            amountCents: cents,
            user: User(id: 1, name: "You", email: "you@example.com", createdAt: "", updatedAt: ""),
            peer: User(id: peerId, name: "Bob", email: "bob@example.com", createdAt: "", updatedAt: "")
        )
    }

    private var members: [GroupMember] {
        [
            GroupMember(id: 10, userId: 1, name: "You", email: "you@example.com", avatarUrl: ""),
            GroupMember(id: 20, userId: 2, name: "Bob", email: "bob@example.com", avatarUrl: "")
        ]
    }
}

private struct TestError: Error {}
