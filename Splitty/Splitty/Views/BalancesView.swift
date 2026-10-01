//
//  BalancesView.swift
//  Splitty
//

import SwiftUI

struct BalancesView: View {
    let session: GroupSession
    @ObservedObject private var snapshot: GroupViewModel
    let currentUserId: Int
    let members: [GroupMember]
    let onSettled: (SettleUpResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BalancesViewModel
    @State private var selectedDebt: BalanceRow?

    init(
        session: GroupSession,
        currentUserId: Int,
        members: [GroupMember],
        onSettled: @escaping (SettleUpResult) -> Void
    ) {
        self.session = session
        _snapshot = ObservedObject(wrappedValue: session.snapshot)
        self.currentUserId = currentUserId
        self.members = members
        self.onSettled = onSettled
        let model = BalancesViewModel(groupId: session.groupId)
        if let summary = session.snapshot.latestSummary {
            model.apply(summary, currentUserId: currentUserId)
        }
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    netHeader
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color("background"))
            .navigationTitle(Text(L10n.Balances.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color("background"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text(L10n.Common.done) }
                }
            }
            .refreshable {
                await viewModel.refresh(session: session)
            }
            .onReceive(snapshot.$latestSummary) { summary in
                if let summary { viewModel.apply(summary, currentUserId: currentUserId) }
            }
            .task {
                guard snapshot.latestSummary == nil else { return }
                do {
                    let summary = try await snapshot.summary(groupId: session.groupId)
                    viewModel.apply(summary, currentUserId: currentUserId)
                } catch {
                    viewModel.fail(with: error)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $selectedDebt) { row in
            SettleUpSheet(
                session: session,
                groupId: session.groupId,
                members: members,
                currentUserId: currentUserId,
                preselectedRow: row
            ) { result in
                onSettled(result)
                dismiss()
            }
        }
    }

    private var netHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(netLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color("muted-foreground"))

            HStack(spacing: 10) {
                Text(Money.formatted(cents: abs(snapshot.group?.netBalanceCents ?? 0)))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color("foreground"))
                    .opacity(snapshot.balancesPending ? 0.5 : 1)

                if snapshot.balancesPending {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var netLabel: String {
        if (snapshot.group?.netBalanceCents ?? 0) > 0 { return L10n.Balances.owedOverall }
        if (snapshot.group?.netBalanceCents ?? 0) < 0 { return L10n.Balances.oweOverall }
        return L10n.Balances.yourBalance
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(L10n.Balances.loading)
                    .foregroundStyle(Color("muted-foreground"))
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)

        case .settled:
            // The brand's settle-up motion: the halves slide back into one coin.
            HStack(spacing: 12) {
                SettledCoin()
                Text(L10n.Balances.everyoneSettled)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color("foreground"))
            }
            .frame(minHeight: 56)

        case .error(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)

                Button {
                    Task { await viewModel.refresh(session: session) }
                } label: {
                    Text(L10n.Common.tryAgain)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 8)

        case .balances(let rows):
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    if row.involvement == .youPay {
                        Button { selectedDebt = row } label: {
                            balanceRow(row)
                        }
                        .buttonStyle(.plain)
                        .disabled(snapshot.balancesPending)
                        .accessibilityHint(L10n.Balances.recordsPayment)
                    } else {
                        balanceRow(row)
                    }

                    if row.id != rows.last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
        }
    }

    private func balanceRow(_ row: BalanceRow) -> some View {
        SimplifiedDebtRow(row: row, numbersArePending: snapshot.balancesPending)
    }
}

private struct SimplifiedDebtRow: View {
    let row: BalanceRow
    let numbersArePending: Bool

    private var directionColor: Color {
        switch row.involvement {
        case .youPay: Color("negative")
        case .paysYou: Color("positive")
        case .uninvolved: Color("card-foreground")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            debtMemberAvatars

            VStack(alignment: .leading, spacing: 2) {
                Text(row.statement)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color("card-foreground"))
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Money.formatted(cents: row.amountCents))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(directionColor)
                    .opacity(numbersArePending ? 0.5 : 1)

                if row.involvement == .youPay {
                    HStack(spacing: 3) {
                        Text(L10n.Balances.settle)
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    // Foreground, not the accent: Coral Deep on the row's red tint is 4:1.
                    .foregroundStyle(Color("card-foreground"))
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, row.involvement == .uninvolved ? 0 : 10)
        .background(
            row.involvement == .uninvolved ? Color.clear : directionColor.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.statement)
        .accessibilityValue(numbersArePending ? L10n.Common.updating : "")
    }

    private var debtMemberAvatars: some View {
        HStack(spacing: -10) {
            avatar(url: row.from.avatarURL)
            avatar(url: row.to.avatarURL)
        }
        .frame(width: 54)
    }

    private func avatar(url: URL?) -> some View {
        CachedAsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(Color("muted-foreground"))
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color("background"), lineWidth: 2))
    }
}

enum BalanceCopy {
    static func overall(cents: Int) -> String {
        if cents > 0 {
            L10n.Balances.owedOverallAmount(Money.formatted(cents: cents))
        } else if cents < 0 {
            L10n.Balances.oweOverallAmount(Money.formatted(cents: abs(cents)))
        } else {
            L10n.Balances.allSettled
        }
    }
}

#Preview {
    BalancesView(
        session: GroupSessionStore().open(1),
        currentUserId: 4,
        members: [],
        onSettled: { _ in }
    )
}
