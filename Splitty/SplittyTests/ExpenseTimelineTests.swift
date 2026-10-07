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
        let session = GroupSession(groupId: 1, dataSource: ControlledGroupData().source())
        session.report(.expenseCreated(TestExpense.make(id: 9, paidBy: 1, amount: 30, splitAmounts: [1: 30])))

        #expect(session.expenses.map(\.id) == [9])
        #expect(session.groupedExpenses.flatMap { $0.expenses }.map(\.id) == [9])
        session.discard()
    }

    @Test func insertingAnEditedExpenseReplacesTheRowRatherThanDoublingIt() {
        let session = GroupSession(groupId: 1, dataSource: ControlledGroupData().source())
        session.report(.expenseCreated(TestExpense.make(id: 9, paidBy: 1, amount: 30, splitAmounts: [1: 30])))
        session.report(.expenseEdited(TestExpense.make(id: 9, paidBy: 1, amount: 45, splitAmounts: [1: 45])))

        #expect(session.expenses.map(\.amount) == [45])
        session.discard()
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

    // Paying only for yourself moves no money, so it must not read as a loan of zero.
    @Test func aSoloPayerPaidForThemselves() {
        let expense = TestExpense.make(paidBy: 1, amount: 30, splitAmounts: [1: 30])
        #expect(expense.involvement(of: 1) == .paidForYourself)
    }

    @Test func aPayerSplittingWithOthersLentTheirShares() {
        let expense = TestExpense.make(paidBy: 1, amount: 30, splitAmounts: [1: 10, 2: 20])
        #expect(expense.involvement(of: 1) == .lent(20))
    }

    @Test func aParticipantBorrowedTheirShare() {
        let expense = TestExpense.make(paidBy: 1, amount: 30, splitAmounts: [1: 10, 2: 20])
        #expect(expense.involvement(of: 2) == .borrowed(20))
    }

    @Test func aNonParticipantIsNotInvolved() {
        let expense = TestExpense.make(paidBy: 1, amount: 30, splitAmounts: [1: 10, 2: 20])
        #expect(expense.involvement(of: 3) == .notInvolved)
    }

    @Test func aSettlementReadsAsAPaymentOnlyToItsTwoSides() {
        let settlement = TestExpense.make(paidBy: 2, amount: 10, splitAmounts: [2: 10, 3: -10], type: .payment)
        #expect(settlement.involvement(of: 2) == .payment)
        #expect(settlement.involvement(of: 3) == .payment)
        #expect(settlement.involvement(of: 1) == .notInvolved)
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

    // A refusal the server names with a code keeps it, so a caller branches on the code
    // rather than the English message. A code this build does not know is an ordinary error.
    @Test func keepsTheCodeOfARefusalItKnows() async {
        let server = StubServer { request in
            let code = request.url?.path == "/known" ? "balances_pending" : "newer_server_code"
            return (409, json(["statusCode": 409, "message": "Try again later.", "code": code]))
        }
        let client = server.client(credentials: InMemoryCredentialStore())

        await #expect {
            let _: EmptyResponse = try await client.request(endpoint: "/known", method: .POST, requiresAuth: false)
        } throws: { error in
            guard case .refused(409, .balancesPending, "Try again later.") = error as? APIError else { return false }
            return true
        }
        await #expect {
            let _: EmptyResponse = try await client.request(endpoint: "/unknown", method: .POST, requiresAuth: false)
        } throws: { error in
            guard case .httpError(409, "Try again later.") = error as? APIError else { return false }
            return true
        }
    }

    @Test func readsAnErrorThatIsNotAnAPIError() {
        struct Sad: LocalizedError { var errorDescription: String? { "Sad" } }
        #expect(Sad().displayMessage == "Sad")
    }

    @Test func recognisesCancellationAsControlFlowRatherThanANetworkFailure() {
        #expect(CancellationError().isCancellation)
        #expect(URLError(.cancelled).isCancellation)
        #expect(APIError.networkError(URLError(.cancelled)).isCancellation)
        #expect(!URLError(.notConnectedToInternet).isCancellation)
    }

    @Test func recognisesOnlyANotFoundResponseAsAlreadyGone() {
        #expect(APIError.httpError(404, message: nil).isAlreadyGone)
        #expect(APIError.httpError(404, message: "This no longer exists.").isAlreadyGone)
        #expect(APIError.networkError(APIError.httpError(404, message: nil)).isAlreadyGone)

        #expect(!APIError.httpError(400, message: nil).isAlreadyGone)
        #expect(!APIError.httpError(403, message: nil).isAlreadyGone)
        #expect(!APIError.httpError(500, message: nil).isAlreadyGone)
        #expect(!URLError(.notConnectedToInternet).isAlreadyGone)
        #expect(!CancellationError().isAlreadyGone)
    }
}

