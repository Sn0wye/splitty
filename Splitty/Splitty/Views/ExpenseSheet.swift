//
//  ExpenseSheet.swift
//  Splitty
//

import SwiftUI

/// Creates or edits an expense. The sheet opens on the amount, with the pad up; everything
/// else is one row below it.
struct ExpenseSheet: View {
    @StateObject private var viewModel: ExpenseFormViewModel
    @Environment(\.dismiss) private var dismiss

    @FocusState private var descriptionFocused: Bool
    @State private var pasteableCents: Int?
    @State private var showingDatePicker = false

    private let onSaved: (Expense) -> Void

    init(
        groupId: Int,
        members: [GroupMember],
        currentUserId: Int,
        expense: Expense? = nil,
        onSaved: @escaping (Expense) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ExpenseFormViewModel(
            groupId: groupId,
            members: members,
            currentUserId: currentUserId,
            expense: expense
        ))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                headerRow

                Spacer(minLength: 12)

                amountRow

                Spacer(minLength: 12)

                descriptionRow
                splitRow

                if let message = viewModel.blockingMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 8)

                // The pad is content, not a keyboard. As a keyboard it dismissed on its
                // own clock, sliding out from under a sheet that was still on screen;
                // owned by the sheet it simply travels with it.
                if !descriptionFocused {
                    ExpenseKeypad(
                        pasteableCents: pasteableCents,
                        isNextEnabled: isNextEnabled,
                        onKey: handle(key:)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The same colour the pad paints itself, so the two meet without a seam.
            .background(Color.expenseBackground)
            // No bar: the sheet's own header carries what it needs, and an empty bar over
            // the amount was only there to hold buttons that are gone.
            .toolbar(.hidden, for: .navigationBar)
            .presentationCornerRadius(28)
            .presentationBackground(Color.expenseBackground)
            .task {
                pasteableCents = await ClipboardPrice.detect()
            }
            .sheet(isPresented: $showingDatePicker) {
                ExpenseDatePicker(date: $viewModel.date)
            }
        }
    }

    // MARK: - Rows

    /// The date on the left, and — while the system keyboard is up and the pad's own arrow
    /// is off screen — the save action on the right, so there is never a moment with no way
    /// forward and never two arrows at once.
    private var headerRow: some View {
        HStack {
            Button {
                showingDatePicker = true
            } label: {
                Text(dateLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.expenseForeground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.expenseForeground.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("expense.date")

            Spacer()

            if descriptionFocused {
                if viewModel.isSaving {
                    ProgressView().frame(width: 40, height: 40)
                } else {
                    ForwardButton(isEnabled: viewModel.canSave, diameter: 40, action: save)
                        .accessibilityLabel("save")
                        .accessibilityIdentifier("expense.save")
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(viewModel.date) { return "Today" }
        if calendar.isDateInYesterday(viewModel.date) { return "Yesterday" }
        return viewModel.date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Tapping the number puts the pad back, whichever field had focus.
    private var amountRow: some View {
        AmountDisplay(text: viewModel.amount.displayText)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { descriptionFocused = false }
            .accessibilityIdentifier("expense.amount")
    }

    private var descriptionRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(Color.expenseForeground.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                TextField("What was it for?", text: $viewModel.description)
                    .focused($descriptionFocused)
                    .submitLabel(.done)
                    .foregroundStyle(Color.expenseForeground)
                    .accessibilityIdentifier("expense.description")
                    .frame(height: 30)
            }
        }
        .padding(.horizontal, 8)
    }

    private var splitRow: some View {
        NavigationLink {
            SplitConfigurationView(viewModel: viewModel)
        } label: {
            HStack {
                Text(viewModel.splitSummary)
                    .font(.subheadline)
                    .foregroundStyle(Color.expenseForeground)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.expenseForeground.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8)
        }
        .accessibilityIdentifier("expense.split")
    }

    // MARK: - Behaviour

    /// The pad's arrow only has to get you off the amount, so it lights up as soon as
    /// there is one. Saving is gated on the sheet as a whole, from the description's bar.
    private var isNextEnabled: Bool { viewModel.totalCents > 0 }

    private func handle(key: KeypadKey) {
        switch key {
        case .digit(let digit): viewModel.amount.type(digit: digit)
        case .decimalPoint: viewModel.amount.typeDecimalPoint()
        case .backspace: viewModel.amount.backspace()
        case .pasteAmount(let cents): viewModel.amount.replaceEntry(cents: cents)
        case .next:
            // Only the destination is set: making the description first responder resigns
            // the amount by itself, and resigning both in one pass races the handoff.
            descriptionFocused = true
        }
    }

    private func save() {
        guard viewModel.canSave else { return }

        Task {
            if let expense = await viewModel.save() {
                onSaved(expense)
                dismiss()
            }
        }
    }
}
