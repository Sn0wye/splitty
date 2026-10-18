//
//  Currency.swift
//  Splitty
//

import SwiftUI

/// The currency every amount in a group is in. A closed list of currencies with two decimal
/// places, matching the server's; see docs/adr/0007-a-group-has-one-currency.md.
///
/// Each currency carries its own format, so `R$ 1.234,50` reads the same whatever the app
/// language: the format belongs to the money, not to the reader.
enum Currency: String, Codable, CaseIterable, Identifiable, Sendable {
    case usd = "USD"
    case cad = "CAD"
    case aud = "AUD"
    case mxn = "MXN"
    case gbp = "GBP"
    case brl = "BRL"
    case eur = "EUR"
    case chf = "CHF"

    var id: String { rawValue }

    var code: String { rawValue }

    /// The short forms Apple uses outside each currency's home country, so no two
    /// currencies in the list share a symbol.
    var symbol: String {
        switch self {
        case .usd: "$"
        case .cad: "CA$"
        case .aud: "A$"
        case .mxn: "MX$"
        case .gbp: "£"
        case .brl: "R$"
        case .eur: "€"
        case .chf: "CHF"
        }
    }

    /// Whether the symbol is written after the number, as in `42,50 €`.
    var symbolFollowsAmount: Bool { self == .eur }

    /// A space between symbol and number: `R$ 42,50` and `42,50 €`, but `$42.50`.
    var symbolIsSpaced: Bool {
        switch self {
        case .brl, .eur, .chf: true
        case .usd, .cad, .aud, .mxn, .gbp: false
        }
    }

    var decimalSeparator: String {
        switch self {
        case .brl, .eur: ","
        case .usd, .cad, .aud, .mxn, .gbp, .chf: "."
        }
    }

    var groupingSeparator: String {
        switch self {
        case .brl, .eur: "."
        case .chf: "'"
        case .usd, .cad, .aud, .mxn, .gbp: ","
        }
    }

    /// The SF Symbol coin for this currency's sign, or nil when SF Symbols has none that matches
    /// how the currency is written: its only franc coin is `₣`, and the Swiss write `CHF`.
    var coinGlyph: String? {
        switch self {
        case .usd, .cad, .aud, .mxn: "dollarsign.circle.fill"
        case .gbp: "sterlingsign.circle.fill"
        case .brl: "brazilianrealsign.circle.fill"
        case .eur: "eurosign.circle.fill"
        case .chf: nil
        }
    }

    /// `number` with the symbol on the side and at the spacing this currency writes it.
    func decorate(_ number: String) -> String {
        let space = symbolIsSpaced ? " " : ""
        return symbolFollowsAmount ? "\(number)\(space)\(symbol)" : "\(symbol)\(space)\(number)"
    }

    /// The currency's name in the app language, for the picker: "Real brasileiro" in
    /// Portuguese, "Brazilian Real" in English.
    var localizedName: String {
        AppLanguage.currentLocale.localizedString(forCurrencyCode: code) ?? code
    }
}

extension EnvironmentValues {
    /// The open group's currency, set once at the root of the group screen so the views under
    /// it, sheets included, format in it without each one being handed the group.
    @Entry var currency: Currency = .usd
}
