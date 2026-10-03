//
//  SettlementDetailView.swift
//  Splitty
//

import SwiftUI

/// Shows one payment and opens the shared amount screen when it is edited.
struct SettlementDetailView: View {
    let settlement: Expense
    let currentUserId: Int
    @ObservedObject var session: GroupSession

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
        .scrollContentBackground(.hidden)
        .background(Color("background"))
        .navigationTitle(Text(L10n.Settlement.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Same order as an expense's detail: delete, then Edit at the trailing edge.
            ToolbarItemGroup(placement: .navigationBarTrailing) {
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

                Button { showingEditSheet = true } label: { Image(systemName: "pencil") }
                    .accessibilityLabel(L10n.Settlement.edit)
                    .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            SettleUpSheet(
                session: session,
                currentUserId: currentUserId,
                settlement: settlement
            )
        }
        .alert(
            L10n.Settlement.deleteTitle(Money.formatted(amount: settlement.amount), payerName, payeeName),
            isPresented: $showingDeleteConfirmation
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
        if let member = session.members.first(where: { $0.userId == peer.id }) {
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
        return date.formatted(.dateTime.weekday(.abbreviated).day().month().year().inAppLanguage())
    }

    private func delete() {
        isDeleting = true
        errorMessage = nil

        Task {
            defer { isDeleting = false }
            if let failureMessage = await session.delete(settlement).value.failureMessage {
                errorMessage = failureMessage
                return
            }
            dismiss()
        }
    }
}