// MARK: - Timeline construction

struct TimelineGroupingTests {

    @Test func ordersDaysAndRowsWithinADayNewestFirst() {
        let grouped = Expense.groupExpensesByDate([
            TestExpense.make(id: 1, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2026-04-10T09:00:00Z"),
            TestExpense.make(id: 2, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2026-04-12T08:00:00Z"),
            TestExpense.make(id: 3, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2026-04-12T20:00:00Z")
        ])

        #expect(grouped.map(\.date) == grouped.map(\.date).sorted(by: >))
        #expect(grouped.flatMap { $0.expenses }.map(\.id) == [3, 2, 1])
    }

    // Same label, different years. Identity is the normalized day, so SwiftUI cannot
    // reuse one section for the other.
    @Test func sectionsInDifferentYearsSharingALabelStillHaveDistinctIdentities() {
        let grouped = Expense.groupExpensesByDate([
            TestExpense.make(id: 1, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2021-04-12T09:00:00Z"),
            TestExpense.make(id: 2, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2027-04-12T09:00:00Z")
        ])

        #expect(grouped.count == 2)
        #expect(Set(grouped.map(\.dateString)).count == 1)
        #expect(Set(grouped.map(\.id)).count == 2)
    }

    @Test func filesAnUndatedRowUnderItsAuditTimestamp() {
        let grouped = Expense.groupExpensesByDate([
            TestExpense.make(id: 1, paidBy: 1, amount: 10, splitAmounts: [1: 10])
        ])

        #expect(grouped.count == 1)
        #expect(grouped[0].date == Calendar.current.startOfDay(for: Expense.parseTimestamp("2026-08-20T12:00:00Z")!))
    }

    @Test func keepsARowWhoseTimestampCannotBeParsed() {
        let grouped = Expense.groupExpensesByDate([
            TestExpense.make(id: 1, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "not a date"),
            TestExpense.make(id: 2, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2026-04-12T09:00:00Z")
        ])

        #expect(grouped.flatMap { $0.expenses }.map(\.id) == [2, 1])
        #expect(grouped.last?.dateString == "Unknown")
    }

    @Test func readsTheAcceptedTimestampFormats() {
        let withFractionalSeconds = Expense.parseTimestamp("2026-04-12T09:00:00.123Z")
        let withoutFractionalSeconds = Expense.parseTimestamp("2026-04-12T09:00:00Z")
        let withoutAZone = Expense.parseTimestamp("2026-04-12T09:00:00")
        let withoutAZoneButFractional = Expense.parseTimestamp("2026-04-12T09:00:00.123")

        #expect(withoutFractionalSeconds == withoutAZone)
        #expect(withoutFractionalSeconds == withoutAZoneButFractional)
        #expect(withFractionalSeconds != nil)
        #expect(withFractionalSeconds! > withoutFractionalSeconds!)
        #expect(Expense.parseTimestamp("nonsense") == nil)
    }

    // Parsing is shared, so repeating a parse must not leak formatter state between the
    // formats — the old implementation mutated one formatter's options in place.
    @Test func repeatedParsesOfMixedFormatsStayStable() {
        let values = ["2026-04-12T09:00:00.123Z", "2026-04-12T09:00:00Z", "2026-04-12T09:00:00"]
        let first = values.map(Expense.parseTimestamp)
        let second = values.map(Expense.parseTimestamp)
        #expect(first == second)
        #expect(first.allSatisfy { $0 != nil })
    }

    @Test func labelsTodayAndYesterdayRelativeToNow() {
        let now = Expense.parseTimestamp("2026-04-12T09:00:00Z")!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let older = Calendar.current.date(byAdding: .day, value: -8, to: now)!

        #expect(Expense.dayLabel(for: now, now: now) == "Today")
        #expect(Expense.dayLabel(for: yesterday, now: now) == "Yesterday")
        #expect(Expense.dayLabel(for: older, now: now) != "Yesterday")
        #expect(Expense.dayLabel(for: nil, now: now) == "Unknown")
    }
}
