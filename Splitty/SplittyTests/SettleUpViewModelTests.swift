import Foundation
import Testing
@testable import Splitty

@MainActor
@Suite(.appLanguage(.english))
struct SettleUpViewModelTests {
    @Test func preselectingYourSimplifiedDebtPrefillsBothSidesButNotTheAmount() async {
        let session = await makeSession(summary([debt(from: 1, to: 2, cents: 2_350)]))
        let row = BalanceRow(from: DebtMember(id: 1, name: "You", avatarUrl: ""),
                             to: DebtMember(id: 2, name: "Bob", avatarUrl: ""),
                             amountCents: 2_350, involvement: .youPay)
        let model = SettleUpViewModel(session: session, currentUserId: 1, preselectedRow: row)
        #expect(model.payerId == 1)
        #expect(model.payeeId == 2)
        #expect(model.amountCents == 0)
        #expect(model.payAllTitle == L10n.Settlement.payAll("$23.50"))
    }

    @Test func loadingSummarySuggestsYourOwnDebtButNotTheAmount() async {
        let session = await makeSession(summary([
            debt(from: 3, to: 2, cents: 7_000), debt(from: 1, to: 2, cents: 2_350)
        ]), members: members + [cara])
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        await model.loadDebts()
        #expect(model.payerId == 1)
        #expect(model.payeeId == 2)
        #expect(model.amountCents == 0)
    }

    @Test func aCreditorIsSuggestedTheirLargestDebtorPayingThem() async {
        let session = await makeSession(summary([
            debt(from: 3, to: 2, cents: 7_000), debt(from: 2, to: 1, cents: 300), debt(from: 3, to: 1, cents: 500)
        ]), members: members + [cara])
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        model.suggestPayment()
        #expect(model.payerId == 3)
        #expect(model.payeeId == 1)
        #expect(model.payAllTitle == L10n.Settlement.fullAmount("$5.00"))
    }

    @Test func aSettledMemberIsSuggestedSomeoneElsesDebt() async {
        let session = await makeSession(summary([debt(from: 2, to: 3, cents: 700)]), members: members + [cara])
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        model.suggestPayment()
        #expect(model.payerId == 2)
        #expect(model.payeeId == 3)
    }

    @Test func aSettledGroupSuggestsYouPayingSomeoneWithNothingToFill() async {
        let model = await makeViewModel(summary([]))
        #expect(model.payerId == 1)
        #expect(model.payeeId == 2)
        #expect(model.payAllTitle == nil)
    }

    @Test func aLaterSuggestionKeepsTheSidesTheMemberPicked() async {
        let session = await makeSession(summary([debt(from: 1, to: 2, cents: 1_200)]), members: members + [cara])
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        model.suggestPayment()
        model.setPayer(3)
        model.suggestPayment()
        #expect(model.payerId == 3)
        #expect(model.payeeId == 2)
    }

    @Test func pickingThePayeeAsPayerSwapsTheSides() async {
        let model = await makeViewModel(summary([debt(from: 1, to: 2, cents: 1_200)]))
        model.setPayer(2)
        #expect(model.payerId == 2)
        #expect(model.payeeId == 1)
        model.setPayee(2)
        #expect(model.payerId == 1)
        #expect(model.payeeId == 2)
        model.swapParties()
        #expect(model.payerId == 2)
        #expect(model.payeeId == 1)
    }

    @Test func theChoicesListYouFirst() async {
        let session = await makeSession(summary([]), members: [cara] + members)
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        #expect(model.choices.map(\.userId) == [1, 2, 3])
        #expect(model.name(of: members[0]) == L10n.Common.you)
    }

    @Test func theFullAmountNeverPassesTheServersCap() async {
        // You owe Bob $12.00 and Cara owes Bob $7.00. Paying Cara is capped at zero: she
        // is owed nothing. Cara paying you is capped at zero too: you are owed nothing.
        let session = await makeSession(summary([
            debt(from: 1, to: 2, cents: 1_200), debt(from: 3, to: 2, cents: 700)
        ]), members: members + [cara])
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        model.suggestPayment()
        #expect(model.capCents == 1_200)
        model.setPayee(3)
        #expect(model.capCents == 0)
        #expect(model.payAllTitle == nil)
        model.swapParties()
        #expect(model.capCents == 0)
        model.setPayee(2)
        #expect(model.capCents == 700)
        #expect(model.payAllTitle == L10n.Settlement.fullAmount("$7.00"))
    }

