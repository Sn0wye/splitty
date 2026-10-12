//
//  ExpenseCSVTests.swift
//  SplittyTests
//

import Testing
@testable import Splitty

@Suite(.appLanguage(.english))
struct ExpenseCSVTests {

    // Oldest first, one column per person, blank where someone had no share.
    @Test func listsRecordsOldestFirstWithAColumnPerPerson() {
        let csv = ExpenseCSV(groupName: "Trip", expenses: [
            TestExpense.make(id: 2, paidBy: 2, amount: 9, splitAmounts: [2: 4.5, 3: 4.5], date: "2026-08-22T12:00:00Z"),
            TestExpense.make(id: 1, paidBy: 1, amount: 30, splitAmounts: [1: 10, 2: 20], date: "2026-08-21T12:00:00Z"),
        ])
        let lines = csv.text.dropFirst().components(separatedBy: "\r\n")

        #expect(lines.first == "Date,Description,Category,Paid by,Amount,User 1,User 2,User 3")
        #expect(lines.dropFirst().map { $0.split(separator: ",", maxSplits: 1).last.map(String.init) } == [
            "Dinner,General,User 1,30.00,10.00,20.00,",
            "Dinner,General,User 2,9.00,,4.50,4.50",
        ])
    }

    @Test func quotesFieldsAndDefusesFormulas() {
        #expect(ExpenseCSV.field(#"Pizza, "large""#) == #""Pizza, ""large""""#)
        #expect(ExpenseCSV.field("=HYPERLINK(1)") == "'=HYPERLINK(1)")
        #expect(ExpenseCSV.field("-4.50") == "-4.50")
    }

    @Test func fileNameDropsPathSeparators() {
        #expect(ExpenseCSV(groupName: "Rent 10/26", expenses: []).fileName == "Rent 10-26")
    }
}
