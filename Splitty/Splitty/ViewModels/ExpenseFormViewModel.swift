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
            configuration = SplitConfiguration(inferredFrom: expense)
        } else {
            amount = AmountExpression()
            description = ""
            date = Date()
            configuration = SplitConfiguration(
                payerId: currentUserId,
                mode: .equal(participants: Set(members.map(\.userId)))
            )
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

    var selectedPreset: SplitPreset? {
        SplitPreset.matching(configuration, memberIds: memberIds, currentUserId: currentUserId)
    }

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
        }
    }

    var isCustomSplit: Bool {
        if case .custom = configuration.mode { return true }
        return false
    }

    func isParticipant(_ userId: Int) -> Bool {
        switch configuration.mode {
        case .equal(let participants): return participants.contains(userId)
        case .custom(let amounts): return (amounts[userId] ?? 0) > 0
        }
    }

    func splits() -> [ExpenseSplitRequest] {
        configuration.splits(totalCents: totalCents)
    }

    // MARK: - Split configuration

    func apply(preset: SplitPreset, payerId: Int?) {
        switch preset {
        case .custom:
            // Seeded from whatever the split currently is: adjusting two numbers beats
            // typing every one of them.
            configuration = SplitConfiguration(
                payerId: payerId ?? configuration.payerId,
                mode: .custom(amounts: perParticipantAmounts)
            )
        default:
            configuration = preset.configuration(
                memberIds: memberIds,
                currentUserId: currentUserId,
                payerId: payerId
            )
        }
    }

    /// Unchecking a member re-derives the split across the rest and drops them from the
    /// payload; on a custom split it clears their row, which does the same thing.
    func toggleParticipant(_ userId: Int) {
        switch configuration.mode {
        case .equal(var participants):
            if participants.contains(userId) {
                participants.remove(userId)
            } else {
                participants.insert(userId)
            }
            configuration.mode = .equal(participants: participants)
        case .custom(var amounts):
            amounts[userId] = amounts[userId, default: 0] > 0 ? 0 : nil
            if amounts[userId] == nil { amounts.removeValue(forKey: userId) }
            configuration.mode = .custom(amounts: amounts)
        }
    }

    func setCustomAmount(_ cents: Int, for userId: Int) {
        guard case .custom(var amounts) = configuration.mode else { return }
        amounts[userId] = cents
        configuration.mode = .custom(amounts: amounts)
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
                    amount: Money.amount(cents: total),
                    paidBy: configuration.payerId,
                    date: date,
                    splits: splits()
                )
            }

            return try await ExpenseService.shared.createExpense(
                groupId: groupId,
                description: trimmedDescription,
                amount: Money.amount(cents: total),
                paidBy: configuration.payerId,
                date: date,
                splits: splits()
            )
        } catch {
            errorMessage = error.displayMessage
            return nil
        }
    }
}
