//
//  ExpenseFormViewModel.swift
//  Splitty
//

import Foundation

/// Backs the sheet used for both creating and editing an expense. `expense` decides which
/// of the two it is; everything else is identical.
///
/// The arithmetic lives in `AmountExpression` and `SplitConfiguration`; this holds the two
/// together, decides when Save is available, and turns the result into a request.
@MainActor
class ExpenseFormViewModel: ObservableObject {
    @Published var amount: AmountExpression
    @Published var description: String
    @Published var date: Date
    @Published var configuration: SplitConfiguration
    @Published var errorMessage: String?
    @Published var isSaving = false

    let groupId: Int
    let members: [GroupMember]
    let currentUserId: Int

    /// Each mode keeps its own draft for as long as the **sheet** is open. The split
    /// screen is pushed and popped constantly while composing, so holding the drafts there
    /// would lose a set of typed amounts to a back swipe.
    ///
    /// The text is kept, not only the parsed value: a half-typed `1.` survives the
    /// keystroke that would otherwise round it away, and a field left blank stays blank
    /// rather than reappearing as `0`.
    @Published private(set) var customText: [Int: String] = [:]
    @Published private(set) var percentageText: [Int: String] = [:]
    private var equalParticipants: Set<Int>
    private var customAmounts: [Int: Int] = [:]
    private var percentages: [Int: Decimal] = [:]

    private let existingExpenseId: Int?

    init(groupId: Int, members: [GroupMember], currentUserId: Int, expense: Expense? = nil) {
        self.groupId = groupId
        self.members = members
        self.currentUserId = currentUserId
        self.existingExpenseId = expense?.id

        if let expense {
            amount = AmountExpression(cents: Money.cents(from: expense.amount))
            description = expense.description
            date = expense.effectiveDate ?? Date()
            configuration = SplitConfiguration(restoredFrom: expense)
            equalParticipants = Set(expense.splits.map(\.userId))
        } else {
            amount = AmountExpression()
            description = ""
            date = Date()
            configuration = SplitConfiguration(
                payerId: currentUserId,
                mode: .equal(participants: Set(members.map(\.userId)))
            )
            equalParticipants = Set(members.map(\.userId))
        }

        // Editing loads both typed modes from what is stored; a new expense starts them
        // empty, since a blank field is what says "not participating".
        if let expense {
            seedTypedDrafts(from: expense)
        }
    }

    /// The stored amounts fill the custom draft whatever the mode was — they are the
    /// numbers on the row either way. Percentages only exist on a percentage expense, so
    /// that draft stays empty unless the row carries them.
    private func seedTypedDrafts(from expense: Expense) {
        for split in expense.splits {
            let cents = Money.cents(from: split.amount)
            customAmounts[split.userId] = cents
            customText[split.userId] = Money.plainString(cents: cents)
        }

        if case .percentage(let stored) = configuration.mode {
            percentages = stored
            percentageText = stored.mapValues(Percent.string)
        }
    }

    // MARK: - Reading

    var isEditing: Bool { existingExpenseId != nil }

    var title: String { isEditing ? "Edit expense" : "New expense" }

    var memberIds: [Int] { members.map(\.userId) }

    /// The whole expression's value, pending operation included: Save auto-evaluates rather
    /// than refusing to save a number the app can compute.
    var totalCents: Int { amount.resolvedCents }

    var splitSummary: String {
        configuration.summary(members: members, currentUserId: currentUserId)
    }

    /// Which of the three the split screen's selector shows.
    var selectedMode: ExpenseSplitMode { configuration.mode.wireValue }

    /// The per-person amounts as they stand, for the split screen's rows.
    var perParticipantAmounts: [Int: Int] { configuration.amounts(totalCents: totalCents) }

    /// Only locally-provable violations block Save. Everything else — anything that depends
    /// on server state — is left to the server's `400`, rendered inline.
    var canSave: Bool {
        !isSaving
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && configuration.blockingReason(totalCents: totalCents) == nil
    }