    @Test func theFullAmountIsTheSuggestedPairEvenWhenTheCapIsHigher() async {
        // You are owed $8.00 in all, $5.00 of it by Cara: Full amount fills $5.00, the
        // debt Balances shows, though the server would take up to $8.00.
        let session = await makeSession(summary([
            debt(from: 3, to: 1, cents: 500), debt(from: 2, to: 1, cents: 300), debt(from: 3, to: 2, cents: 7_000)
        ]), members: members + [cara])
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        model.suggestPayment()
        #expect(model.capCents == 800)
        model.payAll()
        #expect(model.amountCents == 500)
    }

    @Test func choosingSidesKeepsTheTypedAmount() async {
        let model = await makeViewModel(summary([debt(from: 1, to: 2, cents: 1_200)]))
        model.amount.replaceEntry(cents: 500)
        model.swapParties()
        #expect(model.amountCents == 500)
    }

    @Test func aNewPaymentStartsAtZeroUntilPayAll() async {
        let model = await makeViewModel(summary([debt(from: 1, to: 2, cents: 1_200)]))
        #expect(model.amountCents == 0)
        #expect(!model.canSubmit)
        model.payAll()
        #expect(model.amountCents == 1_200)
        #expect(model.canSubmit)
    }

    /// Pending balances no longer block a payment: the server caps it against the rows,
    /// not the stored balances (ADR 0009). The refresh still brings the settled debt in.
    @Test func pendingSessionCanBeSubmittedAndSettledRefreshUpdatesTheDebt() async {
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
        #expect(model.payeeId == 2)
        model.payAll()
        #expect(model.amountCents == 1_200)
        #expect(model.canSubmit)
        model.amount.clear()

        await session.refresh()
        // No summary or pending value is copied into the screen model.
        #expect(!model.balancesPending)
        #expect(model.capCents == 900)
        model.payAll()
        #expect(model.amountCents == 900)
        session.discard()
    }

    @Test func rejectionNamesWhatYouOwe() async {
        let model = await makeViewModel(summary([debt(from: 1, to: 2, cents: 1_200)]))
        model.amount.replaceEntry(cents: 1_201)
        model.recordSubmissionFailure(TestError())
        #expect(model.errorMessage == L10n.Settlement.onlyOwe("Bob", "$12.00"))
    }

    @Test func rejectingMoreThanYouAreOwedNamesWhatThePeerOwes() async {
        let model = await makeViewModel(summary([debt(from: 2, to: 1, cents: 1_200)]))
        model.amount.replaceEntry(cents: 1_201)
        model.recordSubmissionFailure(TestError())
        #expect(model.errorMessage == L10n.Settlement.onlyOwesYou("Bob", "$12.00"))
    }

    @Test func rejectingAPaymentBetweenTwoOthersNamesBoth() async {
        let session = await makeSession(summary([debt(from: 3, to: 2, cents: 700)]), members: members + [cara])
        let model = SettleUpViewModel(session: session, currentUserId: 1)
        model.suggestPayment()
        model.amount.replaceEntry(cents: 800)
        model.recordSubmissionFailure(TestError())
        #expect(model.errorMessage == L10n.Settlement.onlyOwesPeer("Cara", "Bob", "$7.00"))
    }

    @Test func theServersCapIsNamedOverTheOneOnScreen() async {
        let model = await makeViewModel(summary([debt(from: 1, to: 2, cents: 1_200)]))
        model.amount.replaceEntry(cents: 1_200)
        model.recordSubmissionFailure(APIError.settlementExceedsCap(capCents: 400, message: nil))
        #expect(model.errorMessage == L10n.Settlement.onlyOwe("Bob", "$4.00"))
    }

