//
//  SettlementDetailView.swift
//  Splitty
//

import SwiftUI

/// A read-only view of one settlement: who paid whom, and when.
///
/// Delete-only. Editing a settlement belongs to the screen that records them, which owns
/// the cap on what a member may repay; building that form twice is not worth it.
struct SettlementDetailView: View {
    let settlement: Expense
    let members: [GroupMember]
    let currentUserId: Int
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Money.formatted(amount: settlement.amount))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    Text("\(payerName) paid \(payeeName)")
                        .font(.headline)
                    Text(dateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                // Invariant 2: membership is the only authorization boundary. A settlement
                // someone else recorded is no more protected than an expense they logged.
                Text("Any member can delete a settlement, including one someone else recorded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settlement")
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
                    .accessibilityLabel("Delete settlement")
                }
            }
        }
        .confirmationDialog(
            "Delete the \(Money.formatted(amount: settlement.amount)) payment from \(payerName) to \(payeeName)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The balance between them goes back to what it was before this payment.")
        }
    }

    private var payerName: String {
        settlement.paidBy == currentUserId ? "You" : settlement.paidByUser.name
    }

    private var payeeName: String {
        guard let peer = settlement.peer else { return "someone who has left" }
        return peer.id == currentUserId
            ? "you"
            : members.first { $0.userId == peer.id }?.name ?? peer.name
    }

    private var dateText: String {
        guard let date = settlement.effectiveDate else { return "Unknown date" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month().year())
    }

    private func delete() {
        isDeleting = true
        errorMessage = nil

        Task {
            defer { isDeleting = false }
            do {
                try await SettlementService.shared.deleteSettlement(
                    groupId: settlement.groupId,
                    expenseId: settlement.id
                )
                onDeleted()
                dismiss()
            } catch {
                errorMessage = error.displayMessage
            }
        }
    }
}
