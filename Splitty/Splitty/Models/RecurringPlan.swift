//
//  RecurringPlan.swift
//  Splitty
//

import Foundation

/// An active recurring expense as the Plans screen lists it: one that is neither finished
/// nor stopped.
struct RecurringPlan: Codable, Identifiable, Equatable {
    let id: Int
    let description: String
    let amount: Double
    let category: ExpenseCategory
    let paidBy: Int
    /// Nil on a frequency this build does not recognise.
    let frequency: ExpenseRepeat?
    /// The day the next expense will be added, `yyyy-MM-dd`.
    let nextDueOn: String
    /// The last day an expense may be added on, `yyyy-MM-dd`; nil when it never ends.
    let endsOn: String?
    let progress: Progress

    /// `added` of `total` expenses. `total` is nil when it never ends.
    struct Progress: Codable, Equatable {
        let added: Int
        let total: Int?
    }

    /// "4 of 12", or "No end".
    var progressText: String {
        guard let total = progress.total else { return L10n.Plans.noEnd }
        return L10n.Plans.progress(progress.added, total)
    }

    /// Lenient on `frequency` and `category` for the same reason `Expense` is: a value added
    /// later must not fail the whole list.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        description = try container.decode(String.self, forKey: .description)
        amount = try container.decode(Double.self, forKey: .amount)
        category = (try? container.decode(ExpenseCategory.self, forKey: .category)) ?? .general
        paidBy = try container.decode(Int.self, forKey: .paidBy)
        frequency = try? container.decodeIfPresent(ExpenseRepeat.self, forKey: .frequency)
        nextDueOn = try container.decode(String.self, forKey: .nextDueOn)
        endsOn = try container.decodeIfPresent(String.self, forKey: .endsOn)
        progress = try container.decode(Progress.self, forKey: .progress)
    }

    init(
        id: Int,
        description: String,
        amount: Double,
        category: ExpenseCategory,
        paidBy: Int,
        frequency: ExpenseRepeat?,
        nextDueOn: String,
        endsOn: String?,
        progress: Progress
    ) {
        self.id = id
        self.description = description
        self.amount = amount
        self.category = category
        self.paidBy = paidBy
        self.frequency = frequency
        self.nextDueOn = nextDueOn
        self.endsOn = endsOn
        self.progress = progress
    }

    private enum CodingKeys: String, CodingKey {
        case id, description, amount, category, paidBy, frequency, nextDueOn, endsOn, progress
    }

    /// The newest expense this recurring expense added, which is where a member edits or
    /// stops it. Nil when none of `expenses` is one of them.
    func latestExpense(in expenses: [Expense]) -> Expense? {
        expenses
            .filter { $0.recurringExpenseId == id }
            .max { ($0.effectiveDate ?? .distantPast, $0.id) < ($1.effectiveDate ?? .distantPast, $1.id) }
    }
}
