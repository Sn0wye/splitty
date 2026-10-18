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
    @Environment(\.currency) private var currency
    @ObservedObject var viewModel: ExpenseFormViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case amount(Int)
        case percentage(Int)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Typing leaves the keyboard little room, and the bar above it already
                // says what the total is, so the total and payer step aside until it is
                // dismissed.
                if focusedField == nil {
                    totalHeader
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    payerStrip
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                modePicker
                participantSection
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(.snappy(duration: 0.3), value: focusedField == nil)
            // The decimal pad has no return key: a tap anywhere outside the fields puts it
            // away, as does dragging the list down.
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { focusedField = nil }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.expenseBackground)
        // The running total of a typed split stays in view above the keyboard: it is the
        // number every keystroke is aiming at.
        .safeAreaInset(edge: .bottom) {
            if viewModel.selectedMode != .equal {
                assignmentBar
            }
        }
        .toolbarBackground(Color.expenseBackground, for: .navigationBar)
        .navigationTitle(Text(L10n.Split.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                // Save is what an unfinished split blocks; leaving this screen is not. The
                // mode in effect is whichever is selected on the way out.
                Button { dismiss() } label: { Text(L10n.Common.done) }
            }
        }
    }

    // MARK: - Total

    /// The shares below are only meaningful next to the money they divide.
    private var totalHeader: some View {
        VStack(spacing: 4) {
            Text(Money.formatted(cents: viewModel.totalCents, currency: currency))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.expenseForeground)
            Text(totalCaption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .animation(.snappy(duration: 0.25), value: totalCaption)
    }

    /// How many share it, and on an equal split what each pays when the cents divide evenly.
    private var totalCaption: String {
        let shares = viewModel.participantChoices.compactMap { viewModel.perParticipantAmounts[$0.userId] }
            .filter { $0 > 0 }
        let people = L10n.Split.people(shares.count)
        guard viewModel.selectedMode == .equal, let share = shares.first,
              shares.allSatisfy({ $0 == share }) else { return people }
        return "\(L10n.Split.each(Money.formatted(cents: share, currency: currency))) · \(people)"
    }

    // MARK: - Payer

    /// The payer need not be one of the participants: "I paid, you all owe me" is a real
    /// expense, and the API only asks that the payer be a group member. A row of faces
    /// rather than a pushed list: the payer is picked far more often than any other field
    /// here, and a large group scrolls sideways.
    private var payerStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(L10n.Split.paidBy)
                .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(youFirst(viewModel.payerChoices)) { member in
                        payerButton(for: member)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("split.payer")
        }
    }

    private func payerButton(for member: GroupMember) -> some View {
        let isPayer = viewModel.configuration.payerId == member.userId
        let name = viewModel.name(for: member.userId)

        return Button {
            withAnimation(.snappy(duration: 0.25)) { viewModel.setPayer(member.userId) }
        } label: {
            VStack(spacing: 6) {
                MemberAvatar(display: MemberDisplay(member), size: 48)
                    .padding(3)
                    .overlay {
                        Circle().strokeBorder(isPayer ? Color.accentColor : .clear, lineWidth: 2)
                    }
                Text(name.split(separator: " ").first.map(String.init) ?? name)
                    .font(.caption.weight(isPayer ? .semibold : .regular))
                    .foregroundStyle(isPayer ? Color.expenseForeground : Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.94))
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isPayer ? .isSelected : [])
        .accessibilityIdentifier("split.payer.\(member.userId)")
    }

    // MARK: - Mode

    private var modePicker: some View {
        Picker(selection: Binding(
            get: { viewModel.selectedMode },
            set: { mode in withAnimation(.snappy(duration: 0.25)) { viewModel.selectMode(mode) } }
        )) {
            Text(L10n.Split.equally).tag(ExpenseSplitMode.equal)
            Text(L10n.Split.amounts).tag(ExpenseSplitMode.custom)
            Text(L10n.Split.percentages).tag(ExpenseSplitMode.percentage)
        } label: {
            Text(L10n.Split.title)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .accessibilityIdentifier("split.mode")
    }

    // MARK: - Participants

    private var participantSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel(header)
                Spacer()
                if viewModel.selectedMode == .equal {
                    let includesEveryone = viewModel.includesEveryParticipant
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            viewModel.setEveryParticipant(included: !includesEveryone)
                        }
                    } label: {
                        Text(includesEveryone ? L10n.Split.selectNone : L10n.Split.selectAll)
                            .font(.footnote.weight(.semibold))
                    }
                    .accessibilityIdentifier("split.select-all")
                }
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(youFirst(viewModel.participantChoices).enumerated()), id: \.element.id) { index, member in
                    if index > 0 {
                        Divider().padding(.leading, 62)
                    }
                    switch viewModel.selectedMode {
                    case .equal: equalRow(for: member)
                    case .custom: customRow(for: member)
                    case .percentage: percentageRow(for: member)
                    }
                }
            }
            .background(Color.expenseForeground.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)

            // A typed split reports in the bar along the bottom.
            if viewModel.selectedMode == .equal, let message = viewModel.blockingMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var header: String {
        switch viewModel.selectedMode {
        case .equal: return L10n.Split.between
        case .custom: return L10n.Split.amounts
        case .percentage: return L10n.Split.percentages
        }
    }

    /// The avatar and name every mode shares. Someone with no share is greyed out, which
    /// is what a blank field means on the typed modes.
    private func memberRow<Trailing: View>(
        _ member: GroupMember,
        caption: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let included = viewModel.isParticipant(member.userId)

        return HStack(spacing: 12) {
            MemberAvatar(display: MemberDisplay(member), size: 36)
                .grayscale(included ? 0 : 1)
                .opacity(included ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.name(for: member.userId))
                    .foregroundStyle(included ? Color.expenseForeground : Color.secondary)
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(.snappy(duration: 0.2), value: included)
    }

    private func equalRow(for member: GroupMember) -> some View {
        let isParticipant = viewModel.isParticipant(member.userId)

        return Button {
            withAnimation(.snappy(duration: 0.2)) { viewModel.toggleParticipant(member.userId) }
        } label: {
            memberRow(member) {
                if isParticipant {
                    Text(Money.formatted(cents: viewModel.perParticipantAmounts[member.userId] ?? 0, currency: currency))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.expenseForeground)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Image(systemName: isParticipant ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isParticipant ? Color.accentColor : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isParticipant ? .isSelected : [])
        .accessibilityIdentifier("split.member.\(member.userId)")
    }

    /// Amounts and percentages are edited as text so a half-typed `1.` survives the
    /// keystroke that would otherwise round it away. The text lives on the view model:
    /// this screen is popped and pushed constantly while composing.
    private func customRow(for member: GroupMember) -> some View {
        memberRow(member) {
            entryField(.amount(member.userId), prefix: "$", width: 72) {
                TextField("0.00", text: Binding(
                    get: { viewModel.customText[member.userId] ?? "" },
                    set: { viewModel.setCustomText($0, for: member.userId) }
                ))
                .accessibilityIdentifier("split.amount.\(member.userId)")
            }
        }
    }

    private func percentageRow(for member: GroupMember) -> some View {
        // The share and what it comes to: a percentage is only meaningful next to the
        // money it stands for.
        let cents = viewModel.perParticipantAmounts[member.userId] ?? 0

        return memberRow(member, caption: cents > 0 ? Money.formatted(cents: cents, currency: currency) : nil) {
            entryField(.percentage(member.userId), suffix: "%", width: 44) {
                TextField("0", text: Binding(
                    get: { viewModel.percentageText[member.userId] ?? "" },
                    set: { viewModel.setPercentageText($0, for: member.userId) }
                ))
                .accessibilityIdentifier("split.percentage.\(member.userId)")
            }
        }
    }

    /// A filled pill around a number field, outlined while it has focus. The whole pill
    /// takes the tap, not only the digits.
    private func entryField<Content: View>(
        _ field: Field,
        prefix: String? = nil,
        suffix: String? = nil,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 2) {
            if let prefix { Text(prefix).foregroundStyle(.secondary) }
            content()
                // The system pad, not the calculator one: that exists because a *total* is
                // often summed off a receipt, and `AmountExpression` has one job.
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focusedField, equals: field)
                .frame(width: width)
            if let suffix { Text(suffix).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.expenseForeground.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .opacity(focusedField == field ? 1 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { focusedField = field }
        .animation(.easeOut(duration: 0.15), value: focusedField == field)
    }

    // MARK: - Assignment

    /// How much of the total a typed split has handed out, as a bar and in words. It
    /// stands in for a footer that scrolled away under the keyboard.
    private var assignmentBar: some View {
        let progress = assignment
        let message = viewModel.blockingMessage
        let complete = message == nil && viewModel.totalCents > 0
        let tint: Color = complete ? Color("positive") : progress.fraction > 1 ? .orange : .accentColor

        return VStack(spacing: 8) {
            Capsule()
                .fill(Color.expenseForeground.opacity(0.08))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * min(max(progress.fraction, 0), 1))
                    }
                }
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                Text(progress.label)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(message ?? (complete ? L10n.Split.allAssigned : ""))
                    .fontWeight(.semibold)
                    .foregroundStyle(complete ? Color("positive") : .orange)
                    .multilineTextAlignment(.trailing)
            }
            .font(.footnote)
            .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.expenseBackground)
        .animation(.snappy(duration: 0.25), value: progress.fraction)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("split.assigned")
    }

    private var assignment: (fraction: Double, label: String) {
        let configuration = viewModel.configuration
        switch viewModel.selectedMode {
        case .equal:
            return (1, "")
        case .custom:
            let total = viewModel.totalCents
            let assigned = total - configuration.unassignedCents(totalCents: total)
            return (
                total > 0 ? Double(assigned) / Double(total) : 0,
                L10n.Split.assignedOf(Money.formatted(cents: assigned, currency: currency), Money.formatted(cents: total, currency: currency))
            )
        case .percentage:
            let assigned = 100 - configuration.unassignedPercent
            return (
                NSDecimalNumber(decimal: assigned).doubleValue / 100,
                "\(Percent.string(assigned))%"
            )
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.4)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    /// You first, everyone else in the group's order: you are in nearly every expense.
    private func youFirst(_ members: [GroupMember]) -> [GroupMember] {
        members.filter { $0.userId == viewModel.currentUserId }
            + members.filter { $0.userId != viewModel.currentUserId }
    }
}
