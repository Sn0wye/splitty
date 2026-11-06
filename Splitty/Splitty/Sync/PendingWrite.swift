import Foundation

/// A settlement recorded on this device, as it will be sent.
struct SettleDraft: Codable, Equatable {
    let payeeId: Int
    let amountCents: Int
    let date: Date
    var currency: Currency? = nil
}

/// A write made on this device that the server has not confirmed yet (ADR 0008).
///
/// `id` is also what makes a resend safe: it is the `clientId` of a create or a settlement
/// and the `opId` of an edit, so a write sent twice because its answer was lost lands once.
struct PendingWrite: Codable, Identifiable, Equatable {
    let id: UUID
    let groupId: Int
    var action: Action
    /// Set when the server refused the write in a way only the member can resolve. A write
    /// with a problem is not sent again until it is resolved.
    var problem: Problem? = nil
    var attempts: Int = 0
    var createdAt: Date = Date()

    enum Action: Codable, Equatable {
        /// `row` is what the timeline shows until the server answers, under a negative id.
        case createExpense(NewExpenseRequest, row: Expense)
        /// `base` is the row the edit was made against; `row` is what the timeline shows.
        /// `request` carries only the field groups that changed (see `FieldGroup`).
        case editExpense(ExpenseUpdateRequest, base: Expense, row: Expense)
        case deleteExpense(base: Expense)
        /// `row` is the payment the timeline shows, under a negative id.
        case settle(SettleDraft, row: Expense)
        case deleteSettlement(base: Expense)
    }

    enum Problem: Codable, Equatable {
        /// Another member edited the same fields. `theirs` is the row as it is now.
        case conflict(theirs: Expense)
        /// Another member deleted the row. A delete wins, so the edit can only become a new row.
        case deletedElsewhere
        /// The settlement is above what may be paid now.
        case overCap(capCents: Int)
        /// The group was relabelled to another currency (ADR 0007).
        case currencyChanged
        /// Refused for a reason the member cannot fix here, in the server's words.
        case refused(message: String)
    }

    /// The row the timeline shows for this write, or the one it removes.
    var row: Expense {
        switch action {
        case .createExpense(_, let row), .editExpense(_, _, let row), .settle(_, let row): row
        case .deleteExpense(let base), .deleteSettlement(let base): base
        }
    }

    var isSettlement: Bool {
        switch action {
        case .settle, .deleteSettlement: true
        case .createExpense, .editExpense, .deleteExpense: false
        }
    }

    var isDelete: Bool {
        switch action {
        case .deleteExpense, .deleteSettlement: true
        case .createExpense, .editExpense, .settle: false
        }
    }

    /// How this write moves each member's net once the server applies it.
    var nets: [Int: Int] {
        switch action {
        case .createExpense(_, let row), .settle(_, let row):
            LedgerMath.nets(of: row)
        case .editExpense(_, let base, let row):
            LedgerMath.adding(LedgerMath.nets(of: row), LedgerMath.nets(of: base).mapValues { -$0 })
        case .deleteExpense(let base), .deleteSettlement(let base):
            LedgerMath.nets(of: base).mapValues { -$0 }
        }
    }
}

// MARK: - Field groups

/// The parts of an expense an edit changes as a whole. Money is one group because the
/// splits must sum to the total: merging one member's amount with another's splits could
/// produce an expense nobody wrote and the server would refuse.
enum FieldGroup: Hashable {
    case money, description, category, date

    /// The groups that differ between two versions of the same row.
    static func changes(from base: Expense, to other: Expense) -> Set<FieldGroup> {
        var changed: Set<FieldGroup> = []
        if Money.cents(from: base.amount) != Money.cents(from: other.amount)
            || base.paidBy != other.paidBy
            || base.splitMode != other.splitMode
            || splitKey(base.splits) != splitKey(other.splits) {
            changed.insert(.money)
        }
        if base.description != other.description { changed.insert(.description) }
        if base.category != other.category { changed.insert(.category) }
        if wholeSeconds(base.effectiveDate) != wholeSeconds(other.effectiveDate) { changed.insert(.date) }
        return changed
    }

