//
//  GroupFormCurrencyTests.swift
//  SplittyTests
//

import Foundation
import Testing

@testable import Splitty

@MainActor
@Suite("Group form currency")
struct GroupFormCurrencyTests {
    @Test("a new group starts in the phone region's currency, or dollars outside the list", arguments: [
        ("pt_BR", Currency.brl),
        ("en_US", .usd),
        ("de_DE", .eur),
        ("fr_CH", .chf),
        ("en_CA", .cad),
        ("ja_JP", .usd),
        ("en", .usd),
    ])
    func newGroupStartsInRegionCurrency(identifier: String, expected: Currency) {
        #expect(Currency.preferred(for: Locale(identifier: identifier)) == expected)
    }

    @Test("a new group never asks before saving")
    func newGroupNeverAsks() {
        let viewModel = GroupFormViewModel(currency: .usd)
        viewModel.currency = .brl
        #expect(!viewModel.changesCurrency)
    }

    @Test("editing asks only once the currency differs from the saved one")
    func editingAsksOnChange() {
        let viewModel = GroupFormViewModel(existingGroupId: 7, name: "Trip", currency: .eur)
        #expect(!viewModel.changesCurrency)
        viewModel.currency = .gbp
        #expect(viewModel.changesCurrency)
        viewModel.currency = .eur
        #expect(!viewModel.changesCurrency)
    }
}
