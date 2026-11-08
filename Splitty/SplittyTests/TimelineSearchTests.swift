//
//  TimelineSearchTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

@Suite(.appLanguage(.english))
struct TimelineSearchTests {

    private func expense(
        description: String = "Dinner",
        paidBy: Int = 1,
        amount: Double = 30,
        splitAmounts: [Int: Double] = [1: 15, 2: 15],
        type: ExpenseType = .expense,
        category: ExpenseCategory = .general
    ) -> Expense {
        let base = TestExpense.make(
            paidBy: paidBy, amount: amount, splitAmounts: splitAmounts, type: type, category: category
        )
        return Expense(
            id: base.id, groupId: base.groupId, paidBy: base.paidBy, amount: base.amount,
            description: description, type: base.type, category: base.category,
            splitMode: base.splitMode, date: base.date, createdAt: base.createdAt,
            updatedAt: base.updatedAt, paidByUser: base.paidByUser, splits: base.splits
        )
    }

    @Test func anEmptyQueryFindsEverything() {
        #expect(expense().matches(search: "   ", currency: .usd))
    }

    // Typed without the accent or in another case, the description still matches.
    @Test func findsTheDescriptionIgnoringCaseAndAccents() {
        let row = expense(description: "Café da manhã")
        #expect(row.matches(search: "CAFE", currency: .usd))
        #expect(row.matches(search: "manha", currency: .usd))
        #expect(!row.matches(search: "jantar", currency: .usd))
    }

    // Each word may be a fragment of a different word in the row.
    @Test func matchesFragmentsOfSeveralWords() {
        let row = expense(description: "Dinner at the sushi place")
        #expect(row.matches(search: "din su pla", currency: .usd))
        #expect(row.matches(search: "PLA sus", currency: .usd))
        #expect(!row.matches(search: "din pizza", currency: .usd))
    }

    @Test func findsWhoPaidAndWhoTookPart() {
        let row = expense(paidBy: 1, splitAmounts: [1: 10, 3: 20])
        #expect(row.matches(search: "user 1", currency: .usd))
        #expect(row.matches(search: "User 3", currency: .usd))
        #expect(!row.matches(search: "User 2", currency: .usd))
    }

    // Every word has to land somewhere, not necessarily in the same field.
    @Test func everyWordHasToMatch() {
        let row = expense(description: "Groceries run", paidBy: 2, splitAmounts: [2: 30])
        #expect(row.matches(search: "groceries 2", currency: .usd))
        #expect(!row.matches(search: "groceries taxi", currency: .usd))
    }

    @Test func findsTheCategoryAndTheAmountAsWritten() {
        let row = expense(description: "Friday", amount: 42.5, category: .taxi)
        #expect(row.matches(search: ExpenseCategory.taxi.name, currency: .usd))
        #expect(row.matches(search: "42.50", currency: .usd))
        #expect(row.matches(search: "42,50", currency: .brl))
    }

    // A payment is searched by the title its row shows, not the English description the
    // server stored.
    @Test func findsAPaymentByItsRowTitle() {
        let payment = expense(
            description: "Settlement stored by the server",
            paidBy: 1,
            splitAmounts: [1: 10, 2: -10],
            type: .payment,
            category: .payment
        )
        #expect(payment.matches(search: "payment to user 2", currency: .usd))
        #expect(!payment.matches(search: "settlement", currency: .usd))
    }

    // A day keeps only its matching rows, and a day with none loses its header too.
    @Test func narrowsDaysAndDropsTheEmptyOnes() {
        let monday = Date(timeIntervalSince1970: 1_700_000_000)
        let tuesday = monday.addingTimeInterval(86_400)
        let days = [
            GroupedExpense(date: tuesday, dateString: "Tue", expenses: [expense(description: "Taxi"), expense(description: "Lunch")]),
            GroupedExpense(date: monday, dateString: "Mon", expenses: [expense(description: "Cinema")]),
        ]

        let found = days.matching(search: "lunch", currency: .usd)

        #expect(found.map(\.dateString) == ["Tue"])
        #expect(found.first?.expenses.map(\.description) == ["Lunch"])
    }
}
