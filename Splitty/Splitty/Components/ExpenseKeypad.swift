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

/// The amount field's keyboard: a calculator row above a numeric pad, plus a clipboard
/// price chip when there is one to offer.
struct ExpenseKeypad: View {
    let pendingOperator: CalculatorOperator?
    let pasteableCents: Int?
    let onKey: (KeypadKey) -> Void

    private let digitRows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        VStack(spacing: 8) {
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
            }

            calculatorRow

            HStack(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(digitRows, id: \.first) { row in
                        HStack(spacing: 8) {
                            ForEach(row, id: \.self) { digit in
                                key("\(digit)") { onKey(.digit(digit)) }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        key(".") { onKey(.decimalPoint) }
                        key("0") { onKey(.digit(0)) }
                        key(systemImage: "delete.left") { onKey(.backspace) }
                    }
                }

                VStack(spacing: 8) {
                    key("C", tint: .secondary) { onKey(.clear) }
                    key("=", tint: .accentColor) { onKey(.equals) }
                    Button {
                        onKey(.next)
                    } label: {
                        Text("Next")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("keypad.next")
                }
                .frame(width: 88)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    private var calculatorRow: some View {
        HStack(spacing: 8) {
            ForEach(CalculatorOperator.allCases, id: \.self) { operation in
                Button {
                    onKey(.operation(operation))
                } label: {
                    Text(operation.symbol)
                        .font(.title3.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            pendingOperator == operation ? Color.accentColor : Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .foregroundStyle(pendingOperator == operation ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("keypad.operator.\(operation.symbol)")
            }
        }
    }

    private func key(_ title: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("keypad.key.\(title)")
    }

    private func key(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("keypad.key.\(systemImage)")
    }
}

// MARK: - The amount field

/// The amount field is a real `UITextField` whose `inputView` is the pad above.
///
/// Not a SwiftUI `TextField` with `.decimalPad` and an accessory bar: a real responder is
/// what gives the field a caret and makes moving focus to the description swap the pad for
/// the system keyboard, both without any code.
struct AmountInputField: UIViewRepresentable {
    let text: String
    let pendingOperator: CalculatorOperator?
    let pasteableCents: Int?
    @Binding var isFocused: Bool
    let onKey: (KeypadKey) -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 40, weight: .semibold)
        field.textColor = .label
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 22
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

    private func keypad(context: Context) -> ExpenseKeypad {
        ExpenseKeypad(
            pendingOperator: pendingOperator,
            pasteableCents: pasteableCents,
            onKey: { key in context.coordinator.parent.onKey(key) }
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        static let keypadHeight: CGFloat = 300

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
