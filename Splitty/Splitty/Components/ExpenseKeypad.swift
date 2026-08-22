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
        .padding(.horizontal, 12)
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

/// No key cap: a grey circle grows behind the glyph while the finger is down and fades out
/// after it lifts, which is the whole of the key's chrome.
private struct KeypadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 32, weight: .regular))
            .foregroundStyle(Color.expenseForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background {
                Circle()
                    .fill(Color.expenseForeground.opacity(configuration.isPressed ? 0.07 : 0))
                    .frame(width: 72, height: 72)
                    .scaleEffect(configuration.isPressed ? 1 : 0.6)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.expenseBackground)
                .frame(width: 52, height: 52)
                .background(Color.expenseAccent.opacity(isEnabled ? 1 : 0.25), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
    let pasteableCents: Int?
    let isNextEnabled: Bool
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

        // A plain view, not `UIInputView`: the keyboard style paints its own material and
        // hairline, and the pad has to be indistinguishable from the sheet above it.
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: Coordinator.keypadHeight))
        container.backgroundColor = ExpenseTheme.background
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
            pasteableCents: pasteableCents,
            isNextEnabled: isNextEnabled,
            onKey: { key in context.coordinator.parent.onKey(key) }
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        /// One action row and four digit rows, plus the padding around them.
        static let keypadHeight: CGFloat = 356

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

/// The description field, whose accessory bar carries the expense's date and the same
/// forward action the pad ends on. A real date picker rather than a "Today/Yesterday"
/// shortcut: the column accepts any date, including future ones.
struct DescriptionInputField: UIViewRepresentable {
    @Binding var text: String
    @Binding var date: Date
    @Binding var isFocused: Bool
    let placeholder: String
    let isSubmitEnabled: Bool
    let isSaving: Bool
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.font = .preferredFont(forTextStyle: .body)
        field.textColor = ExpenseTheme.foreground
        field.placeholder = placeholder
        field.returnKeyType = .done
        field.autocapitalizationType = .sentences
        field.accessibilityIdentifier = "expense.description"
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)

        let hosting = UIHostingController(rootView: accessory(context: context))
        hosting.view.backgroundColor = .clear
        context.coordinator.hosting = hosting

        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: Coordinator.accessoryHeight))
        container.backgroundColor = ExpenseTheme.background
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
            isSubmitEnabled: isSubmitEnabled,
            isSaving: isSaving,
            onSubmit: { context.coordinator.parent.onSubmit() }
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        static let accessoryHeight: CGFloat = 64

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
    let isSubmitEnabled: Bool
    let isSaving: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack {
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .accessibilityIdentifier("expense.date")

            Spacer()

            if isSaving {
                ProgressView()
                    .frame(width: 52, height: 52)
            } else {
                ForwardButton(isEnabled: isSubmitEnabled, action: onSubmit)
                    .accessibilityLabel("save")
                    .accessibilityIdentifier("expense.save")
            }
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
