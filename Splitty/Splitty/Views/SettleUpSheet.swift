//
//  SettleUpSheet.swift
//  Splitty
//

import SwiftUI

struct SettleUpSheet: View {
    @StateObject private var viewModel: SettleUpViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAmount: Bool
    @State private var showingDatePicker = false
    @State private var savedCount = 0

    private let startsWithFixedPeer: Bool
    private let shouldLoadDebts: Bool
    private let onSaved: (SettleUpResult) -> Void

    init(
        groupId: Int,
        members: [GroupMember],
        currentUserId: Int,
        preselectedRow: BalanceRow? = nil,
        settlement: Expense? = nil,
        onSaved: @escaping (SettleUpResult) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: SettleUpViewModel(
            groupId: groupId,
            members: members,
            currentUserId: currentUserId,
            preselectedRow: preselectedRow,
            settlement: settlement
        ))
        let hasFixedPeer = preselectedRow != nil || settlement != nil
        _showingAmount = State(initialValue: hasFixedPeer)
        startsWithFixedPeer = hasFixedPeer
        shouldLoadDebts = preselectedRow == nil && settlement == nil
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            personStep
                .navigationDestination(isPresented: $showingAmount) {
                    amountStep
                }
        }
        .presentationCornerRadius(28)
        .presentationBackground(Color.expenseBackground)
        .sensoryFeedback(.success, trigger: savedCount)
        .task {
            if shouldLoadDebts {
                await viewModel.loadDebts()
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            ExpenseDatePicker(date: $viewModel.date)
        }
    }

    private var personStep: some View {
        List(viewModel.peers) { peer in
            Button {
                viewModel.select(peerId: peer.userId)
                showingAmount = true
            } label: {
                HStack(spacing: 12) {
                    peerAvatar(peer)

                    Text(peer.name)
                        .font(.body.weight(.semibold))

                    Spacer()

                    if let debt = viewModel.debtCents(for: peer.userId), debt > 0 {
                        Text(Money.formatted(cents: debt))
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.red)
                    }
                }
                .foregroundStyle(Color.expenseForeground)
                .opacity((viewModel.debtCents(for: peer.userId) ?? 0) > 0 ? 1 : 0.45)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color("card"))
        }
        .scrollContentBackground(.hidden)
        .background(Color.expenseBackground)
        .navigationTitle(Text(L10n.Settlement.settleUp))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.expenseBackground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Text(L10n.Common.cancel) }
                    .foregroundStyle(Color.expenseForeground)
            }
        }
    }

    private var amountStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text(viewModel.isEditing ? L10n.Settlement.paymentWith(viewModel.selectedPeer?.name ?? L10n.Common.member) : L10n.Settlement.pay(viewModel.selectedPeer?.name ?? L10n.Common.member))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color("muted-foreground"))
                .padding(.bottom, 8)

            AmountDisplay(text: viewModel.amount.displayText)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("settleUp.amount")

            Spacer(minLength: 0)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            if let payAllTitle = viewModel.payAllTitle, !viewModel.isEditing {
                Button(payAllTitle) { viewModel.payAll() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.expenseAccent)
                    .padding(.bottom, 12)
            }

            Button {
                showingDatePicker = true
            } label: {
                Label(dateLabel, systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.expenseForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.expenseForeground.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.pressable(scale: 0.98))
            .accessibilityIdentifier("settleUp.date")
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            PrimaryButton(
                title: viewModel.isEditing ? L10n.Common.save : L10n.Settlement.record,
                isLoading: viewModel.isSubmitting,
                action: submit
            )
            .disabled(!viewModel.canSubmit)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            ExpenseKeypad(
                onKey: handle(key:),
                onClear: clearAmount
            )
            .disabled(viewModel.isSubmitting)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.expenseBackground)
        .navigationTitle(Text(viewModel.isEditing ? L10n.Settlement.edit : L10n.Settlement.settleUp))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(startsWithFixedPeer)
        .toolbarBackground(Color.expenseBackground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if startsWithFixedPeer {
                    Button { dismiss() } label: { Text(L10n.Common.cancel) }
                        .foregroundStyle(Color.expenseForeground)
                }
            }
        }
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(viewModel.date) { return L10n.Common.today }
        if calendar.isDateInYesterday(viewModel.date) { return L10n.Common.yesterday }
        return viewModel.date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func handle(key: KeypadKey) {
        viewModel.errorMessage = nil
        switch key {
        case .digit(let digit): viewModel.amount.type(digit: digit)
        case .decimalPoint: viewModel.amount.typeDecimalPoint()
        case .backspace: viewModel.amount.backspace()
        }
    }

    private func clearAmount() {
        viewModel.errorMessage = nil
        viewModel.amount.clear()
    }

    private func submit() {
        guard viewModel.canSubmit else { return }
        Task {
            if let result = await viewModel.submit() {
                savedCount += 1
                onSaved(result)
                dismiss()
            }
        }
    }

    private func peerAvatar(_ peer: GroupMember) -> some View {
        CachedAsyncImage(url: URL(string: peer.avatarUrl)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(Color("muted-foreground"))
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }
}
