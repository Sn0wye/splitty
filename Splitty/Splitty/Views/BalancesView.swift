//
//  BalancesView.swift
//  Splitty
//

import SwiftUI

struct BalancesView: View {
    let currentUserId: Int
    let members: [GroupMember]
    let onSettled: (SettleUpResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BalancesViewModel
    @State private var selectedDebt: BalanceRow?

    init(
        context: BalanceSheetContext,
        currentUserId: Int,
        members: [GroupMember],
        onSettled: @escaping (SettleUpResult) -> Void
    ) {
        self.currentUserId = currentUserId
        self.members = members
        self.onSettled = onSettled
        _viewModel = StateObject(wrappedValue: BalancesViewModel(context: context))
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
            .navigationTitle("Balances")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color("background"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable {
                await viewModel.refresh(currentUserId: currentUserId)
            }
            .task {
                await viewModel.load(currentUserId: currentUserId)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $selectedDebt) { row in
            SettleUpSheet(
                groupId: viewModel.groupId,
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
                Text(Money.formatted(cents: abs(viewModel.netCents)))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color("foreground"))
                    .opacity(viewModel.balancesPending ? 0.5 : 1)

                if viewModel.balancesPending {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var netLabel: String {
        if viewModel.netCents > 0 { return "You are owed overall" }
        if viewModel.netCents < 0 { return "You owe overall" }
        return "Your balance"
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading balances…")
                    .foregroundStyle(Color("muted-foreground"))
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)

        case .settled:
            Label("Everyone is settled up", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color("muted-foreground"))
                .frame(minHeight: 56)

        case .error(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)

                Button("Try again") {
                    Task { await viewModel.load(currentUserId: currentUserId) }
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 8)

        case .balances(let rows):
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    if row.direction == .youOwe {
                        Button { selectedDebt = row } label: {
                            balanceRow(row)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Records a payment")
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
        BalancePeerRow(row: row, numbersArePending: viewModel.balancesPending)
    }
}

private struct BalancePeerRow: View {
    let row: BalanceRow
    let numbersArePending: Bool

    private var directionColor: Color {
        row.direction == .youOwe ? .red : .green
    }

    var body: some View {
        HStack(spacing: 12) {
            peerAvatar

            VStack(alignment: .leading, spacing: 2) {
                Text(row.peerName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color("card-foreground"))

                Text(row.direction == .youOwe ? "You owe" : "Owes you")
                    .font(.subheadline)
                    .foregroundStyle(Color("muted-foreground"))
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Money.formatted(cents: row.magnitudeCents))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(directionColor)
                    .opacity(numbersArePending ? 0.5 : 1)

                if row.direction == .youOwe {
                    HStack(spacing: 3) {
                        Text("Settle")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.statement)
        .accessibilityValue(numbersArePending ? "Updating" : "")
    }

    private var peerAvatar: some View {
        CachedAsyncImage(url: row.peerAvatarURL) { image in
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

enum BalanceCopy {
    static func overall(cents: Int) -> String {
        if cents > 0 {
            "You are owed \(Money.formatted(cents: cents)) overall"
        } else if cents < 0 {
            "You owe \(Money.formatted(cents: abs(cents))) overall"
        } else {
            "You are all settled up"
        }
    }
}

#Preview {
    BalancesView(
        context: BalanceSheetContext(groupId: 1, initialNetCents: -23_585, balancesPending: false),
        currentUserId: 4,
        members: [],
        onSettled: { _ in }
    )
}