    /// The groups an edit request sends.
    static func sent(by request: ExpenseUpdateRequest) -> Set<FieldGroup> {
        var sent: Set<FieldGroup> = []
        if request.amountCents != nil || request.paidBy != nil || request.splitMode != nil || request.splits != nil {
            sent.insert(.money)
        }
        if request.description != nil { sent.insert(.description) }
        if request.category != nil { sent.insert(.category) }
        if request.date != nil { sent.insert(.date) }
        return sent
    }

    private static func splitKey(_ splits: [ExpenseSplit]) -> [String] {
        splits.map { "\($0.userId):\(Money.cents(from: $0.amount)):\($0.percentage.map { "\($0)" } ?? "-")" }.sorted()
    }

    static func wholeSeconds(_ date: Date?) -> Int? {
        date.map { Int($0.timeIntervalSince1970.rounded(.down)) }
    }
}

extension ExpenseUpdateRequest {
    /// This edit with every field group equal to `base` left out, so it changes only what
    /// the member changed. The form sends every field; the server treats an omitted field
    /// as unchanged, so the difference is what keeps an edit from undoing another member's.
    func changes(against base: Expense) -> ExpenseUpdateRequest {
        var patch = ExpenseUpdateRequest(groupId: groupId, expenseId: expenseId, reach: reach)
        let edited = PendingRows.applying(self, to: base, members: [])
        let changed = FieldGroup.changes(from: base, to: edited)
        if changed.contains(.money) {
            patch.amountCents = amountCents
            patch.paidBy = paidBy
            patch.splitMode = splitMode
            patch.splits = splits
        }
        if changed.contains(.description) { patch.description = description }
        if changed.contains(.category) { patch.category = category }
        if changed.contains(.date) { patch.date = date }
        patch.currency = currency
        return patch
    }

    /// Whether the edit changes anything at all.
    var isEmpty: Bool { FieldGroup.sent(by: self).isEmpty }
}

// MARK: - Merging

enum EditMerge {
    /// Resolves an edit that met a newer row. When the other edit changed different field
    /// groups, the result is this edit rebased onto `theirs`, ready to resend; when both
    /// changed the same group, nil, and the member chooses.
    static func rebase(
        _ request: ExpenseUpdateRequest,
        base: Expense,
        theirs: Expense
    ) -> ExpenseUpdateRequest? {
        let mine = FieldGroup.sent(by: request)
        let their = FieldGroup.changes(from: base, to: theirs)
        guard mine.isDisjoint(with: their) else { return nil }
        return overwriting(request, theirs: theirs)
    }

    /// This edit resent against `theirs`, keeping this member's version of every group it sends.
    static func overwriting(_ request: ExpenseUpdateRequest, theirs: Expense) -> ExpenseUpdateRequest {
        var rebased = request
        rebased.baseVersion = theirs.version
        return rebased
    }
}

// MARK: - Rows shown before the server answers

