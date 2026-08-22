//
//  ExpenseKeypad.swift
//  Splitty
//

import DataDetection
import SwiftUI
import UIKit

/// Everything the pad can send back to the amount field.
enum KeypadKey: Equatable {
    case digit(Int)
    case decimalPoint
    case backspace
    case pasteAmount(cents: Int)
    case next
}

// MARK: - The pad

/// The amount field's keyboard: borderless glyphs on the sheet's own background, with a
/// circular press halo instead of a key cap.
///
/// Digits only. The arithmetic keys are gone: they turned a two-tap amount into a mode the
/// user had to reason about, and the expression model still resolves whatever is typed.
struct ExpenseKeypad: View {
    let pasteableCents: Int?
    let isNextEnabled: Bool
    let onKey: (KeypadKey) -> Void

    private let digitRows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        VStack(spacing: 2) {
            actionRow

            ForEach(digitRows, id: \.first) { row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { digit in
                        key(title: "\(digit)") { onKey(.digit(digit)) }
                    }
                }
            }

            HStack(spacing: 0) {
                key(title: ".") { onKey(.decimalPoint) }
                key(title: "0") { onKey(.digit(0)) }
                key(systemImage: "chevron.left", label: "delete") { onKey(.backspace) }
            }
        }
        .padding(.bottom, 8)
    }

    /// The pad's only non-digit: the clipboard price on the left, and the forward action
    /// sitting above the column it belongs to.
    private var actionRow: some View {
        HStack(spacing: 12) {
            if let pasteableCents {
                Button {
                    onKey(.pasteAmount(cents: pasteableCents))
                } label: {
                    Label("Paste \(Money.formatted(cents: pasteableCents))", systemImage: "doc.on.clipboard")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.expenseForeground.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("keypad.paste")
            }

            Spacer(minLength: 0)

            ForwardButton(isEnabled: isNextEnabled) { onKey(.next) }
                .accessibilityLabel("next")
                .accessibilityIdentifier("keypad.next")
                .frame(width: 76)
        }
        .frame(height: 60)
        .padding(.horizontal, 8)
    }

    private func key(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(KeypadKeyStyle())
        .accessibilityIdentifier("keypad.key.\(title)")
    }

    private func key(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(KeypadKeyStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier("keypad.key.\(systemImage)")
    }
}

/// No key cap: a grey circle fades in behind the glyph while the finger is down and fades
/// out after it lifts, which is the whole of the key's chrome. It does not grow — the disc
/// is always full size, so the only thing moving under the finger is opacity.
private struct KeypadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 32, weight: .medium, design: .rounded))
            .foregroundStyle(Color.expenseForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background {
                Circle()
                    .fill(Color.expenseForeground.opacity(configuration.isPressed ? 0.07 : 0))
                    .frame(width: 72, height: 72)
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: configuration.isPressed ? 0.08 : 0.2), value: configuration.isPressed)
    }
}

/// The sheet's primary action, and the only filled control on it: a solid disc in the
/// foreground colour with the arrow punched out of it, so it reads white-on-black or
/// black-on-white without a second asset.
struct ForwardButton: View {
    let isEnabled: Bool
    var diameter: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.right")
                .font(.system(size: diameter * 0.38, weight: .semibold))
                .foregroundStyle(Color.expenseBackground)
                .frame(width: diameter, height: diameter)
                .background(Color.expenseAccent.opacity(isEnabled ? 1 : 0.25), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// The date, presented rather than parked in an accessory bar: a bar above the keyboard
/// came with a border the sheet does not otherwise have and sat flush against the keys.
/// Full size and from the bottom, it is the same gesture as everything else here.
struct ExpenseDatePicker: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.graphical)
                .tint(Color.expenseAccent)
                .accessibilityIdentifier("expense.datePicker")

            ForwardButton(isEnabled: true, diameter: 44) { dismiss() }
                .accessibilityLabel("done")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.expenseBackground)
        .presentationDetents([.height(460)])
        .presentationCornerRadius(28)
        .presentationBackground(Color.expenseBackground)
    }
}

// MARK: - Clipboard

/// The price on the clipboard, if there is one.
///
/// The deployment target is 18.2, so there is no pre-detection fallback to write: either
/// the system finds a money amount or the chip does not appear.
enum ClipboardPrice {
    static func detect() async -> Int? {
        guard let match = try? await UIPasteboard.general
            .detectedValues(for: [\.moneyAmounts])
            .moneyAmounts
            .first
        else { return nil }

        let cents = Money.cents(from: match.amount)
        return cents > 0 ? cents : nil
    }
}