    @Test func rejectionIsGenericWithoutAConflictingKnownDebt() async {
        let model = await makeViewModel(summary([debt(from: 1, to: 2, cents: 1_200)]))
        model.amount.replaceEntry(cents: 1_000)
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
        let session = await makeSession(summary([debt(from: 1, to: 2, cents: 1_200)]))
        let model = SettleUpViewModel(session: session, currentUserId: 1,
            dataSource: SettleUpDataSource(create: { _, _, _, _, _ in throw APIError.httpError(400, message: nil) },
                                         update: { _, _, _, _ in }))
        model.suggestPayment()
        model.amount.replaceEntry(cents: 1_200)
        let result = await model.submit()
        #expect(result == nil)
        #expect(model.errorMessage == L10n.Settlement.recordFailed)
    }

    @Test func payingTheLastDebtSettlesYouUp() async {
        let model = await makeViewModel(summary([debt(from: 1, to: 2, cents: 1_200), debt(from: 3, to: 2, cents: 700)]),
                                        dataSource: succeeding)
        model.payAll()
        let result = await model.submit()
        #expect(result?.settlesUp == true)
    }

    @Test func aPartialPaymentDoesNotSettleYouUp() async {
        let model = await makeViewModel(summary([debt(from: 1, to: 2, cents: 1_200)]), dataSource: succeeding)
        model.amount.replaceEntry(cents: 1_000)
        let result = await model.submit()
        #expect(result?.settlesUp == false)
    }

    @Test func clearingOneOfTwoDebtsDoesNotSettleYouUp() async {
        let session = await makeSession(summary([debt(from: 1, to: 2, cents: 1_200), debt(from: 1, to: 3, cents: 500)]),
                                        members: members + [cara])
        let model = SettleUpViewModel(session: session, currentUserId: 1, dataSource: succeeding)
        model.suggestPayment()
        model.amount.replaceEntry(cents: 1_200)
        let result = await model.submit()
        #expect(result?.amountCents == 1_200)
        #expect(result?.settlesUp == false)
    }

    @Test func raisingAPaymentToCoverTheRestSettlesYouUp() async {
        let model = await makeEditModel(remainingCents: 500, paidBy: 1)
        model.amount.replaceEntry(cents: 1_000)
        let result = await model.submit()
        #expect(result?.settlesUp == true)
    }

    @Test func raisingAPaymentShortOfTheRestDoesNotSettleYouUp() async {
        let model = await makeEditModel(remainingCents: 500, paidBy: 1)
        model.amount.replaceEntry(cents: 900)
        let result = await model.submit()
        #expect(result != nil)
        #expect(result?.settlesUp == false)
    }

    @Test func raisingAPaymentYouReceivedToWhatYouAreOwedSettlesYouUp() async {
        // Bob paid you $5.00 and still owes $3.00, so recording $8.00 clears it.
        let model = await makeEditModel(remainingCents: 300, paidBy: 2, debtorIsYou: false)
        model.amount.replaceEntry(cents: 800)
        let result = await model.submit()
        #expect(result?.settlesUp == true)
    }

    @Test func aReceivedPaymentIsSentWithThePeerAsPayerAndSettlesYouUp() async {
        let sent = SentPayments()
        let model = await makeViewModel(summary([debt(from: 2, to: 1, cents: 1_200)]), dataSource: sent.dataSource)
        model.payAll()
        let result = await model.submit()
        #expect(sent.created.count == 1)
        #expect(sent.created.first?.payerId == 2)
        #expect(sent.created.first?.payeeId == 1)
        #expect(sent.created.first?.amountCents == 1_200)
        #expect(result?.payerId == 2)
        #expect(result?.payeeId == 1)
        #expect(result?.settlesUp == true)
    }

    @Test func aReceivedPaymentKeptForLaterIsQueuedWithThePeerAsPayer() async {
        let sent = SentPayments()
        let model = await makeViewModel(summary([debt(from: 2, to: 1, cents: 1_200)]), dataSource: sent.queuedDataSource)
        model.payAll()
        let result = await model.submit()
        #expect(sent.created.isEmpty)
        #expect(sent.queued.count == 1)
        #expect(sent.queued.first?.payerId == 2)
        #expect(sent.queued.first?.payeeId == 1)
        #expect(result?.payerId == 2)
        #expect(result?.queued == true)
        #expect(result?.clientId == sent.clientId)
    }

