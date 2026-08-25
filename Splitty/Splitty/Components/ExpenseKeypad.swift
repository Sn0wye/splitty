//
//  ExpenseKeypad.swift
//  Splitty
//

import SwiftUI
import UIKit

/// Everything the pad can send back to the amount field.
///
/// Digits and nothing else. The pad used to carry the screen's forward action in a row
/// above the keys, which made it the one control that had to outlive the surface it sat
/// on; the amount screen owns that button now, where it can be the shape a primary action
/// should be.
enum KeypadKey: Equatable {
    case digit(Int)
    case decimalPoint
    case backspace
}

// MARK: - The pad

/// The amount field's keyboard: borderless glyphs on the sheet's own background, with a
/// circular press halo instead of a key cap.
///
/// Digits only. The arithmetic keys are gone: they turned a two-tap amount into a mode the
/// user had to reason about, and the expression model still resolves whatever is typed.
struct ExpenseKeypad: View {
    let onKey: (KeypadKey) -> Void

    private let digitRows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        VStack(spacing: 2) {
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
            // On the press, with the halo, not on the release: the tap is the causal event
            // and the two senses have to land on the same frame. Soft and half intensity —
            // this fires several times per amount, and a full impact per digit is a drum.
            .sensoryFeedback(
                .impact(flexibility: .soft, intensity: 0.4),
                trigger: configuration.isPressed
            ) { _, isPressed in isPressed }
    }
}

/// The sheet's primary action. Glass where the system has it, so it picks up the material
/// and the press behaviour of every other prominent control on the OS; a flat disc in the
/// accent colour before that.
struct ForwardButton: View {
    let isEnabled: Bool
    var diameter: CGFloat = 44
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            // The material, not the button style: `.glassProminent` morphs and rescales the
            // capsule under the finger, which on a 44pt disc reads as the button wobbling.
            Button(action: action) {
                glyph
                    .frame(width: diameter, height: diameter)
                    .glassEffect(
                        .regular.tint(Color.expenseAccent.opacity(isEnabled ? 1 : 0.3)),
                        in: .circle
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        } else {
            Button(action: action) {
                glyph
                    .frame(width: diameter, height: diameter)
                    .background(Color.expenseAccent.opacity(isEnabled ? 1 : 0.25), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }

    private var glyph: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: diameter * 0.38, weight: .semibold))
            .foregroundStyle(Color.expenseBackground)
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
