//
//  ExpenseSheet.swift
//  Splitty
//

import SwiftUI

/// Creates or edits an expense. The sheet opens on the amount, with the calculator pad up;
/// everything else is one row below it.
struct ExpenseSheet: View {
    @StateObject private var viewModel: ExpenseFormViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var amountFocused = false
    @State private var descriptionFocused = false
    @State private var pasteableCents: Int?

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

            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(!saveable)
                    }
                }
            }
            .presentationCornerRadius(28)
            .task {
                amountFocused = true
                pasteableCents = await ClipboardPrice.detect()
            }
        }
    }

    // MARK: - Rows

    /// The number is drawn by `AmountDisplay`; the field underneath it is an invisible
    /// responder that owns the pad. Tapping anywhere on the number focuses it.
    private var amountRow: some View {
        AmountDisplay(text: viewModel.amount.displayText)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { amountFocused = true }
            .background(alignment: .center) {
                AmountInputField(
                    pendingOperator: pendingOperator,
                    pasteableCents: pasteableCents,
                    isFocused: $amountFocused,
                    onKey: handle(key:)
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
    }

    private var descriptionRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                DescriptionInputField(
                    text: $viewModel.description,
                    date: $viewModel.date,
                    isFocused: $descriptionFocused,
                    placeholder: "What was it for?"
                )
                .frame(height: 30)

                Text(viewModel.date, format: .dateTime.weekday(.abbreviated).day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var splitRow: some View {
        NavigationLink {
            SplitConfigurationView(viewModel: viewModel)
        } label: {
            HStack {
                Text(viewModel.splitSummary)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("expense.split")
    }

    // MARK: - Behaviour

    private var pendingOperator: CalculatorOperator? {
        viewModel.amount.hasPendingExpression ? viewModel.amount.pendingOperator : nil
    }

    /// Save is available on the resolved value of the expression, pending operation and
    /// all: refusing to save a number the app can compute is a puzzle, not a safeguard.
    private var saveable: Bool { viewModel.canSave }

    private func handle(key: KeypadKey) {
        switch key {
        case .digit(let digit): viewModel.amount.type(digit: digit)
        case .decimalPoint: viewModel.amount.typeDecimalPoint()
        case .backspace: viewModel.amount.backspace()
        case .clear: viewModel.amount.clear()
        case .operation(let operation): viewModel.amount.apply(operation)
        case .equals: viewModel.amount.evaluate()
        case .pasteAmount(let cents): viewModel.amount.replaceEntry(cents: cents)
        case .next:
            // Only the destination is set: making the description first responder resigns
            // the amount by itself, and resigning both in one pass races the handoff.
            descriptionFocused = true
        }
    }

    private func save() {
        // Auto-evaluate: a pending expression is an amount the user typed, not an error.
        viewModel.amount.evaluate()

        Task {
            if let expense = await viewModel.save() {
                onSaved(expense)
                dismiss()
            }
        }
    }
}
