//
//  MoneyFormattingTests.swift
//  SplittyTests
//

import Foundation
import Testing

@testable import Splitty

@Suite("Money formatting")
struct MoneyFormattingTests {
    @Test("each currency writes its own symbol and separators", arguments: [
        (Currency.usd, "$1,234.50"),
        (.cad, "CA$1,234.50"),
        (.aud, "A$1,234.50"),
        (.mxn, "MX$1,234.50"),
        (.gbp, "£1,234.50"),
        (.brl, "R$ 1.234,50"),
        (.eur, "1.234,50 €"),
        (.chf, "CHF 1'234.50"),
    ])
    func formatsEachCurrency(currency: Currency, expected: String) {
        #expect(Money.formatted(cents: 123_450, currency: currency) == expected)
    }

    @Test("the format does not follow the app language")
    func ignoresAppLanguage() {
        AppLanguage.$pinned.withValue(.english) {
            #expect(Money.formatted(cents: 4_250, currency: .brl) == "R$ 42,50")
        }
        AppLanguage.$pinned.withValue(.brazilianPortuguese) {
            #expect(Money.formatted(cents: 4_250, currency: .usd) == "$42.50")
        }
    }

    @Test("groups every three digits and pads the cents")
    func groupsAndPads() {
        #expect(Money.formatted(cents: 5, currency: .usd) == "$0.05")
        #expect(Money.formatted(cents: 99_999, currency: .usd) == "$999.99")
        #expect(Money.formatted(cents: 123_456_789_00, currency: .eur) == "123.456.789,00 €")
    }

    @Test("puts the sign before the symbol")
    func signsNegativeAmounts() {
        #expect(Money.formatted(cents: -4_250, currency: .usd) == "-$42.50")
        #expect(Money.formatted(cents: -4_250, currency: .eur) == "-42,50 €")
    }

    @Test("reads a typed comma as the decimal point, as the system pad types it in Brazil")
    func parsesEitherSeparator() {
        #expect(Money.cents(fromTypedText: "12,50") == 1_250)
        #expect(Money.cents(fromTypedText: "12.50") == 1_250)
        #expect(Money.cents(fromTypedText: "12") == 1_200)
        #expect(Money.cents(fromTypedText: "") == nil)
    }
}
