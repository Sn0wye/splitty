//
//  SettleUpSheet.swift
//  Splitty
//

import SwiftUI

struct SettleUpSheet: View {
    @Environment(\.currency) private var currency
    @ObservedObject private var session: GroupSession
    @StateObject private var viewModel: SettleUpViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAmount: Bool
    @State private var showingDatePicker = false
    @State private var savedCount = 0
    @State private var settledUp = false

    private let startsWithFixedPeer: Bool
    private let shouldLoadDebts: Bool

    init(
        session: GroupSession,
        currentUserId: Int,
        preselectedRow: BalanceRow? = nil,
        settlement: Expense? = nil,
        dataSource: SettleUpDataSource = .live
    ) {
        _session = ObservedObject(wrappedValue: session)
        let model = SettleUpViewModel(
            session: session,
            currentUserId: currentUserId,
            preselectedRow: preselectedRow,
            settlement: settlement,
            dataSource: dataSource
        )
        model.suggestPayment()
        _viewModel = StateObject(wrappedValue: model)
        let isEditing = settlement != nil
        _showingAmount = State(initialValue: preselectedRow != nil || isEditing)
        startsWithFixedPeer = isEditing
        shouldLoadDebts = !isEditing
    }

    var body: some View {
        NavigationStack {
            personStep
                .navigationDestination(isPresented: $showingAmount) {
                    amountStep
                }
        }
        .overlay {
            if settledUp {
                SettledUpMoment { dismiss() }
                    .transition(.opacity)
            }
        }
        .presentationCornerRadius(28)
        .presentationBackground(Color.expenseBackground)
        .sensoryFeedback(.success, trigger: savedCount)
        .task {
            if shouldLoadDebts {
                // Loading may suggest a peer, but only a balance-row entry skips the picker.
                await refreshDebts()
            }
        }
        .onChange(of: session.balanceState(currentUserId: viewModel.currentUserId)) { _, _ in
            viewModel.suggestPayment()
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
                        Text(Money.formatted(cents: debt, currency: currency))
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
        .refreshable {
            await refreshDebts()
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

            if viewModel.balancesPending {
                Button {
                    Task { await refreshDebts() }
                } label: {
                    Label(L10n.Common.tryAgain, systemImage: "arrow.clockwise")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.bottom, 12)
            }

            if let payAllTitle = viewModel.payAllTitle, !viewModel.isEditing {
                Button(payAllTitle) { viewModel.payAll() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
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
        return viewModel.date.formatted(.dateTime.day().month(.abbreviated).year().inAppLanguage())
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
                if result.settlesUp {
                    // The coin plays the success haptic itself, when its halves meet. The
                    // write waits for the cover: it marks balances pending, which would
                    // show Try again under the fade.
                    withAnimation(.easeOut(duration: 0.25)) {
                        settledUp = true
                    } completion: {
                        session.record(result, currentUserId: viewModel.currentUserId)
                    }
                } else {
                    savedCount += 1
                    session.record(result, currentUserId: viewModel.currentUserId)
                    dismiss()
                }
            }
        }
    }

    private func refreshDebts() async {
        await viewModel.loadDebts()
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

/// The sheet's last state after a payment that brings the payer's balance to zero: the
/// coin's halves meet and turn green. A tap, or a short hold, dismisses it.
private struct SettledUpMoment: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var finished = false

    var body: some View {
        VStack(spacing: 24) {
            SettledCoin(size: 150, fromBrand: true)
            Text(L10n.Balances.allSettled)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.expenseForeground)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.expenseBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { finish() }
        .accessibilityIdentifier("settleUp.settled")
        .task {
            // VoiceOver needs time to read the line; a double tap dismisses instead.
            guard !voiceOverEnabled else { return }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