    @Test func aPaymentBetweenTwoOthersIsSentAsPickedAndNeverSettlesYouUp() async {
        let sent = SentPayments()
        let session = await makeSession(summary([debt(from: 1, to: 2, cents: 500), debt(from: 3, to: 2, cents: 700)]),
                                        members: members + [cara])
        let model = SettleUpViewModel(session: session, currentUserId: 1, dataSource: sent.dataSource)
        model.suggestPayment()
        model.setPayer(3)
        model.payAll()
        let result = await model.submit()
        #expect(sent.created.first?.payerId == 3)
        #expect(sent.created.first?.payeeId == 2)
        #expect(sent.created.first?.amountCents == 700)
        #expect(result?.settlesUp == false)
    }

    // Editing a payment either side recorded.

    @Test func editingKeepsBothSidesOfThePayment() async {
        let model = await makeEditModel(remainingCents: 300, paidBy: 2, debtorIsYou: false)
        #expect(model.payerId == 2)
        #expect(model.payeeId == 1)
        model.swapParties()
        model.setPayer(1)
        #expect(model.payerId == 2)
        #expect(model.payeeId == 1)
    }

    @Test func editingAPaymentBetweenTwoOthersNeverSettlesYouUp() async {
        // You owe Bob $5.00; Cara paid Bob $5.00, and raising it moves nothing of yours.
        let session = await makeSession(summary([debt(from: 1, to: 2, cents: 500)]), members: members + [cara])
        let settlement = TestExpense.make(id: 18, paidBy: 3, amount: 5, splitAmounts: [3: 5, 2: -5],
                                          type: .payment, date: "2026-03-01T12:00:00Z")
        let model = SettleUpViewModel(session: session, currentUserId: 1, settlement: settlement,
                                      dataSource: succeeding)
        #expect(model.payer?.name == "Cara")
        #expect(model.payee?.name == "Bob")
        model.amount.replaceEntry(cents: 1_000)
        let result = await model.submit()
        #expect(result?.payerId == 3)
        #expect(result?.payeeId == 2)
        #expect(result?.settlesUp == false)
    }

    private func makeEditModel(remainingCents: Int, paidBy payer: Int, debtorIsYou: Bool = true) async -> SettleUpViewModel {
        let remaining = debtorIsYou ? debt(from: 1, to: 2, cents: remainingCents) : debt(from: 2, to: 1, cents: remainingCents)
        let session = await makeSession(summary([remaining]))
        let payee = payer == 1 ? 2 : 1
        let settlement = TestExpense.make(id: 18, paidBy: payer, amount: 5, splitAmounts: [payer: 5, payee: -5],
                                          type: .payment, date: "2026-03-01T12:00:00Z")
        return SettleUpViewModel(session: session, currentUserId: 1, settlement: settlement, dataSource: succeeding)
    }

    private var cara: GroupMember {
        GroupMember(id: 30, userId: 3, name: "Cara", email: "cara@example.com", avatarUrl: "")
    }

    private var succeeding: SettleUpDataSource {
        SettleUpDataSource(create: { _, _, _, _, _ in }, update: { _, _, _, _ in })
    }

    private func makeViewModel(_ summary: GroupBalanceSummary,
                               dataSource: SettleUpDataSource = .live) async -> SettleUpViewModel {
        let model = SettleUpViewModel(session: await makeSession(summary), currentUserId: 1, dataSource: dataSource)
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

/// Keeps every payment the screen asked to create.
@MainActor
private final class SentPayments {
    private(set) var created: [(payerId: Int, payeeId: Int, amountCents: Int)] = []

    var dataSource: SettleUpDataSource {
        SettleUpDataSource(
            create: { _, payerId, payeeId, amountCents, _ in
                self.created.append((payerId, payeeId, amountCents))
            },
            update: { _, _, _, _ in }
        )
    }

    private(set) var queued: [(payerId: Int, payeeId: Int, amountCents: Int)] = []
    let clientId = UUID()

    /// Keeps every payment for later, the way the outbox does offline.
    var queuedDataSource: SettleUpDataSource {
        var source = dataSource
        source.send = { _, payerId, payeeId, amountCents, _ in
            self.queued.append((payerId, payeeId, amountCents))
            return .queued(clientId: self.clientId)
        }
        return source
    }
}
