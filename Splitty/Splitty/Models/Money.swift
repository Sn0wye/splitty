//
//  Money.swift
//  Splitty
//

import Foundation

/// Amounts in integer cents.
///
/// The API validates that splits sum **exactly** to the total against a `decimal` column.
/// Deriving splits in `Double` makes that a coin flip; deriving them in cents makes it a
/// property of the arithmetic. Conversion happens once, at the request boundary.
enum Money {
    static func cents(from value: Decimal) -> Int {
        var rounded = Decimal()
        var scaled = value * 100
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func cents(from value: Double) -> Int {
        cents(from: Decimal(value))
    }

    static func amount(cents: Int) -> Double {
        Double(cents) / 100
    }

    /// `42`, `42.50` — for a field being typed into, where trailing zeros are noise.
    static func plainString(cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = abs(cents)
        let whole = magnitude / 100
        let fraction = magnitude % 100
        return fraction == 0
            ? "\(sign)\(whole)"
            : "\(sign)\(whole).\(String(format: "%02d", fraction))"
    }

    /// `$42.50` — for anything being read rather than typed. Currency is a hardcoded `$`.
    static func formatted(cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = abs(cents)
        return "\(sign)$\(magnitude / 100).\(String(format: "%02d", magnitude % 100))"
    }

    static func formatted(amount: Double) -> String {
        formatted(cents: cents(from: amount))
    }
}
