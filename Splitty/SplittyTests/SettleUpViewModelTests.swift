//
//  SettleUpViewModelTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

@MainActor
struct SettleUpViewModelTests {
    @Test func preselectingYourSimplifiedDebtPrefillsPayeeAndAmount() {
        let row = BalanceRow(
            from: DebtMember(id: 1, name: "You", avatarUrl: ""),
            to: DebtMember(id: 2, name: "Bob", avatarUrl: ""),
            amountCents: 2_350,
            involvement: .youPay
        )

        let viewModel = SettleUpViewModel(
            groupId: 7,
            members: members,
            currentUserId: 1,
            preselectedRow: row
        )

        #expect(viewModel.selectedPeer?.userId == 2)
        #expect(viewModel.amountCents == 2_350)
        #expect(viewModel.payAllTitle == "Pay all $23.50")
    }

    @Test func loadingSummaryPrefillsTheCurrentUsersSuggestedPayment() async {
        let response = summary([
            debt(from: 3, to: 2, cents: 7_000),
            debt(from: 1, to: 2, cents: 2_350)
        ])
        let viewModel = SettleUpViewModel(
            groupId: 7,
            members: members,
            currentUserId: 1,
            dataSource: SettleUpDataSource(
                summary: { _ in response },
                create: { _, _, _, _ in },
                update: { _, _, _, _ in }
            )
        )

        await viewModel.loadDebts()

        #expect(viewModel.selectedPeer?.userId == 2)
        #expect(viewModel.amountCents == 2_350)
    }

    @Test func onlyPeersOwedByTheGroupArePayable() {
        let viewModel = makeViewModel(members: members + [
            GroupMember(id: 30, userId: 3, name: "Cara", email: "cara@example.com", avatarUrl: "")
        ])
        viewModel.apply(summary([
            debt(from: 1, to: 2, cents: 1_200),
            debt(from: 2, to: 3, cents: 700)
        ]))

        #expect(viewModel.peers.map(\.userId) == [2, 3])
    }

    @Test func pendingSummaryCannotBeSubmittedAndSettledRefreshPrefillsThePayment() {
        let viewModel = makeViewModel()
        viewModel.apply(GroupBalanceSummary(
            simplifiedDebts: [debt(from: 1, to: 2, cents: 1_200)],
            balancesPending: true
        ))

        #expect(viewModel.balancesPending)
        #expect(!viewModel.canSubmit)
        #expect(viewModel.selectedPeer == nil)

        viewModel.apply(summary([debt(from: 1, to: 2, cents: 900)]))

        #expect(!viewModel.balancesPending)
        #expect(viewModel.selectedPeer?.userId == 2)
        #expect(viewModel.amountCents == 900)
        #expect(viewModel.canSubmit)
    }

    @Test(arguments: [nil, 0])
    func payAllIsHiddenWhenDebtIsUnknownOrZero(debtCents: Int?) {
        let viewModel = makeViewModel()
        viewModel.apply(summary([debt(from: 3, to: 2, cents: 700)]))
        viewModel.select(peerId: 2)
        viewModel.setDebt(debtCents, for: 2)

        #expect(viewModel.payAllTitle == nil)
    }

    @Test func payAllShowsTheKnownDebt() {
        let viewModel = makeViewModel()
        viewModel.apply(summary([debt(from: 1, to: 2, cents: 1_200)]))

        #expect(viewModel.payAllTitle == "Pay all $12.00")
    }

    @Test func duplicateBalanceRowsKeepTheLargestDebtInsteadOfCrashing() {
        let viewModel = makeViewModel()
        viewModel.apply(summary([
            debt(from: 1, to: 2, cents: 1_200),
            debt(from: 1, to: 2, cents: 2_350)
        ]))

        #expect(viewModel.debtCents(for: 2) == 2_350)
    }

    @Test func rejectionNamesTheKnownLowerDebt() {
        let viewModel = makeViewModel()
        viewModel.apply(summary([debt(from: 1, to: 2, cents: 1_200)]))
        viewModel.amount.replaceEntry(cents: 1_201)

        viewModel.recordSubmissionFailure(TestError())

        #expect(viewModel.errorMessage == "You only owe Bob $12.00.")
    }

    @Test func rejectionIsGenericWithoutAConflictingKnownDebt() {
        let viewModel = makeViewModel()
        viewModel.apply(summary([debt(from: 3, to: 2, cents: 700)]))
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

    @Test func aServerRejectionProducesARetryableError() async {
        let viewModel = SettleUpViewModel(
            groupId: 7,
            members: members,
            currentUserId: 1,
            dataSource: SettleUpDataSource(
                summary: { _ in self.summary([]) },
                create: { _, _, _, _ in throw APIError.httpError(400, message: nil) },
                update: { _, _, _, _ in }
            )
        )
        viewModel.apply(summary([debt(from: 3, to: 2, cents: 700)]))
        viewModel.select(peerId: 2)
        viewModel.amount.replaceEntry(cents: 1_200)

        let result = await viewModel.submit()

        #expect(result == nil)
        #expect(viewModel.errorMessage == "Couldn't record that payment. Pull down to refresh and try again.")
    }

    private func makeViewModel(members: [GroupMember]? = nil) -> SettleUpViewModel {
        SettleUpViewModel(groupId: 7, members: members ?? self.members, currentUserId: 1)
    }

    private func summary(_ debts: [SimplifiedDebt]) -> GroupBalanceSummary {
        GroupBalanceSummary(simplifiedDebts: debts, balancesPending: false)
    }

    private func debt(from: Int, to: Int, cents: Int) -> SimplifiedDebt {
        SimplifiedDebt(
            from: DebtMember(id: from, name: from == 1 ? "You" : "Member \(from)", avatarUrl: ""),
            to: DebtMember(id: to, name: to == 2 ? "Bob" : "Member \(to)", avatarUrl: ""),
            amountCents: cents,
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
