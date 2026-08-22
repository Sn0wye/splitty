//
//  AmountExpressionTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

struct AmountExpressionTests {

    // MARK: - Entry

    @Test func startsAtZero() {
        let expression = AmountExpression()
        #expect(expression.displayText == "0")
        #expect(expression.resolvedCents == 0)
    }

    @Test func typesDigits() {
        var expression = AmountExpression()
        expression.type(digit: 1)
        expression.type(digit: 2)
        #expect(expression.displayText == "12")
        #expect(expression.resolvedCents == 1200)
    }

    @Test func aLeadingDecimalPointGetsAZero() {
        var expression = AmountExpression()
        expression.typeDecimalPoint()
        expression.type(digit: 5)
        #expect(expression.displayText == "0.5")
        #expect(expression.resolvedCents == 50)
    }

    @Test func keepsTheDisplayedTrailingPointWhileTyping() {
        var expression = AmountExpression()
        expression.type(digit: 7)
        expression.typeDecimalPoint()
        #expect(expression.displayText == "7.")
        #expect(expression.resolvedCents == 700)
    }

    @Test func ignoresASecondDecimalPoint() {
        var expression = AmountExpression()
        expression.type(digit: 1)
        expression.typeDecimalPoint()
        expression.type(digit: 5)
        expression.typeDecimalPoint()
        #expect(expression.displayText == "1.5")
    }

    // Money has two decimal places, so a third digit is not a number the user can mean.
    @Test func stopsAtTwoDecimalPlaces() {
        var expression = AmountExpression()
        expression.type(digit: 1)
        expression.typeDecimalPoint()
        expression.type(digit: 2)
        expression.type(digit: 3)
        expression.type(digit: 4)
        #expect(expression.displayText == "1.23")
    }

    @Test func backspaceRemovesTheLastCharacterAndThenReadsZero() {
        var expression = AmountExpression()
        expression.type(digit: 4)
        expression.type(digit: 2)
        expression.backspace()
        #expect(expression.displayText == "4")
        expression.backspace()
        #expect(expression.displayText == "0")
        expression.backspace()
        #expect(expression.displayText == "0")
    }

    @Test func clearResetsEverything() {
        var expression = AmountExpression()
        expression.type(digit: 9)
        expression.apply(.add)
        expression.type(digit: 9)
        expression.clear()
        #expect(expression.displayText == "0")
        #expect(expression.hasPendingExpression == false)
        #expect(expression.resolvedCents == 0)
    }

    // MARK: - Chained arithmetic

    // No precedence: 2 + 3 x 4 is 20, because parentheses the user cannot see are worse
    // than an answer they can follow left to right.
    @Test func chainsLeftToRightWithNoPrecedence() {
        var expression = AmountExpression()
        expression.type(digit: 2)
        expression.apply(.add)
        expression.type(digit: 3)
        expression.apply(.multiply)
        expression.type(digit: 4)
        #expect(expression.resolvedCents == 2000)
    }

    @Test func showsTheRunningTotalOnceAnOperatorIsPressed() {
        var expression = AmountExpression()
        expression.type(digit: 2)
        expression.apply(.add)
        expression.type(digit: 3)
        expression.apply(.multiply)
        #expect(expression.displayText == "5")
    }

    @Test func equalsResolvesAndLeavesTheResultAsTheEntry() {
        var expression = AmountExpression()
        expression.type(digit: 8)
        expression.apply(.subtract)
        expression.type(digit: 3)
        expression.evaluate()
        #expect(expression.displayText == "5")
        #expect(expression.hasPendingExpression == false)
        #expect(expression.resolvedCents == 500)
    }

    @Test func typingAfterEqualsStartsANewNumber() {
        var expression = AmountExpression()
        expression.type(digit: 8)
        expression.apply(.add)
        expression.type(digit: 2)
        expression.evaluate()
        expression.type(digit: 3)
        #expect(expression.displayText == "3")
    }

    @Test func replacesAnOperatorPressedTwice() {
        var expression = AmountExpression()
        expression.type(digit: 6)
        expression.apply(.add)
        expression.apply(.multiply)
        expression.type(digit: 2)
        #expect(expression.resolvedCents == 1200)
    }

    // Save auto-evaluates, so a dangling operator has to resolve to the left operand
    // rather than to nothing.
    @Test func resolvesADanglingOperatorToTheLeftOperand() {
        var expression = AmountExpression()
        expression.type(digit: 7)
        expression.apply(.divide)
        #expect(expression.hasPendingExpression)
        #expect(expression.resolvedCents == 700)
    }

    @Test func roundsARepeatingDivisionToTheNearestCent() {
        var expression = AmountExpression()
        expression.type(digit: 1)
        expression.type(digit: 0)
        expression.apply(.divide)
        expression.type(digit: 3)
        #expect(expression.resolvedCents == 333)
    }

    @Test func roundsHalfACentUp() {
        var expression = AmountExpression()
        expression.type(digit: 5)
        expression.apply(.divide)
        expression.type(digit: 8)
        #expect(expression.resolvedCents == 63) // 0.625
    }

    // Dividing by zero has no answer to show, so the operator is dropped and the left
    // operand stands.
    @Test func dividingByZeroKeepsTheLeftOperand() {
        var expression = AmountExpression()
        expression.type(digit: 9)
        expression.apply(.divide)
        expression.type(digit: 0)
        expression.evaluate()
        #expect(expression.displayText == "9")
    }

    // MARK: - Seeding

    @Test func seedsFromAnExistingAmount() {
        let expression = AmountExpression(cents: 4250)
        #expect(expression.displayText == "42.50")
        #expect(expression.resolvedCents == 4250)
    }

    @Test func seedsAWholeAmountWithoutTrailingZeros() {
        let expression = AmountExpression(cents: 4200)
        #expect(expression.displayText == "42")
    }

    @Test func replacesTheWholeEntryWithAPastedAmount() {
        var expression = AmountExpression()
        expression.type(digit: 1)
        expression.replaceEntry(cents: 1999)
        #expect(expression.displayText == "19.99")
        #expect(expression.hasPendingExpression == false)
    }
}
