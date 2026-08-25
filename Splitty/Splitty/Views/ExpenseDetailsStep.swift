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
    let onSave: () -> Void

    @FocusState private var descriptionFocused: Bool
    @State private var showingDatePicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                descriptionRow
                splitRow
                dateRow

                if let message = viewModel.blockingMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
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
            PrimaryButton(title: "Save", isLoading: viewModel.isSaving, action: onSave)
                .disabled(!viewModel.canSave)
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
            ExpenseDatePicker(date: $viewModel.date)
        }
    }

    // MARK: - Rows

    private var descriptionRow: some View {
        HStack(spacing: 14) {
            rowIcon("text.alignleft")

            TextField("What was it for?", text: $viewModel.description)
                .focused($descriptionFocused)
                .submitLabel(.done)
                .foregroundStyle(Color.expenseForeground)
                .accessibilityIdentifier("expense.description")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.expenseForeground.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
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

    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(viewModel.date) { return "Today" }
        if calendar.isDateInYesterday(viewModel.date) { return "Yesterday" }
        return viewModel.date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
