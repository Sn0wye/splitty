//
//  AmountDisplay.swift
//  Splitty
//

import SwiftUI

/// The hero amount.
///
/// Drawn by SwiftUI rather than by the `UITextField` that owns the keypad, which stays
/// invisible. The number is one run of text and never animates: it changes several times
/// a second while someone types, and every keystroke has to land as the latest value, not
/// as a transition still catching up with the one before it. The keypad's halo and haptic
/// are the feedback; the number is the result.
struct AmountDisplay: View {
    let text: String
    /// Currency is a static glyph — there is no currency field and no conversion.
    var currencySymbol: String = "$"
    var size: CGFloat = 76

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(text)

            // Trailing, and the same size as the digits: the symbol is part of the number
            // the way it is written, not a superscript hung off the front of it.
            Text(currencySymbol)
                .padding(.leading, size * 0.12)
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(Color.expenseForeground)
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        // Whatever animation the keystroke arrived in, the amount does not take part in it.
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    struct Demo: View {
        @State private var text = "0"

        var body: some View {
            VStack(spacing: 40) {
                AmountDisplay(text: text)
                HStack {
                    Button("2") { text = text == "0" ? "2" : text + "2" }
                    Button("5") { text = text == "0" ? "5" : text + "5" }
                    Button("⌫") { text = String(text.dropLast()); if text.isEmpty { text = "0" } }
                }
                .font(.title)
            }
        }
    }
    return Demo()
}
