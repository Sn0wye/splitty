import Foundation
import Testing
@testable import Splitty

@MainActor
struct SettleUpViewModelTests {
    @Test func preselectingYourSimplifiedDebtPrefillsPayeeAndAmount() async {
        let session = await makeSession(summary([debt(from: 1, to: 2, cents: 2_350)]))
        let row = BalanceRow(from: DebtMember(id: 1, name: "You", avatarUrl: ""),
                             to: DebtMember(id: 2, name: "Bob", avatarUrl: ""),
                             amountCents: 2_350, involvement: .youPay)
        let model = SettleUpViewModel(session: session, currentUserId: 1, preselectedRow: row)
        #expect(model.selectedPeer?.userId == 2)
        #expect(model.amountCents == 2_350)
        #expect(model.payAllTitle?.contains("$23.50") == true)
    }

    @Test func loadingSummaryPrefillsTheCurrentUsersSuggestedPayment() async {
        let session = await makeSession(summary([
            debt(from: 3, to: 2, cents: 7_000), debt(from: 1, to: 2, cents: 2_350)
        ]))
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        await model.loadDebts()
        #expect(model.selectedPeer?.userId == 2)
        #expect(model.amountCents == 2_350)
    }

    @Test func onlyPeersOwedByTheGroupArePayable() async {
        let session = await makeSession(summary([
            debt(from: 1, to: 2, cents: 1_200), debt(from: 2, to: 3, cents: 700)
        ]), members: members + [GroupMember(id: 30, userId: 3, name: "Cara", email: "cara@example.com", avatarUrl: "")])
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        #expect(model.peers.map(\.userId) == [2, 3])
    }

    @Test func pendingSessionCannotBeSubmittedAndSettledRefreshPrefillsThePayment() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.cancelBalanceRetry = true
        data.summaryForCall = { call in
            GroupBalanceSummary(simplifiedDebts: [self.debt(from: 1, to: 2, cents: call == 1 ? 1_200 : 900)],
                                balancesPending: call == 1)
        }
        let session = GroupSession(groupId: 7, seed: group(), dataSource: data.source())
        await session.appear().value
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        model.suggestPayment()
        #expect(!model.canSubmit)
        #expect(model.selectedPeer?.userId == 2)

        await session.refresh()
        // No summary or pending value is copied into the screen model.
        #expect(!model.balancesPending)
        #expect(model.debtCents(for: 2) == 900)
        model.suggestPayment()
        #expect(model.amountCents == 900)
        #expect(model.canSubmit)
        session.discard()
    }

    @Test(arguments: [nil, 0])
    func payAllIsHiddenWhenDebtIsUnknownOrZero(debtCents: Int?) async {
        var debts = [debt(from: 3, to: 2, cents: 700)]
        if let debtCents { debts.append(debt(from: 1, to: 2, cents: debtCents)) }
        let session = await makeSession(summary(debts))
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        model.select(peerId: 2)
        #expect(model.payAllTitle == nil)
    }

    @Test func payAllShowsTheKnownDebt() async {
        let model = await makeViewModel(summary([debt(from: 1, to: 2, cents: 1_200)]))
        #expect(model.payAllTitle?.contains("$12.00") == true)
    }

    @Test func duplicateBalanceRowsKeepTheLargestDebtInsteadOfCrashing() async {
        let model = await makeViewModel(summary([
            debt(from: 1, to: 2, cents: 1_200), debt(from: 1, to: 2, cents: 2_350)
        ]))
        #expect(model.debtCents(for: 2) == 2_350)
    }

    @Test func rejectionNamesTheKnownLowerDebt() async {
        let model = await makeViewModel(summary([debt(from: 1, to: 2, cents: 1_200)]))
        model.amount.replaceEntry(cents: 1_201)
        model.recordSubmissionFailure(TestError())
        #expect(model.errorMessage == L10n.Settlement.onlyOwe("Bob", "$12.00"))
    }

    @Test func rejectionIsGenericWithoutAConflictingKnownDebt() async {
        let model = await makeViewModel(summary([debt(from: 3, to: 2, cents: 700)]))
        model.select(peerId: 2)
        model.amount.replaceEntry(cents: 1_200)
        model.recordSubmissionFailure(TestError())
        #expect(model.errorMessage == L10n.Settlement.recordFailed)
    }

    @Test func editingAlwaysUsesTheGenericRejection() async {
        let session = await makeSession(summary([debt(from: 1, to: 2, cents: 1)]))
        let settlement = TestExpense.make(id: 18, paidBy: 1, amount: 12, splitAmounts: [1: 12, 2: -12],
                                          type: .payment, date: "2026-03-01T12:00:00Z")
        let model = SettleUpViewModel(session: session, currentUserId: 1, settlement: settlement)
        model.recordSubmissionFailure(TestError())
        #expect(model.date == Expense.parseTimestamp("2026-03-01T12:00:00Z"))
        #expect(model.errorMessage == L10n.Settlement.recordFailed)
    }

    @Test func aServerRejectionProducesARetryableError() async {
        let session = await makeSession(summary([debt(from: 3, to: 2, cents: 700)]))
        let model = SettleUpViewModel(session: session, currentUserId: 1,
            dataSource: SettleUpDataSource(create: { _, _, _, _ in throw APIError.httpError(400, message: nil) },
                                         update: { _, _, _, _ in }))
        model.select(peerId: 2)
        model.amount.replaceEntry(cents: 1_200)
        let result = await model.submit()
        #expect(result == nil)
        #expect(model.errorMessage == L10n.Settlement.recordFailed)
    }

    private func makeViewModel(_ summary: GroupBalanceSummary) async -> SettleUpViewModel {
        let model = SettleUpViewModel(session: await makeSession(summary), currentUserId: 1)
        model.suggestPayment()
        return model
    }

    private func makeSession(_ summary: GroupBalanceSummary, members: [GroupMember]? = nil) async -> GroupSession {
        let data = ControlledGroupData()
        data.summaryForCall = { _ in summary }
        data.cancelBalanceRetry = true
        let session = GroupSession(groupId: 7, seed: group(members: members), dataSource: data.source())
        _ = try? await session.readSummary()
        return session
    }

    private func group(members: [GroupMember]? = nil) -> Group {
        Group(id: 7, name: "Trip", description: nil, netBalanceCents: -5_000, createdAt: "2026-01-01",
              members: members ?? self.members)
    }

    private func summary(_ debts: [SimplifiedDebt]) -> GroupBalanceSummary {
        GroupBalanceSummary(simplifiedDebts: debts, balancesPending: false)
    }

    private func debt(from: Int, to: Int, cents: Int) -> SimplifiedDebt {
        SimplifiedDebt(from: DebtMember(id: from, name: from == 1 ? "You" : "Member \(from)", avatarUrl: ""),
                       to: DebtMember(id: to, name: to == 2 ? "Bob" : "Member \(to)", avatarUrl: ""), amountCents: cents)
    }

    private var members: [GroupMember] {
        [GroupMember(id: 10, userId: 1, name: "You", email: "you@example.com", avatarUrl: ""),
         GroupMember(id: 20, userId: 2, name: "Bob", email: "bob@example.com", avatarUrl: "")]
    }
}

private struct TestError: Error {}