    /// What is wrong with the *split*, in words. An amount of zero says so by being an
    /// empty amount field, so it gets no message.
    var blockingMessage: String? {
        switch configuration.blockingReason(totalCents: totalCents) {
        case .none, .amountNotPositive:
            return nil
        case .noParticipants:
            return "Select who this is split between"
        case .unassigned(let cents):
            return cents > 0
                ? "\(Money.formatted(cents: cents)) left to assign"
                : "\(Money.formatted(cents: -cents)) over the total"
        case .unassignedPercent(let percent):
            return percent > 0
                ? "\(Percent.string(percent))% left to assign"
                : "\(Percent.string(-percent))% over 100%"
        case .percentageRoundsToZero(let userId):
            // The API rejects a split of zero, and the reason is invisible from the field:
            // the share is a real number, it is the total that is too small for it.
            return "\(name(for: userId))'s share rounds down to nothing"
        }
    }

    func isParticipant(_ userId: Int) -> Bool {
        switch configuration.mode {
        case .equal(let participants): return participants.contains(userId)
        case .custom(let amounts): return (amounts[userId] ?? 0) > 0
        case .percentage(let percentages): return (percentages[userId] ?? 0) > 0
        }
    }

    func name(for userId: Int) -> String {
        userId == currentUserId
            ? "You"
            : members.first { $0.userId == userId }?.name ?? "Unknown"
    }

    func splits() -> [ExpenseSplitRequest] {
        configuration.splits(totalCents: totalCents)
    }

    // MARK: - Split configuration

    /// Switching modes swaps in that mode's draft. Nothing is derived from the mode being
    /// left: a percentage split is not seeded from the equal division it replaces, because
    /// the whole reason to switch is that the equal division is wrong.
    func selectMode(_ mode: ExpenseSplitMode) {
        switch mode {
        case .equal:
            configuration.mode = .equal(participants: equalParticipants)
        case .custom:
            configuration.mode = .custom(amounts: customAmounts)
        case .percentage:
            configuration.mode = .percentage(percentages: percentages)
        }
    }

    /// Unchecking a member re-derives the split across the rest and drops them from the
    /// payload. Equal splits only: the typed modes say the same thing with an empty field.
    func toggleParticipant(_ userId: Int) {
        guard case .equal(var participants) = configuration.mode else { return }

        if participants.contains(userId) {
            participants.remove(userId)
        } else {
            participants.insert(userId)
        }

        equalParticipants = participants
        configuration.mode = .equal(participants: participants)
    }

    /// A blank field is not a participant, which is why the row is removed rather than set
    /// to zero: zero would be a share the API refuses, blank is someone left out.
    func setCustomText(_ text: String, for userId: Int) {
        customText[userId] = text

        if let cents = Money.cents(fromTypedText: text), cents > 0 {
            customAmounts[userId] = cents
        } else {
            customAmounts.removeValue(forKey: userId)
        }

        if case .custom = configuration.mode {
            configuration.mode = .custom(amounts: customAmounts)
        }
    }

    func setPercentageText(_ text: String, for userId: Int) {
        percentageText[userId] = text

        if let percent = Percent.value(fromTypedText: text), percent > 0 {
            percentages[userId] = percent
        } else {
            percentages.removeValue(forKey: userId)
        }

        if case .percentage = configuration.mode {
            configuration.mode = .percentage(percentages: percentages)
        }
    }

    func setPayer(_ userId: Int) {
        configuration.payerId = userId
    }

    // MARK: - Saving

    /// Returns the saved expense on success, nil on failure.
    func save() async -> Expense? {
        guard canSave else { return nil }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let total = totalCents

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let expenseId = existingExpenseId {
                return try await ExpenseService.shared.updateExpense(
                    groupId: groupId,
                    expenseId: expenseId,
                    description: trimmedDescription,
                    amountCents: total,
                    paidBy: configuration.payerId,
                    date: date,
                    splitMode: configuration.mode.wireValue,
                    splits: splits()
                )
            }

            return try await ExpenseService.shared.createExpense(
                groupId: groupId,
                description: trimmedDescription,
                amountCents: total,
                paidBy: configuration.payerId,
                date: date,
                splitMode: configuration.mode.wireValue,
                splits: splits()
            )
        } catch {
            errorMessage = error.displayMessage
            return nil
        }
    }
}
