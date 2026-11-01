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
/// Decodes a decimal JSON amount into the integer-cent representation used everywhere
/// after the transport boundary.
@propertyWrapper
struct DecodedCents: Codable, Equatable {
    var wrappedValue: Int

    init(wrappedValue: Int) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = Money.cents(from: try container.decode(Decimal.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Decimal(wrappedValue) / 100)
    }
}

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

    /// Reads what someone typed into an amount field. The pad always types a `.`, but the
    /// system decimal pad types the device region's separator, which is a `,` in Brazil or
    /// France. Neither field offers a grouping separator, so a `,` can only be the decimal.
    static func cents(fromTypedText text: String) -> Int? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return cents(from: value)
    }

    static func amount(cents: Int) -> Double {
        Double(cents) / 100
    }

    /// The value to put in a request body.
    ///
    /// Not `Double`: `JSONSerialization` prints a double to 17 significant digits, so 8.33
    /// goes out as `8.3300000000000001`, and the API parses that into a `decimal` that
    /// keeps every one of those digits. Three of them no longer sum to 25 and the request
    /// is rejected for splits that are, in cents, exact. `NSDecimalNumber` prints the
    /// decimal it holds.
    static func requestValue(cents: Int) -> NSDecimalNumber {
        NSDecimalNumber(decimal: Decimal(cents) / 100)
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

    /// `$1,234.50`, `R$ 1.234,50`, `1.234,50 €`: for anything being read rather than typed.
    /// Each currency writes its own symbol and separators, whatever the app language.
    static func formatted(cents: Int, currency: Currency) -> String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = abs(cents)
        let whole = grouped(magnitude / 100, separator: currency.groupingSeparator)
        let fraction = String(format: "%02d", magnitude % 100)
        return sign + currency.decorate("\(whole)\(currency.decimalSeparator)\(fraction)")
    }

    static func formatted(amount: Double, currency: Currency) -> String {
        formatted(cents: cents(from: amount), currency: currency)
    }

    /// `1234567` as `1,234,567`, in threes from the right.
    private static func grouped(_ value: Int, separator: String) -> String {
        let digits = String(value)
        var result = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { result += separator }
            result.append(digit)
        }
        return result
    }
}
