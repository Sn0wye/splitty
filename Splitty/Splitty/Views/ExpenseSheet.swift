//
//  ExpenseSheet.swift
//  Splitty
//

import SwiftUI
import UIKit

/// Creates or edits an expense. The sheet opens on the amount, with the pad up; everything
/// else is one row below it.
struct ExpenseSheet: View {
    @StateObject private var viewModel: ExpenseFormViewModel
    @Environment(\.dismiss) private var dismiss

    @FocusState private var descriptionFocused: Bool
    @State private var showingDatePicker = false
    @State private var keyboardInset: CGFloat = 0

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
            ZStack(alignment: .bottom) {
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

                    // Held open whether the pad is showing its digits or not, so opening
                    // the keyboard moves nothing above it.
                    Color.clear.frame(height: Self.padHeight)
                }
                // The content above the pad is anchored to the sheet, not to the keyboard:
                // letting the system lift it as well produced two shifts at once.
                .ignoresSafeArea(.keyboard, edges: .bottom)

                // The pad is content, not a keyboard. As a keyboard it dismissed on its
                // own clock, sliding out from under a sheet that was still on screen;
                // owned by the sheet it simply travels with it. Its action row survives
                // the system keyboard and rides above it, so the arrow stays put.
                ExpenseKeypad(
                    isNextEnabled: isNextEnabled,
                    isSaving: viewModel.isSaving,
                    showsDigits: !descriptionFocused,
                    onKey: handle(key:)
                )
                .padding(.bottom, padBottomInset)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The keyboard is answered by hand, below: letting SwiftUI lift the sheet moved
            // the pad outside the bounds it is hit-tested against, so the arrow drew in the
            // right place and answered to nothing.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // The same colour the pad paints itself, so the two meet without a seam.
            .background(Color.expenseBackground)
            // No bar: the sheet's own header carries what it needs, and an empty bar over
            // the amount was only there to hold buttons that are gone.
            .toolbar(.hidden, for: .navigationBar)
            .presentationCornerRadius(28)
            .presentationBackground(Color.expenseBackground)
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification
            )) { note in
                setKeyboardInset(from: note)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification
            )) { _ in
                withAnimation(.easeOut(duration: 0.25)) { keyboardInset = 0 }
            }
            .sheet(isPresented: $showingDatePicker) {
                ExpenseDatePicker(date: $viewModel.date)
            }
        }
    }

    // MARK: - Rows

    /// The date, and nothing else: the forward action stays with the pad at the bottom of
    /// the sheet whether the pad or the keyboard is up.
    private var headerRow: some View {
        HStack {
            dateButton
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var dateButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                showingDatePicker = true
            } label: {
                Text(dateLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.expenseForeground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("expense.date")
        } else {
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
        }
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

    /// One action row and four digit rows, plus the padding under them. Reserved in the
    /// layout at all times: the pad shrinks to the action row when the keyboard takes over,
    /// and nothing above it is allowed to notice.
    private static let digitsHeight: CGFloat = 4 * 68 + 2 * 3
    private static let padHeight: CGFloat = 60 + digitsHeight + 8

    /// The keyboard covers the digit grid, which is hidden under it anyway, so only the
    /// part of it that reaches past the grid moves the pad. Ignored unless the description
    /// is what the keyboard belongs to: the split screen raises one of its own, and acting
    /// on that left the pad hoisted over the sheet on the way back.
    private var padBottomInset: CGFloat {
        guard descriptionFocused else { return 0 }
        return max(0, keyboardInset - Self.digitsHeight)
    }

    /// How far the keyboard reaches into the sheet, past the home indicator the sheet
    /// already clears.
    private func setKeyboardInset(from note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window = UIApplication.shared.connectedScenes
                  .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                  .first
        else { return }

        let overlap = max(0, window.bounds.maxY - frame.minY - window.safeAreaInsets.bottom)
        withAnimation(.easeOut(duration: 0.25)) { keyboardInset = overlap }
    }

    /// One arrow, two jobs: leaving the amount only needs an amount, but once the
    /// description has focus the arrow is the save and answers to the whole sheet.
    private var isNextEnabled: Bool {
        descriptionFocused ? viewModel.canSave : viewModel.totalCents > 0
    }

    private func handle(key: KeypadKey) {
        switch key {
        case .digit(let digit): viewModel.amount.type(digit: digit)
        case .decimalPoint: viewModel.amount.typeDecimalPoint()
        case .backspace: viewModel.amount.backspace()
        case .next:
            if descriptionFocused {
                save()
            } else {
                descriptionFocused = true
            }
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
