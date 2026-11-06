import Foundation
import Testing
@testable import Splitty

/// `Expense.parseTimestamp` reads the API's shapes by hand before trying the formatters.
/// Every instant it produces has to be the one the formatters produce, to the bit.
struct TimestampParsingTests {
    /// A deterministic generator, so a failure names a value that reproduces.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static func samples() -> [String] {
        var random = SplitMix(state: 2026)
        let zones = ["Z", "", "+00:00", "-03:00", "+05:30", "+14:00", "-12:00", "+02:45"]
        var values: [String] = []
        for _ in 0..<4_000 {
            let year = Int.random(in: 1890...2110, using: &random)
            let month = Int.random(in: 1...12, using: &random)
            let day = Int.random(in: 1...31, using: &random)
            let hour = Int.random(in: 0...23, using: &random)
            let minute = Int.random(in: 0...59, using: &random)
            let second = Int.random(in: 0...59, using: &random)
            let fractionDigits = Int.random(in: 0...9, using: &random)
            var fraction = ""
            if fractionDigits > 0 {
                fraction = "." + (0..<fractionDigits).map { _ in String(Int.random(in: 0...9, using: &random)) }.joined()
            }
            let zone = zones[Int.random(in: 0..<zones.count, using: &random)]
            values.append(String(format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second) + fraction + zone)
        }
        return values
    }

    /// Shapes the hand reader leaves to the formatters, each of which they read their own way.
    private static let unusual = [
        "2025-02-30T13:53:41Z", "2025-02-02T24:00:00Z", "2025-02-02T13:53:60Z",
        "2025-02-02t13:53:41z", "2025-02-02T13:53:41+0200", "2025-02-02T13:53:41.Z",
        "0001-01-01T00:00:00Z", "1582-10-10T00:00:00Z", "2025-02-02 13:53:41Z",
        "2025-02-02T13:53:41.950093", "2025-02-02T13:53:41", "2025-02-02", "", "garbage",
        "2025-02-02T13:53:41.123Z ", "2025-02-02T13:53:41+15:00", "2024-02-29T00:00:00Z",
        "2023-02-29T00:00:00Z", "2000-02-29T23:59:59.999Z", "1900-02-29T00:00:00Z",
    ]

    @Test func everyShapeReadsToTheFormattersInstant() {
        var read = 0
        for value in Self.samples() + Self.unusual {
            if Expense.readTimestamp(value) != nil { read += 1 }
            #expect(Expense.parseTimestamp(value) == Expense.parseTimestampWithFormatters(value), "\(value)")
        }
        // Most generated values are valid dates the hand reader takes; the rest prove the fallback.
        #expect(read > 3_000)
    }

    @Test func theAPIsShapesTakeTheFastPath() {
        for value in ["2026-01-01T12:00:00Z", "2025-02-02T13:53:41.950093Z", "2026-04-12T12:00:00.5-03:00", "2026-04-12T12:00:00"] {
            #expect(Expense.readTimestamp(value) != nil, "\(value)")
        }
    }

    /// Evidence rather than a gate: a 500-row timeline's timestamps, both ways.
    @Test func readingByHandIsCheaperThanTheFormatters() {
        let values = (0..<500).map { String(format: "2026-01-%02dT12:%02d:00.%06dZ", $0 % 28 + 1, $0 % 60, $0 * 997) }
        let clock = ContinuousClock()
        let formatters = clock.measure { for value in values { _ = Expense.parseTimestampWithFormatters(value) } }
        let byHand = clock.measure { for value in values { _ = Expense.parseTimestamp(value) } }
        print("Timestamp parsing, 500 values: formatters \(formatters), by hand \(byHand)")
        #expect(byHand < formatters)
    }
}
