//
//  AmountDisplay.swift
//  Splitty
//

import SwiftUI

/// The hero amount, drawn one glyph at a time so a digit can animate in on its own.
///
/// A `UITextField` renders its text as a single opaque run, so the field that owns the
/// keypad stays invisible and this draws what it holds: each character is a separate view
/// with a stable identity, which is what lets SwiftUI move the digits that stayed and
/// transition only the one that changed.
struct AmountDisplay: View {
    let text: String
    /// Currency is a static glyph — there is no currency field and no conversion.
    var currencySymbol: String = "$"
    var size: CGFloat = 76

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(glyphs, id: \.id) { glyph in
                Text(glyph.character)
                    .transition(.asymmetric(
                        insertion: AnyTransition(BlurPushTransition(from: .below)),
                        removal: AnyTransition(BlurPushTransition(from: .above))
                    ))
            }

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
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: text)
    }

    /// Identity is position **and** character: appending leaves the earlier glyphs alone,
    /// while replacing one retires the old glyph and introduces the new one in its place.
    private var glyphs: [Glyph] {
        text.enumerated().map { index, character in
            Glyph(id: "\(index)-\(character)", character: String(character))
        }
    }

    private struct Glyph {
        let id: String
        let character: String
    }
}

/// A glyph arrives from below and leaves upward, blurring and shrinking at the far end of
/// the travel — the motion blur a number picks up when it moves that fast.
struct BlurPushTransition: Transition {
    enum Origin {
        case below
        case above

        var offset: CGFloat {
            switch self {
            case .below: return 0.45
            case .above: return -0.45
            }
        }
    }

    let from: Origin

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .blur(radius: phase.isIdentity ? 0 : 9)
            .scaleEffect(phase.isIdentity ? 1 : 0.55, anchor: .center)
            .offset(y: phase.isIdentity ? 0 : from.offset * 90)
            .opacity(phase.isIdentity ? 1 : 0)
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
