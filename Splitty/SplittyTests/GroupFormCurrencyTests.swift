//
//  GroupFormCurrencyTests.swift
//  SplittyTests
//

import Testing

@testable import Splitty

@MainActor
@Suite("Group form currency")
struct GroupFormCurrencyTests {
    @Test("a new group starts in dollars and never asks before saving")
    func newGroupDefaultsToDollars() {
        let viewModel = GroupFormViewModel()
        #expect(viewModel.currency == .usd)
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
