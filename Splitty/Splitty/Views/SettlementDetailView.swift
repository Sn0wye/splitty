//
//  SettlementDetailView.swift
//  Splitty
//

import SwiftUI

/// Shows one payment and opens the shared amount screen when it is edited.
struct SettlementDetailView: View {
    let settlement: Expense
    let members: [GroupMember]
    let currentUserId: Int
    let onChanged: () -> Void
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var showingEditSheet = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: -8) {
                        MemberAvatar(display: payerDisplay, size: 40)
                        MemberAvatar(display: payeeDisplay, size: 40)
                    }
                    Text(Money.formatted(amount: settlement.amount))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    paymentDescription
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
                Text(L10n.Settlement.anyMemberDelete)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text(L10n.Settlement.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showingEditSheet = true } label: { Text(L10n.Common.edit) }
                    .disabled(isDeleting)

                if isDeleting {
                    ProgressView()
                } else {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(L10n.Settlement.deleteA11y)
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            SettleUpSheet(
                groupId: settlement.groupId,
                members: members,
                currentUserId: currentUserId,
                settlement: settlement
            ) { _ in
                onChanged()
            }
        }
        .confirmationDialog(
            L10n.Settlement.deleteTitle(Money.formatted(amount: settlement.amount), payerName, payeeName),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) { delete() } label: { Text(L10n.Common.delete) }
            Button(role: .cancel) {} label: { Text(L10n.Common.cancel) }
        } message: {
            Text(L10n.Settlement.deleteMessage)
        }
    }

    private var payerName: String {
        settlement.paidBy == currentUserId ? L10n.Common.you : payerDisplay.name
    }

    private var payerDisplay: MemberDisplay {
        MemberDisplay(
            settlement.paidByUser,
            currentUserId: currentUserId,
            currentUserLabel: L10n.Common.you
        )
    }

    private var payeeName: String {
        payeeDisplay.name
    }

    private var payeeDisplay: MemberDisplay {
        guard let peer = settlement.peer else {
            return .removed
        }
        if peer.id == currentUserId {
            return MemberDisplay(peer, currentUserId: currentUserId, currentUserLabel: L10n.Common.youLowercase)
        }
        if let member = members.first(where: { $0.userId == peer.id }) {
            return MemberDisplay(member)
        }
        return MemberDisplay(peer, currentUserId: currentUserId, currentUserLabel: L10n.Common.youLowercase)
    }

    private var paymentDescription: Text {
        Text(payerName)
            .foregroundColor(payerDisplay.isRemoved ? Color("muted-foreground") : Color("foreground"))
        + Text(L10n.Settlement.paidConnector)
        + Text(payeeName)
            .foregroundColor(payeeDisplay.isRemoved ? Color("muted-foreground") : Color("foreground"))
    }

    private var dateText: String {
        guard let date = settlement.effectiveDate else { return L10n.Expense.unknownDate }
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
