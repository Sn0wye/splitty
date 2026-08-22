//
//  SplitConfigurationView.swift
//  Splitty
//

import SwiftUI

/// The screen behind the sheet's summary line: who paid, and how the total is divided.
struct SplitConfigurationView: View {
    @ObservedObject var viewModel: ExpenseFormViewModel
    @Environment(\.dismiss) private var dismiss

    /// Custom amounts are edited as text so a half-typed "1." survives the keystroke that
    /// would otherwise round it away.
    @State private var drafts: [Int: String] = [:]
    @State private var isCustom = false

    var body: some View {
        List {
            presetSection
            payerSection
            participantSection
        }
        .navigationTitle("Split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Save is what an unfinished split blocks; leaving this screen is not.
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            isCustom = viewModel.isCustomSplit
            seedDrafts()
        }
        .onChange(of: viewModel.isCustomSplit) { _, nowCustom in
            isCustom = nowCustom
            if nowCustom { seedDrafts() }
        }
    }

    // MARK: - Presets

    private var presetSection: some View {
        Section("Preset") {
            ForEach(SplitPreset.available(memberIds: viewModel.memberIds, currentUserId: viewModel.currentUserId)) { preset in
                Button {
                    viewModel.apply(preset: preset, payerId: nil)
                } label: {
                    HStack {
                        Text(preset.title(members: viewModel.members, currentUserId: viewModel.currentUserId))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        if viewModel.selectedPreset == preset {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityIdentifier("split.preset")
            }
        }
    }

    // MARK: - Payer

    /// The payer need not be one of the participants: "I paid, you all owe me" is a real
    /// expense, and the API only asks that the payer be a group member.
    private var payerSection: some View {
        Section("Paid by") {
            Picker("Paid by", selection: Binding(
                get: { viewModel.configuration.payerId },
                set: { viewModel.setPayer($0) }
            )) {
                ForEach(viewModel.members) { member in
                    Text(name(for: member.userId)).tag(member.userId)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("split.payer")
        }
    }

    // MARK: - Participants

    private var participantSection: some View {
        Section {
            ForEach(viewModel.members) { member in
                if isCustom {
                    customRow(for: member)
                } else {
                    equalRow(for: member)
                }
            }
        } header: {
            Text(isCustom ? "Amounts" : "Split between")
        } footer: {
            if let message = viewModel.blockingMessage {
                Text(message).foregroundStyle(.orange)
            } else if isCustom {
                Text("Everything is assigned.")
            }
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
                Text(name(for: member.userId))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text(Money.formatted(cents: viewModel.perParticipantAmounts[member.userId] ?? 0))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityIdentifier("split.member.\(member.userId)")
    }

    private func customRow(for member: GroupMember) -> some View {
        HStack {
            Text(name(for: member.userId))
            Spacer()
            Text("$").foregroundStyle(.secondary)
            TextField("0", text: Binding(
                get: { drafts[member.userId] ?? "" },
                set: { newValue in
                    drafts[member.userId] = newValue
                    viewModel.setCustomAmount(max(0, Money.cents(fromTypedText: newValue) ?? 0), for: member.userId)
                }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 90)
            .accessibilityIdentifier("split.amount.\(member.userId)")
        }
    }

    // MARK: - Helpers

    private func name(for userId: Int) -> String {
        userId == viewModel.currentUserId
            ? "You"
            : viewModel.members.first { $0.userId == userId }?.name ?? "Unknown"
    }

    private func seedDrafts() {
        drafts = viewModel.perParticipantAmounts.reduce(into: [:]) { drafts, entry in
            drafts[entry.key] = entry.value > 0 ? Money.plainString(cents: entry.value) : ""
        }
    }
}
