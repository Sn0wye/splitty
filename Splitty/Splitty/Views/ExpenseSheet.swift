//
//  ExpenseSheet.swift
//  Splitty
//

import SwiftUI

/// Creates or edits an expense, in two steps: the amount, then everything about it.
///
/// One screen, one input surface. The amount screen belongs to the pad and the details
/// screen belongs to the system keyboard, and because they are different screens the two
/// can never contend for the bottom of the sheet. Everything that used to be needed to
/// arbitrate between them — reserved gaps, reconstructed keyboard heights, a forward button
/// that had to survive both — stopped being needed when the contention did.
///
/// It is also how money apps are shaped: the amount is a decision worth its own screen, and
/// what the money was for is a different decision.
struct ExpenseSheet: View {
    @StateObject private var viewModel: ExpenseFormViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingDetails = false
    /// Bumped once the server has the expense, so the success texture fires on the save
    /// landing rather than on the tap that asked for it.
    @State private var savedCount = 0

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
            amountStep
                .navigationDestination(isPresented: $showingDetails) {
                    ExpenseDetailsStep(viewModel: viewModel, onSave: save)
                }
        }
        .presentationCornerRadius(28)
        .presentationBackground(Color.expenseBackground)
        .sensoryFeedback(.success, trigger: savedCount)
    }

    // MARK: - Step one: the amount

    /// Nothing but the number and the keys that change it.
    ///
    /// `Spacer`s are safe here in a way they were not before: this screen has no keyboard,
    /// so the box the amount centres in never changes size and the number never moves.
    private var amountStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            AmountDisplay(text: viewModel.amount.displayText)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("expense.amount")

            Spacer(minLength: 0)

            PrimaryButton(title: "Next") {
                showingDetails = true
            }
            .disabled(viewModel.totalCents == 0)
            .accessibilityIdentifier("expense.next")
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            ExpenseKeypad(onKey: handle(key:))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.expenseBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.expenseBackground, for: .navigationBar)
        .toolbar {
            // The way out. A sheet with no visible dismiss leaves the drag gesture as the
            // only exit, which is not something to have to discover.
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Color.expenseForeground)
                    .accessibilityIdentifier("expense.cancel")
            }
        }
    }

    // MARK: - Behaviour

    private func handle(key: KeypadKey) {
        switch key {
        case .digit(let digit): viewModel.amount.type(digit: digit)
        case .decimalPoint: viewModel.amount.typeDecimalPoint()
        case .backspace: viewModel.amount.backspace()
        }
    }

    private func save() {
        guard viewModel.canSave else { return }

        Task {
            if let expense = await viewModel.save() {
                savedCount += 1
                onSaved(expense)
                dismiss()
            }
        }
    }
}
