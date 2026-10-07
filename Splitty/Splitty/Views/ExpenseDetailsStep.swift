//
//  ExpenseDetailsStep.swift
//  Splitty
//

import SwiftUI

/// The second step: what the money was for, who it splits between, and when.
///
/// Its own view rather than a property on the sheet, because focus is scoped to the view
/// that declares it. A `@FocusState` on the presenting screen does not reach a field inside
/// a `navigationDestination` — the pushed screen is a separate focus scope, and a binding
/// handed across that boundary silently does nothing.
struct ExpenseDetailsStep: View {
    @ObservedObject var viewModel: ExpenseFormViewModel
    /// Called once Save is allowed, with the answer to the scope prompt when one was asked.
    let onSave: (ExpenseScope?) -> Void

    @FocusState private var descriptionFocused: Bool
    @State private var showingDatePicker = false
    @State private var showingScopeChoice = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                descriptionRow
                if let message = viewModel.descriptionRequiredMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("expense.description-error")
                }
                categoryRow
                splitRow
                if let message = viewModel.blockingMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                dateRow
                if let message = viewModel.repeatDateMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.expenseBackground)
        // Save rides above the keyboard because SwiftUI's own avoidance puts it there. This
        // screen does not opt out of that, so there is nothing left to measure.
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: L10n.Common.save, isLoading: viewModel.isSaving, action: save)
                .disabled(viewModel.isSaving)
                .accessibilityIdentifier("expense.save")
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color.expenseBackground)
        }
        .navigationTitle(Money.formatted(cents: viewModel.totalCents))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.expenseBackground, for: .navigationBar)
        // The field is the whole point of arriving here, so it is already waiting. Asked for
        // after the push rather than during it: a focus request made while the transition is
        // still running is one SwiftUI drops.
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            descriptionFocused = true
        }
        .sheet(isPresented: $showingDatePicker) {
            ExpenseDatePicker(
                date: $viewModel.date,
                earliestDate: viewModel.earliestDate,
                repeatFrequency: viewModel.showsRepeatPicker ? $viewModel.repeatFrequency : nil
            )
        }
        .alert(L10n.Repeat.saveTitle, isPresented: $showingScopeChoice) {
            Button { onSave(.this) } label: { Text(L10n.Repeat.onlyThis) }
                .accessibilityIdentifier("expense.save.only-this")
            Button { onSave(.following) } label: { Text(L10n.Repeat.thisAndFollowing) }
                .accessibilityIdentifier("expense.save.following")
            Button(role: .cancel) {} label: { Text(L10n.Common.cancel) }
        } message: {
            Text(L10n.Repeat.saveMessage)
        }
    }

    /// An expense a recurring expense added asks how far the change reaches before
    /// saving, unless the answer is already implied.
    private func save() {
        guard viewModel.attemptSave() else { return }
        if viewModel.needsScopeChoice {
            descriptionFocused = false
            showingScopeChoice = true
        } else {
            onSave(nil)
        }
    }

    // MARK: - Rows

    private var descriptionRow: some View {
        HStack(spacing: 14) {
            rowIcon("text.alignleft")

            TextField(L10n.Expense.whatFor, text: $viewModel.description)
                .focused($descriptionFocused)
                .submitLabel(.done)
                .foregroundStyle(Color.expenseForeground)
                .accessibilityIdentifier("expense.description")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.expenseForeground.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if viewModel.descriptionRequiredMessage != nil {
                RoundedRectangle(cornerRadius: 14).stroke(.red, lineWidth: 1)
            }
        }
    }

    private var splitRow: some View {
        NavigationLink {
            SplitConfigurationView(viewModel: viewModel)
        } label: {
            HStack(spacing: 14) {
                rowIcon("person.2")

                Text(viewModel.splitSummary)
                    .font(.subheadline)
                    .foregroundStyle(Color.expenseForeground)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.expenseForeground.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.pressable(scale: 0.98))
        .accessibilityIdentifier("expense.split")
    }

    private var categoryRow: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(viewModel.categorySuggestions) { category in
                        Button {
                            viewModel.category = viewModel.category == category ? .general : category
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.glyph)
                                Text(category.name)
                                if viewModel.category == category {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.bold))
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                viewModel.category == category
                                    ? Color.expenseBackground
                                    : Color.expenseForeground.opacity(0.72)
                            )
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(
                                viewModel.category == category
                                    ? Color.expenseForeground
                                    : Color.expenseForeground.opacity(0.08),
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable(scale: 0.96))
                        .accessibilityAddTraits(viewModel.category == category ? .isSelected : [])
                    }
                }
                .padding(.trailing, 14)
            }
            .scrollIndicators(.hidden)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }

            NavigationLink {
                ExpenseCategoryPickerView(selection: $viewModel.category)
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.expenseForeground)
                    .frame(width: 36, height: 36)
                    .background(
                        Color.expenseForeground.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.pressable(scale: 0.94))
            .accessibilityIdentifier("expense.category-picker")
        }
        .padding(.vertical, 8)
    }

    private var dateRow: some View {
        Button {
            descriptionFocused = false
            showingDatePicker = true
        } label: {
            HStack(spacing: 14) {
                rowIcon("calendar")

                Text(dateLabel)
                    .font(.subheadline)
                    .foregroundStyle(Color.expenseForeground)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.expenseForeground.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.pressable(scale: 0.98))
        .accessibilityIdentifier("expense.date")
    }

    private func rowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
            .frame(width: 24)
    }

    /// The day, then how often it repeats when it does.
    private var dateLabel: String {
        guard let badge = viewModel.repeatFrequency.badge else { return dayLabel }
        return "\(dayLabel) · \(badge)"
    }

    private var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(viewModel.date) { return L10n.Common.today }
        if calendar.isDateInYesterday(viewModel.date) { return L10n.Common.yesterday }
        return viewModel.date.formatted(.dateTime.day().month(.abbreviated).year().inAppLanguage())
    }
}