/// Builds the rows the timeline shows for a write the server has not confirmed. They are
/// display only: the server owns split identity, so the ids here are never sent.
enum PendingRows {
    static func user(for userId: Int, members: [GroupMember], fallback: User?, timestamp: String) -> User {
        if let member = members.first(where: { $0.userId == userId }) {
            return User(
                id: member.userId,
                name: member.name,
                email: member.email,
                avatarURL: member.avatarUrl.isEmpty ? nil : URL(string: member.avatarUrl),
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }
        return fallback ?? User(id: userId, name: "", email: "", createdAt: timestamp, updatedAt: timestamp)
    }

    static func expense(
        from request: NewExpenseRequest,
        id: Int,
        clientId: UUID,
        members: [GroupMember],
        now: Date = Date()
    ) -> Expense {
        let timestamp = ExpenseService.timestamp(from: now)
        return Expense(
            id: id,
            groupId: request.groupId,
            paidBy: request.paidBy,
            amount: Money.amount(cents: request.amountCents),
            description: request.description,
            type: .expense,
            category: request.category,
            splitMode: request.splitMode,
            date: request.date.map(ExpenseService.timestamp(from:)),
            createdAt: timestamp,
            updatedAt: timestamp,
            paidByUser: user(for: request.paidBy, members: members, fallback: nil, timestamp: timestamp),
            splits: splits(request.splits, expenseId: id, members: members, existing: [], timestamp: timestamp),
            clientId: clientId
        )
    }

    /// `base` with the fields `request` sends replaced. Members not in `members` keep the
    /// user `base` already had for them.
    static func applying(
        _ request: ExpenseUpdateRequest,
        to base: Expense,
        members: [GroupMember],
        now: Date? = nil
    ) -> Expense {
        let timestamp = now.map(ExpenseService.timestamp(from:)) ?? base.updatedAt
        let paidBy = request.paidBy ?? base.paidBy
        let existingUsers = [base.paidByUser] + base.splits.map(\.user)
        return Expense(
            id: base.id,
            groupId: base.groupId,
            paidBy: paidBy,
            amount: request.amountCents.map(Money.amount(cents:)) ?? base.amount,
            description: request.description ?? base.description,
            type: base.type,
            category: request.category ?? base.category,
            splitMode: request.splitMode ?? base.splitMode,
            date: request.date.map(ExpenseService.timestamp(from:)) ?? base.date,
            createdAt: base.createdAt,
            updatedAt: timestamp,
            paidByUser: user(
                for: paidBy,
                members: members,
                fallback: existingUsers.first { $0.id == paidBy },
                timestamp: timestamp
            ),
            splits: request.splits.map {
                splits($0, expenseId: base.id, members: members, existing: existingUsers, timestamp: timestamp)
            } ?? base.splits,
            recurringExpenseId: base.recurringExpenseId,
            repeatFrequency: base.repeatFrequency,
            endsOn: base.endsOn,
            installment: base.installment,
            clientId: base.clientId,
            version: base.version
        )
    }

    /// A payment from `payerId` to `payeeId`, built the way the server builds one: two
    /// opposite splits and the description the server writes (it is data, not copy; the row
    /// title is localized at render time).
    static func payment(
        _ draft: SettleDraft,
        payerId: Int,
        id: Int,
        groupId: Int,
        clientId: UUID,
        members: [GroupMember],
        now: Date = Date()
    ) -> Expense {
        let timestamp = ExpenseService.timestamp(from: now)
        let payer = user(for: payerId, members: members, fallback: nil, timestamp: timestamp)
        let payee = user(for: draft.payeeId, members: members, fallback: nil, timestamp: timestamp)
        let amount = Money.amount(cents: draft.amountCents)
        return Expense(
            id: id,
            groupId: groupId,
            paidBy: payerId,
            amount: amount,
            description: "Payment to \(payee.name)",
            type: .payment,
            category: .payment,
            splitMode: nil,
            date: ExpenseService.timestamp(from: draft.date),
            createdAt: timestamp,
            updatedAt: timestamp,
            paidByUser: payer,
            splits: [
                ExpenseSplit(id: id * 10, expenseId: id, userId: payerId, amount: amount, percentage: nil, user: payer),
                ExpenseSplit(id: id * 10 - 1, expenseId: id, userId: draft.payeeId, amount: -amount, percentage: nil, user: payee)
            ],
            clientId: clientId
        )
    }

    private static func splits(
        _ requests: [ExpenseSplitRequest],
        expenseId: Int,
        members: [GroupMember],
        existing: [User],
        timestamp: String
    ) -> [ExpenseSplit] {
        requests.enumerated().map { index, split in
            ExpenseSplit(
                id: -(abs(expenseId) * 100 + index + 1),
                expenseId: expenseId,
                userId: split.userId,
                amount: Money.amount(cents: split.amountCents),
                percentage: split.percentage.map { NSDecimalNumber(decimal: $0).doubleValue },
                user: user(
                    for: split.userId,
                    members: members,
                    fallback: existing.first { $0.id == split.userId },
                    timestamp: timestamp
                )
            )
        }
    }
}
