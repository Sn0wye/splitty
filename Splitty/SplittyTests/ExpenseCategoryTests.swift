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

    @MainActor
    @Test func chipsUpdateWhenTheSessionTimelineArrivesAfterSheetCreation() {
        let form = ExpenseFormViewModel(
            groupId: 1,
            members: TestExpense.members,
            currentUserId: 1
        )
        #expect(!form.categorySuggestions.contains(.games))

        form.updateTimelineExpenses([
            TestExpense.make(paidBy: 1, amount: 1, splitAmounts: [1: 1], category: .games)
        ])

        #expect(form.categorySuggestions.first == .games)
    }
}

struct ExpenseRepeatDecodingTests {
    private func decode(_ extraFields: String) throws -> Expense {
        let json =
            #"""
            {
              "id":1,
              "groupId":1,
              "paidBy":1,
              "amount":1200,
              "description":"Rent",
              "type":"expense",
              "splitMode":"equal",
              "category":"rent",
              "date":"2026-10-01T03:00:00Z",
              "createdAt":"2026-10-01T03:00:00Z",
              "updatedAt":"2026-10-01T03:00:00Z",
              "paidByUser":{"id":1,"name":"Alice","email":"alice@example.com","createdAt":"","updatedAt":""},
            """# + extraFields + #"""
              "splits":[]
            }
            """#
        return try JSONDecoder().decode(Expense.self, from: Data(json.utf8))
    }

    @Test func readsTheRecurringExpenseThatAddedIt() throws {
        let expense = try decode(#""recurringExpenseId":40,"repeat":"fortnightly","#)

        #expect(expense.recurringExpenseId == 40)
        #expect(expense.repeatFrequency == .fortnightly)
        #expect(expense.isRecurring)
        #expect(expense.repeatFrequency?.badge == "Repeats fortnightly")
    }

    @Test func anExpenseEnteredByHandHasNeither() throws {
        let nulls = try decode(#""recurringExpenseId":null,"repeat":null,"#)
        let absent = try decode("")

        for expense in [nulls, absent] {
            #expect(expense.recurringExpenseId == nil)
            #expect(expense.repeatFrequency == nil)
            #expect(!expense.isRecurring)
        }
    }

    @Test func anUnknownFrequencyDoesNotFailTheList() throws {
        let expense = try decode(#""recurringExpenseId":40,"repeat":"daily","#)

        #expect(expense.recurringExpenseId == 40)
        #expect(expense.repeatFrequency == nil)
    }
}
