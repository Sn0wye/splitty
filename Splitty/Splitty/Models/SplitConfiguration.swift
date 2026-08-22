//
//  SplitConfiguration.swift
//  Splitty
//

import Foundation

/// How the per-user amounts were derived. A client-only concept: the API takes absolute
/// amounts and stores no mode, so this never leaves the device.
enum SplitMode: Equatable {
    /// Divided evenly across the checked members.
    case equal(participants: Set<Int>)
    /// Typed per person, in cents.
    case custom(amounts: [Int: Int])
}

/// Why Save is unavailable. Only locally-provable violations appear here; anything that
/// depends on server state is left to the server's `400`.
enum SplitBlock: Equatable {
    case amountNotPositive
    case noParticipants
    /// Positive when the custom amounts fall short of the total, negative when they exceed it.
    case unassigned(cents: Int)
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

    // MARK: - Resolving

    /// The amount each participant owes, in cents.
    func amounts(totalCents: Int) -> [Int: Int] {
        switch mode {
        case .equal(let participants):
            return Self.equalAmounts(totalCents: totalCents, among: participants)
        case .custom(let amounts):
            return amounts
        }
    }

    /// The payload. A participant who lands on zero is **omitted** rather than sent as `0`:
    /// the API rejects a split that is not greater than zero.
    func splits(totalCents: Int) -> [ExpenseSplitRequest] {
        amounts(totalCents: totalCents)
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { ExpenseSplitRequest(userId: $0.key, amount: Money.amount(cents: $0.value)) }
    }

    /// What is left to assign on a custom split — the exact-sum invariant rendered as a
    /// progress readout instead of a validation error.
    func unassignedCents(totalCents: Int) -> Int {
        guard case .custom(let amounts) = mode else { return 0 }
        return totalCents - amounts.values.reduce(0, +)
    }

    func blockingReason(totalCents: Int) -> SplitBlock? {
        guard totalCents > 0 else { return .amountNotPositive }

        switch mode {
        case .equal(let participants):
            return participants.isEmpty ? .noParticipants : nil
        case .custom:
            let unassigned = unassignedCents(totalCents: totalCents)
            return unassigned == 0 ? nil : .unassigned(cents: unassigned)
        }
    }

    // MARK: - Reopening

    /// The API stores no split mode, so it is inferred: **equal** when the stored amounts
    /// match within a cent — a remainder cent is still an equal split — and **custom**
    /// otherwise. A wrong inference is harmless: the real stored amounts are on screen
    /// either way.
    init(inferredFrom expense: Expense) {
        payerId = expense.paidBy

        let amounts = Dictionary(
            uniqueKeysWithValues: expense.splits.map { ($0.userId, Money.cents(from: $0.amount)) }
        )

        guard let lowest = amounts.values.min(), let highest = amounts.values.max() else {
            mode = .equal(participants: [])
            return
        }

        mode = highest - lowest <= 1
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

/// A named starting point on the split screen: payer and mode in one tap.
enum SplitPreset: Hashable, CaseIterable, Identifiable {
    case youPaidSplitEqually
    case someoneElsePaidSplitEqually
    case youPaidTheyOweFull
    case theyPaidYouOweFull
    case custom

    var id: Self { self }

    /// "Owes the full amount" is offered only to two-person groups. In a larger group it
    /// would need a target picker, which is a custom split with extra steps.
    static func available(memberIds: [Int], currentUserId: Int) -> [SplitPreset] {
        allCases.filter { preset in
            switch preset {
            case .youPaidTheyOweFull, .theyPaidYouOweFull:
                return memberIds.count == 2 && memberIds.contains(currentUserId)
            default:
                return true
            }
        }
    }

    func title(members: [GroupMember], currentUserId: Int) -> String {
        switch self {
        case .youPaidSplitEqually: return "You paid, split equally"
        case .someoneElsePaidSplitEqually: return "Someone else paid, split equally"
        case .youPaidTheyOweFull:
            return "You paid, \(Self.otherName(members: members, currentUserId: currentUserId)) owes the full amount"
        case .theyPaidYouOweFull:
            return "\(Self.otherName(members: members, currentUserId: currentUserId)) paid, you owe the full amount"
        case .custom: return "Custom"
        }
    }

    /// `payerId` only matters for `someoneElsePaidSplitEqually`; the others derive the
    /// payer from the preset itself.
    func configuration(memberIds: [Int], currentUserId: Int, payerId: Int? = nil) -> SplitConfiguration {
        let others = memberIds.filter { $0 != currentUserId }.sorted()

        switch self {
        case .youPaidSplitEqually:
            return SplitConfiguration(payerId: currentUserId, mode: .equal(participants: Set(memberIds)))
        case .someoneElsePaidSplitEqually:
            return SplitConfiguration(
                payerId: payerId ?? others.first ?? currentUserId,
                mode: .equal(participants: Set(memberIds))
            )
        case .youPaidTheyOweFull:
            return SplitConfiguration(payerId: currentUserId, mode: .equal(participants: Set(others)))
        case .theyPaidYouOweFull:
            return SplitConfiguration(
                payerId: others.first ?? currentUserId,
                mode: .equal(participants: [currentUserId])
            )
        case .custom:
            return SplitConfiguration(payerId: payerId ?? currentUserId, mode: .custom(amounts: [:]))
        }
    }

    /// Which preset a configuration reads as, so the split screen can show the one in
    /// effect rather than always starting from the default.
    static func matching(
        _ configuration: SplitConfiguration,
        memberIds: [Int],
        currentUserId: Int
    ) -> SplitPreset? {
        // A custom split carries amounts a preset cannot reproduce, so it is recognised by
        // its mode rather than by rebuilding it.
        if case .custom = configuration.mode { return .custom }

        return available(memberIds: memberIds, currentUserId: currentUserId).first { preset in
            preset != .custom && preset.configuration(
                memberIds: memberIds,
                currentUserId: currentUserId,
                payerId: configuration.payerId
            ) == configuration
        }
    }

    private static func otherName(members: [GroupMember], currentUserId: Int) -> String {
        members.first { $0.userId != currentUserId }?.name ?? "they"
    }
}
