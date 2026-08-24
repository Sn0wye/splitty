//
//  SplitConfiguration.swift
//  Splitty
//

import Foundation

/// How the per-user amounts were derived. Stored by the API as of the split-mode column,
/// so reopening an expense recovers the mode instead of guessing it from the numbers.
enum SplitMode: Equatable {
    /// Divided evenly across the checked members.
    case equal(participants: Set<Int>)
    /// Typed per person, in cents.
    case custom(amounts: [Int: Int])
    /// Typed per person, in percent units (`70`). Amounts derive from the total on demand,
    /// exactly as `.equal` does — a cached copy would go stale the moment the total moved.
    case percentage(percentages: [Int: Decimal])

    /// The value the API stores alongside the amounts.
    var wireValue: ExpenseSplitMode {
        switch self {
        case .equal: return .equal
        case .custom: return .custom
        case .percentage: return .percentage
        }
    }
}

/// Percent units (`70`, `12.5`), kept in `Decimal` so a typed share is the share the user
/// typed rather than the nearest binary approximation of it.
enum Percent {
    static func value(fromTypedText text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The API sends percentages as JSON numbers; two places is the scale it stores.
    static func value(from value: Double) -> Decimal {
        var rounded = Decimal()
        var raw = Decimal(value)
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return rounded
    }

    /// `20`, `12.5` — no trailing zeros, for both fields and prose.
    static func string(_ value: Decimal) -> String {
        var rounded = Decimal()
        var raw = value
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}

/// Why Save is unavailable. Only locally-provable violations appear here; anything that
/// depends on server state is left to the server's `400`.
enum SplitBlock: Equatable {
    case amountNotPositive
    case noParticipants
    /// Positive when the custom amounts fall short of the total, negative when they exceed it.
    case unassigned(cents: Int)
    /// Positive when the percentages fall short of 100, negative when they exceed it.
    case unassignedPercent(Decimal)
    /// A positive percentage that lands on zero cents — `0.4%` of `$1.00`. The API rejects
    /// a split that is not greater than zero, on grounds the user cannot see from here.
    case percentageRoundsToZero(userId: Int)
}

/// Who paid and who owes, in integer cents.
struct SplitConfiguration: Equatable {
    var payerId: Int
    var mode: SplitMode

    init(payerId: Int, mode: SplitMode) {
        self.payerId = payerId
        self.mode = mode
    }

    // MARK: - Equal division

    /// Divides `totalCents` across `userIds`, giving the remainder cents to the first
    /// participants by **ascending user id**. Deterministic and device-independent; giving
    /// them to the payer instead would bias one person across many expenses.
    static func equalAmounts(totalCents: Int, among userIds: some Collection<Int>) -> [Int: Int] {
        guard !userIds.isEmpty, totalCents > 0 else { return [:] }

        let ordered = userIds.sorted()
        let base = totalCents / ordered.count
        let remainder = totalCents % ordered.count

        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { index, userId in
            (userId, base + (index < remainder ? 1 : 0))
        })
    }

    // MARK: - Percentage division

    /// Floors every share, then hands the leftover cents out one each by **ascending user
    /// id** — the same rule the equal split uses, for the same reason.
    ///
    /// A share of zero or less is not a participant and gets no row. When the percentages
    /// do not sum to 100 the result deliberately does not reach the total: that is a
    /// blocked save, not something to paper over by inflating someone's share.
    static func percentageAmounts(totalCents: Int, percentages: [Int: Decimal]) -> [Int: Int] {
        let participants = percentages.filter { $0.value > 0 }.sorted { $0.key < $1.key }
        guard !participants.isEmpty, totalCents > 0 else { return [:] }

        var amounts = Dictionary(uniqueKeysWithValues: participants.map { userId, percentage in
            (userId, flooredCents(totalCents: totalCents, percentage: percentage))
        })

        var leftover = totalCents - amounts.values.reduce(0, +)
        for (userId, _) in participants where leftover > 0 {
            amounts[userId, default: 0] += 1
            leftover -= 1
        }

        return amounts
    }

    private static func flooredCents(totalCents: Int, percentage: Decimal) -> Int {
        var floored = Decimal()
        var exact = Decimal(totalCents) * percentage / 100
        NSDecimalRound(&floored, &exact, 0, .down)
        return NSDecimalNumber(decimal: floored).intValue
    }

    // MARK: - Resolving

    /// The amount each participant owes, in cents.
    func amounts(totalCents: Int) -> [Int: Int] {
        switch mode {
        case .equal(let participants):
            return Self.equalAmounts(totalCents: totalCents, among: participants)
        case .custom(let amounts):
            return amounts
        case .percentage(let percentages):
            return Self.percentageAmounts(totalCents: totalCents, percentages: percentages)
        }
    }

    /// The payload. A participant who lands on zero is **omitted** rather than sent as `0`:
    /// the API rejects a split that is not greater than zero.
    func splits(totalCents: Int) -> [ExpenseSplitRequest] {
        let percentages: [Int: Decimal]
        if case .percentage(let typed) = mode { percentages = typed } else { percentages = [:] }

        return amounts(totalCents: totalCents)
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { ExpenseSplitRequest(
                userId: $0.key,
                amountCents: $0.value,
                percentage: percentages[$0.key]
            ) }
    }

    /// What is left to assign on a custom split — the exact-sum invariant rendered as a
    /// progress readout instead of a validation error.
    func unassignedCents(totalCents: Int) -> Int {
        guard case .custom(let amounts) = mode else { return 0 }
        return totalCents - amounts.values.reduce(0, +)
    }

    /// What is left to assign on a percentage split, in percent units.
    var unassignedPercent: Decimal {
        guard case .percentage(let percentages) = mode else { return 0 }
        return 100 - percentages.values.filter { $0 > 0 }.reduce(Decimal(0), +)
    }

    func blockingReason(totalCents: Int) -> SplitBlock? {
        guard totalCents > 0 else { return .amountNotPositive }

        switch mode {
        case .equal(let participants):
            return participants.isEmpty ? .noParticipants : nil
        case .custom:
            let unassigned = unassignedCents(totalCents: totalCents)
            return unassigned == 0 ? nil : .unassigned(cents: unassigned)
        case .percentage(let percentages):
            let participants = percentages.filter { $0.value > 0 }.keys.sorted()
            if participants.isEmpty { return .noParticipants }

            let unassigned = unassignedPercent
            if unassigned != 0 { return .unassignedPercent(unassigned) }

            // Checked against the derived amounts, not the raw share: a share that floors
            // to nothing may still be handed a leftover cent.
            let amounts = Self.percentageAmounts(totalCents: totalCents, percentages: percentages)
            if let starved = participants.first(where: { (amounts[$0] ?? 0) == 0 }) {
                return .percentageRoundsToZero(userId: starved)
            }
            return nil
        }
    }

    // MARK: - Reopening

    /// Rebuilds the configuration an expense was saved with. The stored mode is what says
    /// how to read the rows; a row with no usable mode — a settlement, a row older than
    /// the column, a mode this build does not know — falls back to inference.
    init(restoredFrom expense: Expense) {
        payerId = expense.paidBy
        mode = Self.storedMode(of: expense) ?? Self.inferredMode(of: expense)
    }

    /// The fallback for a row with no usable mode: **equal** when the stored amounts match
    /// within a cent — a remainder cent is still an equal split — and **custom** otherwise.
    /// It keeps the stored amounts either way, so opening a `$60`/`$40` row to look at it
    /// cannot rewrite it to `$50`/`$50`.
    init(inferredFrom expense: Expense) {
        payerId = expense.paidBy
        mode = Self.inferredMode(of: expense)
    }

    /// The mode the row names, when it names one this build can act on.
    private static func storedMode(of expense: Expense) -> SplitMode? {
        let amounts = Dictionary(
            uniqueKeysWithValues: expense.splits.map { ($0.userId, Money.cents(from: $0.amount)) }
        )

        switch expense.splitMode {
        case .equal:
            return .equal(participants: Set(amounts.keys))
        case .custom:
            return .custom(amounts: amounts)
        case .percentage:
            let percentages = expense.splits.compactMap { split -> (Int, Decimal)? in
                guard let percentage = split.percentage else { return nil }
                return (split.userId, Percent.value(from: percentage))
            }
            // A percentage row missing its percentage cannot be edited as one, so it is
            // read by its amounts rather than reopened half-empty.
            guard percentages.count == expense.splits.count else { return nil }
            return .percentage(percentages: Dictionary(uniqueKeysWithValues: percentages))
        case .none:
            return nil
        }
    }

    private static func inferredMode(of expense: Expense) -> SplitMode {
        let amounts = Dictionary(
            uniqueKeysWithValues: expense.splits.map { ($0.userId, Money.cents(from: $0.amount)) }
        )

        guard let lowest = amounts.values.min(), let highest = amounts.values.max() else {
            return .equal(participants: [])
        }

        return highest - lowest <= 1
            ? .equal(participants: Set(amounts.keys))
            : .custom(amounts: amounts)
    }

    // MARK: - Summary

    /// The line the sheet shows in place of the split screen.
    func summary(members: [GroupMember], currentUserId: Int) -> String {
        let payer = payerId == currentUserId
            ? "you"
            : members.first { $0.userId == payerId }?.name ?? "someone else"

        switch mode {
        case .custom:
            return "Paid by \(payer) and split by amounts"
        case .percentage:
            // Leaving the split screen at 80% is allowed; the line is where the missing
            // fifth is said out loud, since Save only says that something is wrong.
            let unassigned = unassignedPercent
            if unassigned > 0 {
                return "Paid by \(payer), \(Percent.string(unassigned))% left to assign"
            }
            if unassigned < 0 {
                return "Paid by \(payer), \(Percent.string(-unassigned))% over 100%"
            }
            return "Paid by \(payer) and split by percentages"
        case .equal(let participants):
            if participants.count == 1, let onlyId = participants.first, onlyId != payerId {
                let debtor = onlyId == currentUserId
                    ? "you owe"
                    : "\(members.first { $0.userId == onlyId }?.name ?? "they") owes"
                return "Paid by \(payer), \(debtor) the full amount"
            }
            if participants.count == members.count || members.isEmpty {
                return "Paid by \(payer) and split equally"
            }
            return "Paid by \(payer) and split equally between \(participants.count) people"
        }
    }
}
