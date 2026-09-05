//
//  BalancesView.swift
//  Splitty
//

import SwiftUI

struct BalancesView: View {
    let currentUserId: Int

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BalancesViewModel

    init(context: BalanceSheetContext, currentUserId: Int) {
        self.currentUserId = currentUserId
        _viewModel = StateObject(wrappedValue: BalancesViewModel(context: context))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    netHeader
                        .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
                        .listRowBackground(Color("background"))
                        .listRowSeparator(.hidden)
                }

                Section("Open balances") {
                    content
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color("background"))
            .navigationTitle("Balances")
            .navigationBarTitleDisplayMode(.inline)
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
    }

    private var netHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your balance")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color("muted-foreground"))

            HStack(spacing: 10) {
                Text(BalanceCopy.overall(cents: viewModel.netCents))
                    .font(.title2.weight(.bold))
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

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading balances…")
                    .foregroundStyle(Color("muted-foreground"))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color("card"))

        case .settled:
            Label("Everyone is settled up", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color("muted-foreground"))
                .listRowBackground(Color("card"))

        case .error(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)

                Button("Try again") {
                    Task { await viewModel.load(currentUserId: currentUserId) }
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color("card"))

        case .balances(let rows):
            ForEach(rows) { row in
                BalancePeerRow(
                    row: row,
                    largestMagnitudeCents: viewModel.largestMagnitudeCents,
                    numbersArePending: viewModel.balancesPending
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color("card"))
            }
        }
    }
}

private struct BalancePeerRow: View {
    let row: BalanceRow
    let largestMagnitudeCents: Int
    let numbersArePending: Bool

    private var fraction: CGFloat {
        CGFloat(row.magnitudeCents) / CGFloat(max(largestMagnitudeCents, 1))
    }

    private var directionColor: Color {
        row.direction == .youOwe ? .red : .green
    }

    var body: some View {
        HStack(spacing: 12) {
            peerAvatar

            Text(
                row.direction == .youOwe
                    ? "You owe \(row.peerName)"
                    : "\(row.peerName) owes you"
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(Color("card-foreground"))

            Spacer(minLength: 12)

            Text(Money.formatted(cents: row.magnitudeCents))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(directionColor)
                .opacity(numbersArePending ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(alignment: .leading) {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 10)
                    .fill(directionColor.opacity(0.14))
                    .frame(width: geometry.size.width * fraction)
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.statement)
        .accessibilityValue(numbersArePending ? "Updating" : "")
    }

    private var peerAvatar: some View {
        AsyncImage(url: row.peerAvatarURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(Color("muted-foreground"))
            }
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
        currentUserId: 4
    )
}
