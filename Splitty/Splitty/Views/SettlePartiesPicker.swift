//
//  SettlePartiesPicker.swift
//  Splitty
//

import SwiftUI

/// The settle-up sheet's first two steps: a grid of the group's faces asking who paid, each
/// with what they owe, then the same grid asking to whom, each with what the payer owes
/// them. Any member may record a payment between any two members (ADR 0010).
struct SettlePartiesPicker: View {
    @Environment(\.currency) private var currency
    @ObservedObject var viewModel: SettleUpViewModel
    let onFinish: () -> Void
    @State private var askingPayee = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(askingPayee ? L10n.Settlement.paidToWhom : L10n.Settlement.whoPaid)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.expenseForeground)
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 20) {
                    ForEach(viewModel.choices) { member in
                        let isPayer = member.userId == viewModel.payerId
                        SettlePartyFace(
                            member: member,
                            name: viewModel.name(of: member),
                            isSelected: askingPayee ? member.userId == viewModel.payeeId : isPayer,
                            isDimmed: askingPayee && isPayer,
                            caption: caption(for: member),
                            captionColor: askingPayee ? Color("positive") : Color("negative")
                        ) {
                            withAnimation(.snappy(duration: 0.3)) {
                                if askingPayee {
                                    viewModel.setPayee(member.userId)
                                    onFinish()
                                } else {
                                    viewModel.setPayer(member.userId)
                                    askingPayee = true
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 12)
        }
        .background(Color.expenseBackground)
        .toolbar {
            if askingPayee {
                ToolbarItem(placement: .topBarLeading) {
                    Button { withAnimation { askingPayee = false } } label: {
                        Image(systemName: "chevron.backward").fontWeight(.semibold)
                    }
                    .accessibilityLabel(Text(L10n.Common.back))
                }
            }
        }
    }

    /// What each member owes the group while asking who paid, then what the payer owes each
    /// member while asking to whom.
    private func caption(for member: GroupMember) -> String? {
        if askingPayee {
            guard let payer = viewModel.payerId, member.userId != payer,
                  let cents = viewModel.pairCents(from: payer, to: member.userId) else { return nil }
            return Money.formatted(cents: cents, currency: currency)
        }
        let net = viewModel.netCents(of: member.userId)
        guard net < 0 else { return nil }
        return Money.formatted(cents: -net, currency: currency)
    }
}

/// The two sides picked, above the amount. Tapping it goes back to who paid; an edit keeps
/// both sides, so there it only reads.
struct SettlePartiesSummary: View {
    @ObservedObject var viewModel: SettleUpViewModel
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 10) {
                if let payer = viewModel.payer { MemberAvatar(display: MemberDisplay(payer), size: 32) }
                Text(L10n.Group.payerPaidPayee(
                    viewModel.payer.map { viewModel.name(of: $0) } ?? "—",
                    viewModel.payee.map { viewModel.name(of: $0) } ?? "—"
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.expenseForeground)
                .lineLimit(2)
                if let payee = viewModel.payee { MemberAvatar(display: MemberDisplay(payee), size: 32) }
                if !viewModel.isEditing {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.expenseForeground.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.pressable(scale: 0.97))
        .disabled(viewModel.isEditing)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .accessibilityIdentifier("settleUp.parties")
    }
}

/// The expense form's payer face: an avatar ringed in the accent when picked, the first name
/// under it, and an optional amount under that.
private struct SettlePartyFace: View {
    let member: GroupMember
    let name: String
    let isSelected: Bool
    var isDimmed = false
    var caption: String? = nil
    var captionColor: Color = .secondary
    var size: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                MemberAvatar(display: MemberDisplay(member), size: size)
                    .padding(3)
                    .overlay {
                        Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    }
                Text(name.split(separator: " ").first.map(String.init) ?? name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.expenseForeground : Color.secondary)
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(captionColor)
                        .lineLimit(1)
                }
            }
            .frame(width: size + 28)
            .contentShape(Rectangle())
            .opacity(isDimmed ? 0.35 : 1)
        }
        .buttonStyle(.pressable(scale: 0.94))
        .disabled(isDimmed)
        .accessibilityLabel(Text(caption.map { "\(name), \($0)" } ?? name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
