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
    case clear
    case operation(CalculatorOperator)
    case equals
    case pasteAmount(cents: Int)
    case next
}

// MARK: - The pad

/// The amount field's keyboard: borderless glyphs on the sheet's own background, with a
/// circular press halo instead of a key cap. A calculator row sits above the digits,
/// styled the same way so it reads as part of the pad rather than a toolbar bolted to it.
struct ExpenseKeypad: View {
    let pendingOperator: CalculatorOperator?
    let pasteableCents: Int?
    let onKey: (KeypadKey) -> Void

    private let digitRows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        VStack(spacing: 4) {
            if let pasteableCents {
                Button {
                    onKey(.pasteAmount(cents: pasteableCents))
                } label: {
                    Label("Paste \(Money.formatted(cents: pasteableCents))", systemImage: "doc.on.clipboard")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("keypad.paste")
                .padding(.bottom, 4)
            }

            calculatorRow

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
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    /// The pending operator stays lit, so a half-typed expression is legible from the pad
    /// itself rather than only from the amount.
    private var calculatorRow: some View {
        HStack(spacing: 0) {
            ForEach(CalculatorOperator.allCases, id: \.self) { operation in
                key(title: operation.symbol, isOn: pendingOperator == operation) {
                    onKey(.operation(operation))
                }
                .accessibilityIdentifier("keypad.operator.\(operation.symbol)")
            }
            key(title: "=") { onKey(.equals) }
            key(systemImage: "arrow.forward", label: "next") { onKey(.next) }
                .accessibilityIdentifier("keypad.next")
        }
        .font(.system(size: 24, weight: .regular))
    }

    private func key(
        title: String,
        isOn: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(KeypadKeyStyle(isOn: isOn))
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
        .buttonStyle(KeypadKeyStyle(isOn: false))
        .accessibilityLabel(label)
        .accessibilityIdentifier("keypad.key.\(systemImage)")
    }
}

/// No key cap: a grey circle grows behind the glyph while the finger is down and fades out
/// after it lifts, which is the whole of the key's chrome.
private struct KeypadKeyStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 34, weight: .regular))
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background {
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed || isOn ? 0.07 : 0))
                    .frame(width: 72, height: 72)
                    .scaleEffect(configuration.isPressed || isOn ? 1 : 0.6)
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: configuration.isPressed ? 0.08 : 0.2), value: configuration.isPressed)
    }
}

// MARK: - The amount field

/// The responder behind the amount: a real `UITextField` whose `inputView` is the pad
/// above, kept invisible because `AmountDisplay` draws the number.
///
/// Not a SwiftUI `TextField` with `.decimalPad` and an accessory bar: a real responder is
/// what makes moving focus to the description swap the pad for the system keyboard,
/// without any code. It renders nothing itself — a text field draws its text as one opaque
/// run, and the digits have to animate one at a time.
struct AmountInputField: UIViewRepresentable {
    let pendingOperator: CalculatorOperator?
    let pasteableCents: Int?
    @Binding var isFocused: Bool
    let onKey: (KeypadKey) -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.tintColor = .clear
        field.textColor = .clear
        field.backgroundColor = .clear
        field.isAccessibilityElement = false
        field.accessibilityIdentifier = "expense.amount"

        let hosting = UIHostingController(rootView: keypad(context: context))
        hosting.view.backgroundColor = .clear
        context.coordinator.hosting = hosting

        let container = UIInputView(
            frame: CGRect(x: 0, y: 0, width: 320, height: Coordinator.keypadHeight),
            inputViewStyle: .keyboard
        )
        container.autoresizingMask = .flexibleWidth
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(hosting.view)
        field.inputView = container

        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hosting?.rootView = keypad(context: context)

        // Deferred: changing the first responder inside a SwiftUI update is a change the
        // system may drop, and the handoff to the description is exactly that case.
        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isFocused, uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func keypad(context: Context) -> ExpenseKeypad {
        ExpenseKeypad(
            pendingOperator: pendingOperator,
            pasteableCents: pasteableCents,
            onKey: { key in context.coordinator.parent.onKey(key) }
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        /// Five borderless rows, each 64pt, plus the padding around them.
        static let keypadHeight: CGFloat = 360

        var parent: AmountInputField
        var hosting: UIHostingController<ExpenseKeypad>?

        init(parent: AmountInputField) {
            self.parent = parent
        }

        /// Every character arrives through the pad. Hardware keyboards and dictation would
        /// otherwise write text the expression knows nothing about.
        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            let isFocused = parent.$isFocused
            DispatchQueue.main.async { isFocused.wrappedValue = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            let isFocused = parent.$isFocused
            DispatchQueue.main.async { isFocused.wrappedValue = false }
        }
    }
}

// MARK: - The description field

/// The description field, whose accessory bar carries the expense's date. A real date
/// picker rather than a "Today/Yesterday" shortcut: the column accepts any date, including
/// future ones.
struct DescriptionInputField: UIViewRepresentable {
    @Binding var text: String
    @Binding var date: Date
    @Binding var isFocused: Bool
    let placeholder: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.font = .preferredFont(forTextStyle: .body)
        field.placeholder = placeholder
        field.returnKeyType = .done
        field.autocapitalizationType = .sentences
        field.accessibilityIdentifier = "expense.description"
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)

        let hosting = UIHostingController(rootView: accessory(context: context))
        hosting.view.backgroundColor = .clear
        context.coordinator.hosting = hosting

        let container = UIInputView(
            frame: CGRect(x: 0, y: 0, width: 320, height: Coordinator.accessoryHeight),
            inputViewStyle: .keyboard
        )
        container.autoresizingMask = .flexibleWidth
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(hosting.view)
        field.inputAccessoryView = container

        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hosting?.rootView = accessory(context: context)

        if uiView.text != text {
            uiView.text = text
        }

        // Deferred: changing the first responder inside a SwiftUI update is a change the
        // system may drop, and the handoff to the description is exactly that case.
        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isFocused, uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func accessory(context: Context) -> ExpenseDateAccessory {
        ExpenseDateAccessory(
            date: Binding(
                get: { context.coordinator.parent.date },
                set: { context.coordinator.parent.date = $0 }
            ),
            onDone: { context.coordinator.parent.isFocused = false }
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        static let accessoryHeight: CGFloat = 48

        var parent: DescriptionInputField
        var hosting: UIHostingController<ExpenseDateAccessory>?

        init(parent: DescriptionInputField) {
            self.parent = parent
        }

        @objc func editingChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            let isFocused = parent.$isFocused
            DispatchQueue.main.async { isFocused.wrappedValue = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            let isFocused = parent.$isFocused
            DispatchQueue.main.async { isFocused.wrappedValue = false }
        }
    }
}

struct ExpenseDateAccessory: View {
    @Binding var date: Date
    let onDone: () -> Void

    var body: some View {
        HStack {
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .accessibilityIdentifier("expense.date")

            Spacer()

            Button("Done", action: onDone)
                .font(.body.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
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
