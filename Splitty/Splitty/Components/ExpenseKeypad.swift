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
    let onClear: () -> Void

    @Environment(\.currency) private var currency
    @State private var clearCount = 0
    @State private var suppressNextBackspace = false

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
                // Shows the currency's separator. The amount field still stores a `.`.
                key(title: currency.decimalSeparator, identifier: ".") { onKey(.decimalPoint) }
                key(title: "0") { onKey(.digit(0)) }
                backspaceKey
            }
        }
        .padding(.bottom, 8)
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: clearCount)
    }

    private func key(
        title: String,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(KeypadKeyStyle())
        .accessibilityIdentifier("keypad.key.\(identifier ?? title)")
    }

    private var backspaceKey: some View {
        Button { backspace() } label: {
            Image(systemName: "chevron.left")
        }
        .buttonStyle(KeypadKeyStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in clear() }
        )
        .accessibilityLabel(L10n.Keypad.delete)
        .accessibilityAction(named: L10n.Keypad.clearAmount, clear)
        .accessibilityIdentifier("keypad.key.chevron.left")
    }

    private func backspace() {
        if suppressNextBackspace {
            suppressNextBackspace = false
        } else {
            onKey(.backspace)
        }
    }

    private func clear() {
        suppressNextBackspace = true
        onClear()
        clearCount += 1
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

/// The date, presented rather than parked in an accessory bar: a bar above the keyboard
/// came with a border the sheet does not otherwise have and sat flush against the keys.
/// Full size and from the bottom, it is the same gesture as everything else here.
struct ExpenseDatePicker: View {
    @Binding var date: Date
    /// The first day on offer, when there is one.
    var earliestDate: Date? = nil
    /// The Repeats choice, on an expense that may repeat. Nil hides it: a payment never
    /// repeats, and neither does an expense entered by hand once it exists.
    var repeatFrequency: Binding<ExpenseRepeat>? = nil
    /// When it ends, shown while `repeatFrequency` repeats.
    var repeatEnd: Binding<RepeatEndDraft>? = nil
    /// What a count works out to, so "12 times" can say which day the last one lands on.
    var lastExpenseDate: Date? = nil
    var repeatEndMessage: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// What the sheet holds above the button, and the button with its padding: together,
    /// the height that shows everything without scrolling.
    @State private var contentHeight: CGFloat?
    @State private var buttonHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                datePicker
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .tint(Color.accentColor)
                    .accessibilityIdentifier("expense.datePicker")

                if let repeatFrequency {
                    repeatsRow(repeatFrequency)
                }

                if let repeatEnd, showsEnd {
                    RepeatEndControl(
                        end: repeatEnd,
                        startDate: date,
                        lastExpenseDate: lastExpenseDate,
                        message: repeatEndMessage
                    )
                }
            }
            .padding([.horizontal, .top], 20)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if contentHeight == nil {
                    contentHeight = height
                } else {
                    withAnimation(.snappy) { contentHeight = height }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Pinned rather than scrolled: the sheet grows and shrinks from the top, so the
        // button stays where the thumb left it when Repeats or Ends comes and goes, and at
        // the largest text sizes the calendar scrolls behind it instead of pushing it off.
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: L10n.Common.done) { dismiss() }
                .accessibilityIdentifier("expense.datePicker.done")
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color.expenseBackground)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonHeight = $0 }
        }
        .background(Color.expenseBackground)
        // A `.height` detent sits above the home indicator, and one taller than the screen
        // stops at the largest detent; past that the scroll view takes over.
        .presentationDetents(contentHeight.map { [.height($0 + buttonHeight)] } ?? [.medium])
        .presentationCornerRadius(28)
        .presentationBackground(Color.expenseBackground)
    }

    private var showsEnd: Bool { (repeatFrequency?.wrappedValue ?? .never) != .never }

    /// Label and value side by side, until the text is large enough that the value alone
    /// fills the row; then the value goes underneath rather than off the edge.
    private func repeatsRow(_ frequency: Binding<ExpenseRepeat>) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 14))

        return layout {
            HStack(spacing: 14) {
                Image(systemName: "repeat")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(L10n.Repeat.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.expenseForeground)
            }

            if dynamicTypeSize.isAccessibilitySize {
                // The menu picker's own label cannot grow taller than a line, so a wrapped
                // "Doesn't repeat" is clipped; the same choices behind a label that wraps.
                Menu {
                    frequencyPicker(frequency)
                } label: {
                    HStack(spacing: 8) {
                        Text(frequency.wrappedValue.name)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.Repeat.title)
                    .accessibilityValue(frequency.wrappedValue.name)
                }
                .foregroundStyle(Color.expenseForeground)
                .accessibilityIdentifier("expense.repeat")
            } else {
                Spacer(minLength: 8)

                frequencyPicker(frequency)
                    .pickerStyle(.menu)
                    // A menu picker wraps its label to fit; "Doesn't repeat" reads as one value.
                    .fixedSize()
                    .tint(Color.expenseForeground)
                    .accessibilityIdentifier("expense.repeat")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.expenseForeground.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func frequencyPicker(_ frequency: Binding<ExpenseRepeat>) -> some View {
        Picker(selection: frequency) {
            ForEach(ExpenseRepeat.allCases) { frequency in
                Text(frequency.name).tag(frequency)
            }
        } label: {
            Text(L10n.Repeat.title)
        }
    }

    @ViewBuilder
    private var datePicker: some View {
        if let earliestDate {
            DatePicker(selection: $date, in: earliestDate..., displayedComponents: .date) {
                Text(L10n.Common.date)
            }
        } else {
            DatePicker(selection: $date, displayedComponents: .date) { Text(L10n.Common.date) }
        }
    }
}

/// Never, after a number of times, or on a day: three segments, and below them one row
/// that always takes the same room. A count says which day it lands on, since "12 times"
/// is a date to the server.
private struct RepeatEndControl: View {
    @Binding var end: RepeatEndDraft
    let startDate: Date
    let lastExpenseDate: Date?
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(L10n.Repeat.ends)
                    .font(.subheadline)
                    .foregroundStyle(Color.expenseForeground)
            }

            Picker(L10n.Repeat.ends, selection: $end.kind) {
                ForEach(RepeatEndKind.allCases) { kind in
                    Text(kind.name).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("expense.repeatEnd")

            detail
                .frame(height: 44)
                .animation(.spring(duration: 0.3, bounce: 0), value: end.kind)
        }
        .padding(16)
        .background(Color.expenseForeground.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var detail: some View {
        switch end.kind {
        case .never:
            Text(L10n.Repeat.untilStopped)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .afterCount:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Repeat.times(end.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.expenseForeground)
                        .contentTransition(.numericText(value: Double(end.count)))
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(message == nil ? .secondary : Color.orange)
                }
                .monospacedDigit()
                .animation(.spring(duration: 0.3, bounce: 0), value: end.count)

                Spacer(minLength: 8)

                Stepper(L10n.Repeat.times(end.count), value: $end.count, in: 1...999)
                    .labelsHidden()
                    .accessibilityIdentifier("expense.repeatEnd.count")
            }
        case .onDate:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Repeat.endDate)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.expenseForeground)
                    // The last expense, not the picked day: monthly from the 14th to the
                    // 20th of next year still lands on the 14th.
                    Text(caption)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(message == nil ? .secondary : Color.orange)
                }

                Spacer(minLength: 8)

                DatePicker(
                    L10n.Repeat.endDate,
                    selection: $end.date,
                    in: Calendar.current.startOfDay(for: startDate)...,
                    displayedComponents: .date
                )
                .labelsHidden()
                // The compact field otherwise follows the device region, not the app's
                // language, and disagrees with every other date on the form.
                .environment(\.locale, AppLanguage.currentLocale)
                .accessibilityIdentifier("expense.repeatEnd.date")
            }
        }
    }

    /// The day the last one lands on, or why the count cannot be saved.
    private var caption: String {
        if let message { return message }
        guard let lastExpenseDate else { return " " }
        return L10n.Repeat.lastOn(
            lastExpenseDate.formatted(.dateTime.day().month(.abbreviated).year().inAppLanguage())
        )
    }
}
