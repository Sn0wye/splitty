//
//  AmountExpression.swift
//  Splitty
//

import Foundation

/// The four operations the keypad offers.
enum CalculatorOperator: CaseIterable {
    case add
    case subtract
    case multiply
    case divide

    var symbol: String {
        switch self {
        case .add: return "+"
        case .subtract: return "−"
        case .multiply: return "×"
        case .divide: return "÷"
        }
    }
}

/// The amount field's state machine: what has been typed, plus at most one pending
/// operation.
///
/// Arithmetic is **chained left to right with no precedence** — `2 + 3 × 4` is `20`.
/// Precedence without visible parentheses produces an answer that looks wrong and cannot
/// be diagnosed from the one line of digits on screen.
///
/// Values are held as `Decimal` and rounded to the cent only when read, so a chain of
/// operations does not accumulate binary floating-point drift on its way to a total that
/// the splits have to match exactly.
struct AmountExpression: Equatable {
    /// The number currently being typed. `nil` means the next digit starts a fresh one,
    /// and the display falls back to `accumulator`.
    private var entry: String?
    private var accumulator: Decimal = 0

    /// Visible so the pad can highlight the operator that is waiting for its right operand.
    private(set) var pendingOperator: CalculatorOperator?

    /// Two decimal places, because a third digit is not an amount of money anyone can pay.
    private static let fractionLimit = 2

    /// Enough digits for any real expense, and short of anything that would overflow the
    /// conversion to cents.
    private static let integerLimit = 9

    init() {}

    /// Seeds the field when an existing expense is reopened.
    init(cents: Int) {
        entry = Self.format(Decimal(cents) / 100)
    }

    // MARK: - Reading

    var displayText: String {
        entry ?? Self.format(accumulator)
    }

    /// True while an operator is waiting for its right operand. Save auto-evaluates rather
    /// than refusing to save a number the app can compute.
    var hasPendingExpression: Bool { pendingOperator != nil }

    /// The value of the whole expression, pending operation included, in cents.
    var resolvedCents: Int {
        Money.cents(from: resolved)
    }

    private var resolved: Decimal {
        guard let pendingOperator else { return entryValue ?? accumulator }
        guard let right = entryValue else { return accumulator }
        return Self.combine(accumulator, pendingOperator, right) ?? accumulator
    }

    private var entryValue: Decimal? {
        // A trailing point ("7.") is a display state, not a number; parsing reads it as 7.
        guard let entry, let cents = Money.cents(fromTypedText: entry) else { return nil }
        return Decimal(cents) / 100
    }

    // MARK: - Entry

    mutating func type(digit: Int) {
        guard (0...9).contains(digit) else { return }

        guard var text = entry else {
            entry = "\(digit)"
            return
        }

        if text == "0" {
            entry = "\(digit)"
            return
        }

        if let pointIndex = text.firstIndex(of: ".") {
            let fractionDigits = text.distance(from: text.index(after: pointIndex), to: text.endIndex)
            guard fractionDigits < Self.fractionLimit else { return }
        } else {
            guard text.count < Self.integerLimit else { return }
        }

        text.append("\(digit)")
        entry = text
    }

    mutating func typeDecimalPoint() {
        guard let text = entry else {
            entry = "0."
            return
        }
        guard !text.contains(".") else { return }
        entry = text + "."
    }

    mutating func backspace() {
        // After an evaluation the result lives in the accumulator; deleting from it is
        // what someone who mistyped the last digit expects.
        if entry == nil, pendingOperator == nil, accumulator != 0 {
            entry = Self.format(accumulator)
            accumulator = 0
        }

        guard var text = entry else { return }
        text.removeLast()
        entry = text.isEmpty ? nil : text
    }

    mutating func clear() {
        entry = nil
        accumulator = 0
        pendingOperator = nil
    }

    /// Replaces the whole entry — the clipboard chip, which offers a price rather than a
    /// digit to append.
    mutating func replaceEntry(cents: Int) {
        entry = Self.format(Decimal(cents) / 100)
        accumulator = 0
        pendingOperator = nil
    }

    // MARK: - Arithmetic

    mutating func apply(_ operation: CalculatorOperator) {
        if let right = entryValue {
            accumulator = pendingOperator.flatMap { Self.combine(accumulator, $0, right) } ?? right
            entry = nil
        }
        pendingOperator = operation
    }

    mutating func evaluate() {
        accumulator = resolved
        entry = nil
        pendingOperator = nil
    }

    /// `nil` when the operation has no answer to show — only division by zero, which
    /// leaves the left operand standing rather than inventing a result.
    private static func combine(_ left: Decimal, _ operation: CalculatorOperator, _ right: Decimal) -> Decimal? {
        switch operation {
        case .add: return left + right
        case .subtract: return left - right
        case .multiply: return left * right
        case .divide: return right == 0 ? nil : left / right
        }
    }

    // MARK: - Formatting

    /// Whole amounts read as `42`, not `42.00`: the trailing zeros are noise while typing.
    private static func format(_ value: Decimal) -> String {
        let cents = Money.cents(from: value)
        return Money.plainString(cents: cents)
    }
}
