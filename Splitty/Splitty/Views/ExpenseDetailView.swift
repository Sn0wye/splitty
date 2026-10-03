//
//  ExpenseDetailView.swift
//  Splitty
//

import SwiftUI

/// A read-only view of one expense: the total, who paid, and every split. Editing reopens
/// the same sheet that created it.
struct ExpenseDetailView: View {
    let expense: Expense
    let members: [GroupMember]
    let currentUserId: Int
    let timelineExpenses: [Expense]
    var onMoneyWrite: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                positionStrip
                section(L10n.Split.paidBy) { payerRow }
                section(splitHeader) { splitRows }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color("background"))
        .navigationTitle(Text(L10n.Expense.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isDeleting {
                    ProgressView()
                } else {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(L10n.Expense.deleteA11y)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingEditSheet = true } label: { Image(systemName: "pencil") }
                    .accessibilityLabel(L10n.Expense.editExpense)
                    .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            ExpenseSheet(
                groupId: expense.groupId,
                members: members,
                currentUserId: currentUserId,
                expense: expense,
                timelineExpenses: timelineExpenses
            ) { saved in
                appState.groupSessions.report(.expenseEdited(saved), groupId: expense.groupId)
                onMoneyWrite?()
                dismiss()
            }
        }
        // Every member may delete anything, so the confirmation names what is going, not
        // who recorded it.
        .alert(
            L10n.Expense.deleteTitle(expense.description),
            isPresented: $showingDeleteConfirmation
        ) {
            Button(role: .destructive) { delete() } label: { Text(L10n.Common.delete) }
            Button(role: .cancel) {} label: { Text(L10n.Common.cancel) }
        } message: {
            Text(L10n.Expense.deleteMessage)
        }
    }

    // MARK: - Sections

    /// What it was, how much, and when — read top to bottom before anything else.
    private var hero: some View {
        VStack(spacing: 8) {
            Image(systemName: expense.category.glyph)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(expense.category.tint, in: Circle())
                .padding(.bottom, 4)
                .accessibilityHidden(true)

            Text(expense.description)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color("foreground"))
                .multilineTextAlignment(.center)

            Text(Money.formatted(amount: expense.amount))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color("foreground"))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(verbatim: "\(expense.category.name) · \(dateText)")
                .font(.subheadline)
                .foregroundStyle(Color("muted-foreground"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    /// The answer most people open an expense for: what it means for them. Worded as the
    /// timeline row says it, so the two read as the same fact.
    private var positionStrip: some View {
        let involvement = expense.involvement(of: currentUserId)
        let (label, amount, tint): (String, Double?, Color) = switch involvement {
        case .lent(let amount): (L10n.Group.youLent, amount, Color("positive"))
        case .borrowed(let amount): (L10n.Group.youBorrowed, amount, Color("negative"))
        case .paidForYourself: (L10n.Group.youPaidForYourself, nil, Color("muted-foreground"))
        case .notInvolved, .payment: (L10n.Group.notInvolved, nil, Color("muted-foreground"))
        }

        return HStack {
            Text(label.sentenceCased)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color("foreground"))

            Spacer(minLength: 12)

            if let amount {
                Text(Money.formatted(amount: amount))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var payerRow: some View {
        HStack(spacing: 12) {
            MemberAvatar(display: payerDisplay, size: 36)
            Text(payerDisplay.name)
                .font(.body.weight(expense.paidBy == currentUserId ? .semibold : .regular))
                .foregroundStyle(payerDisplay.isRemoved ? Color("muted-foreground") : Color("foreground"))
            Spacer(minLength: 12)
            Text(Money.formatted(amount: expense.amount))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color("foreground"))
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var splitRows: some View {
        VStack(spacing: 0) {
            ForEach(sortedSplits) { split in
                splitRow(split)
                if split.id != sortedSplits.last?.id {
                    Divider().padding(.leading, 48)
                }
            }
        }
    }

    /// One person's share. An uneven split draws each share against the total, so who
    /// carried most of it shows without reading a single number.
    private func splitRow(_ split: ExpenseSplit) -> some View {
        let display = display(for: split.userId)
        let isYou = split.userId == currentUserId

        return HStack(spacing: 12) {
            MemberAvatar(display: display, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                Text(display.name)
                    .font(.body.weight(isYou ? .semibold : .regular))
                    .foregroundStyle(display.isRemoved ? Color("muted-foreground") : Color("foreground"))

                if expense.splitMode != .equal, expense.amount > 0 {
                    ShareBar(fraction: split.amount / expense.amount, tint: expense.category.tint)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.formatted(amount: split.amount))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color("foreground"))

                // A percentage split shows the share it was written as next to the
                // money it came to: the payoff for storing the mode is that
                // reopening an expense answers "how was this split?".
                if let percentage = split.percentage, expense.splitMode == .percentage {
                    Text("\(Percent.string(Percent.value(from: percentage)))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color("muted-foreground"))
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// You first, then everyone else by the size of their share.
    private var sortedSplits: [ExpenseSplit] {
        expense.splits.sorted { lhs, rhs in
            if lhs.userId == currentUserId { return true }
            if rhs.userId == currentUserId { return false }
            return lhs.amount > rhs.amount
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("muted-foreground"))
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            content()
                .padding(.horizontal, 16)
                .background(Color("card"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    /// The stored mode, said once above the rows rather than repeated on each of them.
    private var splitHeader: String {
        switch expense.splitMode {
        case .equal: return L10n.Expense.splitEqually
        case .custom: return L10n.Expense.splitByAmounts
        case .percentage: return L10n.Expense.splitByPercentages
        case .none: return L10n.Expense.split
        }
    }

    private var payerDisplay: MemberDisplay {
        MemberDisplay(
            expense.paidByUser,
            currentUserId: currentUserId,
            currentUserLabel: L10n.Common.you
        )
    }

    private var dateText: String {
        guard let date = expense.effectiveDate else { return L10n.Expense.unknownDate }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month().year().inAppLanguage())
    }

    private func display(for userId: Int) -> MemberDisplay {
        if let member = members.first(where: { $0.userId == userId }) {
            let display = MemberDisplay(member)
            return userId == currentUserId
                ? MemberDisplay(name: L10n.Common.you, avatarURL: display.avatarURL, userID: userId)
                : display
        }

        if let user = expense.splits.first(where: { $0.userId == userId })?.user {
            return MemberDisplay(user)
        }

        return MemberDisplay(name: L10n.Common.unknown, avatarURL: nil)
    }

    private func delete() {
        isDeleting = true
        errorMessage = nil

        Task {
            defer { isDeleting = false }
            let outcome = await appState.groupSessions.delete(expense, groupId: expense.groupId).value
            if let failureMessage = outcome.failureMessage {
                errorMessage = failureMessage
                return
            }
            onMoneyWrite?()
            dismiss()
        }
    }
}

private struct ShareBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        Capsule()
            .fill(Color("muted"))
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(maxWidth: 160)
            .accessibilityHidden(true)
    }
}

private extension String {
    /// "you lent" as a line of its own: the timeline sets it mid-row, lowercase.
    var sentenceCased: String {
        prefix(1).uppercased() + dropFirst()
    }
}
