//
//  MoneyRequestValueTests.swift
//  SplittyTests
//

import Foundation
import Testing

@testable import Splitty

@Suite("Money request values")
struct MoneyRequestValueTests {
    /// The bug this exists for: `JSONSerialization` prints a `Double` to 17 significant
    /// digits, so a third of 25 went out as 8.3300000000000001 and the API — which parses
    /// into `decimal`, keeping all of it — rejected three of them for not summing to 25.
    @Test("serialises to the decimal it holds, not to a double's expansion")
    func serialisesExactly() throws {
        let body = ["amount": Money.requestValue(cents: 833)]
        let json = String(
            data: try JSONSerialization.data(withJSONObject: body),
            encoding: .utf8
        )

        #expect(json == #"{"amount":8.33}"#)
    }

    @Test("an equal split still reads as the total once serialised")
    func equalSplitSurvivesSerialisation() throws {
        let amounts = SplitConfiguration.equalAmounts(totalCents: 2500, among: [1, 2, 3])
        let body: [String: Any] = [
            "amount": Money.requestValue(cents: 2500),
            "splits": amounts.values.sorted().map { ["amount": Money.requestValue(cents: $0)] }
        ]

        let json = String(
            data: try JSONSerialization.data(withJSONObject: body),
            encoding: .utf8
        )!

        #expect(json.contains("8.33"))
        #expect(json.contains("8.34"))
        #expect(!json.contains("8.3300"))
        #expect(!json.contains("25.0000"))
    }

    @Test("whole amounts keep their scale")
    func wholeAmounts() {
        #expect(Money.requestValue(cents: 2500).stringValue == "25")
        #expect(Money.requestValue(cents: 1250).stringValue == "12.5")
        #expect(Money.requestValue(cents: 7).stringValue == "0.07")
    }
}
