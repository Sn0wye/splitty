//
//  SplitConfigurationView.swift
//  Splitty
//

import SwiftUI

/// The screen behind the sheet's summary line: who paid, and how the total is divided.
///
/// There are no presets. With the mode on screen as a selector, a preset row that only
/// moves that selector is a second control for one action — picking the payer inside an
/// equal split is the same two taps a preset saved.
struct SplitConfigurationView: View {
    @ObservedObject var viewModel: ExpenseFormViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            payerSection
            modeSection
            participantSection
        }
        .navigationTitle("Split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Save is what an unfinished split blocks; leaving this screen is not. The
                // mode in effect is whichever is selected on the way out.
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Payer

    /// The payer need not be one of the participants: "I paid, you all owe me" is a real
    /// expense, and the API only asks that the payer be a group member.
    private var payerSection: some View {
        Section {
            NavigationLink {
                PayerPickerView(viewModel: viewModel)
            } label: {
                HStack {
                    Text("Paid by")
                    Spacer()
                    Text(viewModel.name(for: viewModel.configuration.payerId))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("split.payer")
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        Section {
            Picker("Split", selection: Binding(
                get: { viewModel.selectedMode },
                set: { viewModel.selectMode($0) }
            )) {
                Text("Equally").tag(ExpenseSplitMode.equal)
                Text("Amounts").tag(ExpenseSplitMode.custom)
                Text("Percentages").tag(ExpenseSplitMode.percentage)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("split.mode")
        }
    }

    // MARK: - Participants

    private var participantSection: some View {
        Section {
            ForEach(viewModel.members) { member in
                switch viewModel.selectedMode {
                case .equal: equalRow(for: member)
                case .custom: customRow(for: member)
                case .percentage: percentageRow(for: member)
                }
            }
        } header: {
            Text(header)
        } footer: {
            if let message = viewModel.blockingMessage {
                Text(message).foregroundStyle(.orange)
            } else if viewModel.selectedMode != .equal {
                Text("Everything is assigned. A blank field is someone left out.")
            }
        }
    }

    private var header: String {
        switch viewModel.selectedMode {
        case .equal: return "Split between"
        case .custom: return "Amounts"
        case .percentage: return "Percentages"
        }
    }

    private func equalRow(for member: GroupMember) -> some View {
        let isParticipant = viewModel.isParticipant(member.userId)

        return Button {
            viewModel.toggleParticipant(member.userId)
        } label: {
            HStack {
                Image(systemName: isParticipant ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isParticipant ? Color.accentColor : Color.secondary)
                Text(viewModel.name(for: member.userId))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text(Money.formatted(cents: viewModel.perParticipantAmounts[member.userId] ?? 0))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityIdentifier("split.member.\(member.userId)")
    }

    /// Amounts and percentages are edited as text so a half-typed `1.` survives the
    /// keystroke that would otherwise round it away. The text lives on the view model:
    /// this screen is popped and pushed constantly while composing.
    private func customRow(for member: GroupMember) -> some View {
        HStack {
            Text(viewModel.name(for: member.userId))
            Spacer()
            Text("$").foregroundStyle(.secondary)
            TextField("0", text: Binding(
                get: { viewModel.customText[member.userId] ?? "" },
                set: { viewModel.setCustomText($0, for: member.userId) }
            ))
            // The system pad, not the calculator one: that exists because a *total* is
            // often summed off a receipt, and `AmountExpression` has one job.
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 90)
            .accessibilityIdentifier("split.amount.\(member.userId)")
        }
    }

    private func percentageRow(for member: GroupMember) -> some View {
        HStack {
            Text(viewModel.name(for: member.userId))
            Spacer()
            // The share and what it comes to: a percentage is only meaningful next to the
            // money it stands for.
            Text(Money.formatted(cents: viewModel.perParticipantAmounts[member.userId] ?? 0))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            TextField("0", text: Binding(
                get: { viewModel.percentageText[member.userId] ?? "" },
                set: { viewModel.setPercentageText($0, for: member.userId) }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 60)
            .accessibilityIdentifier("split.percentage.\(member.userId)")
            Text("%").foregroundStyle(.secondary)
        }
    }
}

/// Who paid. A pushed list rather than a menu: the group can be large, and the payer is
/// picked far more often than any other field on the split screen.
private struct PayerPickerView: View {
    @ObservedObject var viewModel: ExpenseFormViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(viewModel.members) { member in
            Button {
                viewModel.setPayer(member.userId)
                dismiss()
            } label: {
                HStack {
                    Text(viewModel.name(for: member.userId))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if viewModel.configuration.payerId == member.userId {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .accessibilityIdentifier("split.payer.\(member.userId)")
        }
        .navigationTitle("Paid by")
        .navigationBarTitleDisplayMode(.inline)
    }
}
