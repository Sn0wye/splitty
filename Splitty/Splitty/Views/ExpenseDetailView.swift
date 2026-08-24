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
                VStack(alignment: .leading, spacing: 6) {
                    Text(expense.description)
                        .font(.title2.weight(.semibold))
                    Text(Money.formatted(amount: expense.amount))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    Text("\(payerName) paid · \(dateText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section(splitHeader) {
                ForEach(expense.splits) { split in
                    HStack {
                        Text(name(for: split.userId))
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
        .navigationTitle("Expense")
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
                    .accessibilityLabel("Delete expense")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showingEditSheet = true }
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
            "Delete \"\(expense.description)\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the expense and everyone's share of it.")
        }
    }

    /// The stored mode, said once above the rows rather than repeated on each of them.
    private var splitHeader: String {
        switch expense.splitMode {
        case .equal: return "Split equally"
        case .custom: return "Split by amounts"
        case .percentage: return "Split by percentages"
        case .none: return "Split"
        }
    }

    private var payerName: String {
        expense.paidBy == currentUserId ? "You" : expense.paidByUser.name
    }

    private var dateText: String {
        guard let date = expense.effectiveDate else { return "Unknown date" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month().year())
    }

    private func name(for userId: Int) -> String {
        userId == currentUserId
            ? "You"
            : members.first { $0.userId == userId }?.name
                ?? expense.splits.first { $0.userId == userId }?.user.name
                ?? "Unknown"
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
                onDeleted()
                dismiss()
            } catch {
                errorMessage = error.displayMessage
            }
        }
    }
}
