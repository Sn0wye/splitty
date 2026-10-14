//
//  PlansTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

/// Installment badges on expenses, and the Plans screen's Installments section.
@Suite(.appLanguage(.english))
@MainActor
struct PlansTests {

    // MARK: - Badges

    @Test func aRecurringExpenseWithAnEndShowsWhichInstallmentItIs() throws {
        let expense = try decodeExpense(installment: ["number": 4, "total": 12], endsOn: "2030-12-15")

        #expect(expense.installment == ExpenseInstallment(number: 4, total: 12))
        #expect(expense.endsOn == "2030-12-15")
        #expect(expense.repeatBadge == "Repeats monthly · 4/12")
    }

    @Test func aRecurringExpenseWithNoEndLooksAsBefore() throws {
        let expense = try decodeExpense(installment: nil, endsOn: nil)

        #expect(expense.repeatBadge == "Repeats monthly")
    }

    @Test func anExpenseEnteredByHandHasNoBadge() {
        let expense = TestExpense.make(paidBy: 1, amount: 10, splitAmounts: [1: 10])

        #expect(expense.repeatBadge == nil)
    }

    // MARK: - Installments

    @Test func loadsTheGroupsActiveRecurringExpenses() async throws {
        var asked: [Int] = []
        let viewModel = PlansViewModel(groupId: 5, dataSource: PlansDataSource { groupId in
            asked.append(groupId)
            return [Self.phone, Self.rent]
        })
        #expect(viewModel.installments == .loading)

        await viewModel.load()

        #expect(asked == [5])
        #expect(viewModel.installments == .loaded([Self.phone, Self.rent]))
    }

    @Test func aGroupWithNothingRecurringIsEmpty() async {
        let viewModel = PlansViewModel(groupId: 5, dataSource: PlansDataSource { _ in [] })

        await viewModel.load()

        #expect(viewModel.installments == .empty)
    }

    @Test func aFailedLoadSaysWhyAndTryingAgainRecovers() async {
        var fails = true
        let viewModel = PlansViewModel(groupId: 5, dataSource: PlansDataSource { _ in
            if fails { throw APIError.networkError(URLError(.notConnectedToInternet)) }
            return [Self.phone]
        })

        await viewModel.load()
        guard case .failed(let message) = viewModel.installments else {
            Issue.record("Expected a failure, got \(viewModel.installments)")
            return
        }
        #expect(!message.isEmpty)

        fails = false
        await viewModel.load()
        #expect(viewModel.installments == .loaded([Self.phone]))
    }

    @Test func reloadingKeepsTheListUntilTheAnswerArrives() async {
        var answer = [Self.phone, Self.rent]
        let viewModel = PlansViewModel(groupId: 5, dataSource: PlansDataSource { _ in answer })
        await viewModel.load()

        answer = [Self.rent]
        await viewModel.load()

        #expect(viewModel.installments == .loaded([Self.rent]))
    }

    @Test func progressReadsAsCountOfTotalOrNoEnd() {
        #expect(Self.phone.progressText == "4 of 12")
        #expect(Self.rent.progressText == "No end")
    }

    @Test func decodesTheRouteAnswer() throws {
        let data = json([[
            "id": 1, "description": "New phone", "amount": 100.5, "category": "electronics", "paidBy": 2,
            "frequency": "monthly", "nextDueOn": "2030-05-15", "endsOn": "2030-12-15",
            "progress": ["added": 4, "total": 12]
        ], [
            "id": 2, "description": "Rent", "amount": 1500, "category": "rent", "paidBy": 1,
            "frequency": "monthly", "nextDueOn": "2030-05-01", "endsOn": NSNull(),
            "progress": ["added": 9, "total": NSNull()]
        ]])

        let plans = try JSONDecoder().decode([RecurringPlan].self, from: data)

        #expect(plans.map(\.progressText) == ["4 of 12", "No end"])
        #expect(plans[0].endsOn == "2030-12-15")
        #expect(plans[1].endsOn == nil)
    }

    @Test func openingAPlanFindsItsNewestExpense() {
        var april = TestExpense.make(id: 3, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2030-04-15T12:00:00Z")
        april.recurringExpenseId = Self.phone.id
        var march = TestExpense.make(id: 9, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2030-03-15T12:00:00Z")
        march.recurringExpenseId = Self.phone.id
        let other = TestExpense.make(id: 4, paidBy: 1, amount: 10, splitAmounts: [1: 10], date: "2030-05-15T12:00:00Z")

        #expect(Self.phone.latestExpense(in: [march, other, april])?.id == 3)
        #expect(Self.rent.latestExpense(in: [march, other, april]) == nil)
    }

    // MARK: - Fixtures

    private static let phone = RecurringPlan(
        id: 1, description: "New phone", amount: 100, category: .electronics, paidBy: 1,
        frequency: .monthly, nextDueOn: "2030-05-15", endsOn: "2030-12-15",
        progress: .init(added: 4, total: 12)
    )

    private static let rent = RecurringPlan(
        id: 2, description: "Rent", amount: 1_500, category: .rent, paidBy: 1,
        frequency: .monthly, nextDueOn: "2030-05-01", endsOn: nil,
        progress: .init(added: 9, total: nil)
    )

    private func decodeExpense(installment: [String: Int]?, endsOn: String?) throws -> Expense {
        let user: [String: Any] = ["id": 1, "name": "Ada", "email": "ada@example.com", "createdAt": "", "updatedAt": ""]
        let data = json([
            "id": 7, "groupId": 1, "paidBy": 1, "amount": 30, "description": "Phone", "type": "expense",
            "category": "electronics", "splitMode": "equal", "date": "2030-04-15T12:00:00Z",
            "createdAt": "2030-04-15T12:00:00Z", "updatedAt": "2030-04-15T12:00:00Z",
            "recurringExpenseId": 40, "repeat": "monthly",
            "endsOn": endsOn as Any? ?? NSNull(),
            "installment": installment as Any? ?? NSNull(),
            "paidByUser": user, "splits": []
        ])
        return try JSONDecoder().decode(Expense.self, from: data)
    }
}
