//
//  ExpenseDetailView.swift
//  Splitty
//

import SwiftUI

/// A read-only view of one expense: the total, who paid, and every split. Editing reopens
/// the same sheet that created it.
struct ExpenseDetailView: View {
    let expense: Expense
    let members: [GroupMember]
    let currentUserId: Int
    let onChanged: () -> Void
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    MemberAvatar(display: payerDisplay, size: 48)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(expense.description)
                            .font(.title2.weight(.semibold))
                        Text(Money.formatted(amount: expense.amount))
                            .font(.largeTitle.weight(.bold))
                            .monospacedDigit()
                        Text(L10n.Expense.payerPaidDate(payerName, dateText))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(splitHeader) {
                ForEach(expense.splits) { split in
                    let display = display(for: split.userId)
                    HStack {
                        MemberAvatar(display: display)
                        Text(display.name)
                            .foregroundStyle(display.isRemoved ? Color("muted-foreground") : Color("foreground"))
                        Spacer()
                        // A percentage split shows the share it was written as next to the
                        // money it came to: the payoff for storing the mode is that
                        // reopening an expense answers "how was this split?".
                        if let percentage = split.percentage, expense.splitMode == .percentage {
                            Text("\(Percent.string(Percent.value(from: percentage)))%")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                        Text(Money.formatted(amount: split.amount))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

        }
        .navigationTitle(Text(L10n.Expense.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isDeleting {
                    ProgressView()
                } else {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(L10n.Expense.deleteA11y)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingEditSheet = true } label: { Text(L10n.Common.edit) }
                    .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            ExpenseSheet(
                groupId: expense.groupId,
                members: members,
                currentUserId: currentUserId,
                expense: expense
            ) { _ in
                onChanged()
                dismiss()
            }
        }
        // Every member may delete anything, so the confirmation names what is going, not
        // who recorded it.
        .confirmationDialog(
            L10n.Expense.deleteTitle(expense.description),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) { delete() } label: { Text(L10n.Common.delete) }
            Button(role: .cancel) {} label: { Text(L10n.Common.cancel) }
        } message: {
            Text(L10n.Expense.deleteMessage)
        }
    }

    /// The stored mode, said once above the rows rather than repeated on each of them.
    private var splitHeader: String {
        switch expense.splitMode {
        case .equal: return L10n.Expense.splitEqually
        case .custom: return L10n.Expense.splitByAmounts
        case .percentage: return L10n.Expense.splitByPercentages
        case .none: return L10n.Expense.split
        }
    }

    private var payerName: String {
        expense.paidBy == currentUserId ? L10n.Common.you : payerDisplay.name
    }

    private var payerDisplay: MemberDisplay {
        MemberDisplay(
            expense.paidByUser,
            currentUserId: currentUserId,
            currentUserLabel: L10n.Common.you
        )
    }

    private var dateText: String {
        guard let date = expense.effectiveDate else { return L10n.Expense.unknownDate }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month().year())
    }

    private func display(for userId: Int) -> MemberDisplay {
        if let member = members.first(where: { $0.userId == userId }) {
            let display = MemberDisplay(member)
            return userId == currentUserId
                ? MemberDisplay(name: L10n.Common.you, avatarURL: display.avatarURL, userID: userId)
                : display
        }

        if let user = expense.splits.first(where: { $0.userId == userId })?.user {
            return MemberDisplay(user)
        }

        return MemberDisplay(name: L10n.Common.unknown, avatarURL: nil)
    }

    private func delete() {
        isDeleting = true
        errorMessage = nil

        Task {
            defer { isDeleting = false }
            do {
                try await ExpenseService.shared.deleteExpense(
                    groupId: expense.groupId,
                    expenseId: expense.id
                )
            } catch {
                guard error.isAlreadyGone else {
                    errorMessage = error.displayMessage
                    return
                }
            }

            onDeleted()
            dismiss()
        }
    }
}
