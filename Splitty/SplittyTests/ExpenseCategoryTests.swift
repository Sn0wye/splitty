import Foundation
import Testing
@testable import Splitty

struct ExpenseCategoryTests {
    @Test func multiwordCategoriesUseTheAPIsSnakeCaseTokens() throws {
        let decoded = try JSONDecoder().decode(
            ExpenseCategory.self,
            from: Data(#""dining_out""#.utf8)
        )
        let encoded = try JSONEncoder().encode(ExpenseCategory.tvPhoneInternet)

        #expect(decoded == .diningOut)
        #expect(String(decoding: encoded, as: UTF8.self) == #""tv_phone_internet""#)
    }

    @Test func unknownWireCategoryFallsBackToGeneral() throws {
        let data = Data(
            #"""
            {
              "id":1,
              "groupId":1,
              "paidBy":1,
              "amount":12.5,
              "description":"Lunch",
              "type":"expense",
              "splitMode":"equal",
              "category":"newer-server-value",
              "date":null,
              "createdAt":"2026-08-20T12:00:00Z",
              "updatedAt":"2026-08-20T12:00:00Z",
              "paidByUser":{"id":1,"name":"Alice","email":"alice@example.com","createdAt":"","updatedAt":""},
              "splits":[]
            }
            """#.utf8
        )

        let expense = try JSONDecoder().decode(Expense.self, from: data)

        #expect(expense.category == .general)
    }

    @Test func chipsOrderByUsageThenFixedListOrder() {
        let expenses = [
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .taxi),
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .groceries),
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .taxi),
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .diningOut),
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .groceries),
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .movies),
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .games)
        ]

        #expect(
            ExpenseCategory.chipSuggestions(from: expenses, selected: .general)
                == [.groceries, .taxi, .games, .movies, .diningOut]
        )
    }

    @Test func selectionOutsideTopFiveTakesTheFirstSlot() {
        let expenses = [
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .games),
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .movies),
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .music),
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .sports),
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .entertainmentOther)
        ]

        #expect(
            ExpenseCategory.chipSuggestions(from: expenses, selected: .water)
                == [.water, .games, .movies, .music, .sports]
        )
    }
}
