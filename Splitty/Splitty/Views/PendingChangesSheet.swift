import SwiftUI

/// The writes this device holds for a group, with what can be done about each one the server
/// refused. Nothing here is ever dropped without the member choosing to (ADR 0008).
struct PendingChangesSheet: View {
    @ObservedObject var session: GroupSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if session.unsentWrites.isEmpty {
                    Text(L10n.Sync.allSent)
                        .foregroundStyle(Color("muted-foreground"))
                } else {
                    ForEach(session.unsentWrites) { write in
                        PendingChangeRow(
                            write: write,
                            currency: session.currency,
                            isSending: session.outbox?.isSending(write) == true,
                            actions: actions(for: write)
                        )
                    }
                }
            }
            .navigationTitle(Text(L10n.Sync.unsentTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text(L10n.Common.done) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func actions(for write: PendingWrite) -> [PendingChangeAction] {
        guard let outbox = session.outbox, let problem = write.problem else { return [] }
        let discard = PendingChangeAction(title: L10n.Sync.discard, role: .destructive) {
            outbox.discard(write.id)
        }
        switch problem {
        case .conflict(let theirs):
            guard case .editExpense(let request, _, let row) = write.action else { return [discard] }
            return [
                PendingChangeAction(title: L10n.Sync.keepMine) {
                    outbox.resolve(write.id) { write in
                        write.action = .editExpense(EditMerge.overwriting(request, theirs: theirs), base: theirs, row: row)
                    }
                },
                PendingChangeAction(title: L10n.Sync.keepTheirs, role: .destructive) {
                    outbox.discard(write.id)
                }
            ]
        case .deletedElsewhere:
            guard case .editExpense(let request, let base, _) = write.action else { return [discard] }
            return [
                PendingChangeAction(title: L10n.Sync.saveAsNew) {
                    saveAsNew(request, base: base, replacing: write, outbox: outbox)
                },
                discard
            ]
        case .overCap(let capCents):
            guard capCents > 0, case .settle(let draft, let row) = write.action else { return [discard] }
            let capped = SettleDraft(payeeId: draft.payeeId, amountCents: capCents, date: draft.date, currency: draft.currency)
            let cappedRow = PendingRows.payment(capped, payerId: row.paidBy, id: row.id, groupId: write.groupId,
                                                clientId: write.id, members: session.members)
            return [
                PendingChangeAction(title: L10n.Sync.recordAmount(Money.formatted(cents: capCents, currency: session.currency))) {
                    outbox.resolve(write.id) { $0.action = .settle(capped, row: cappedRow) }
                    session.resizeQueuedPayment(clientId: write.id, toCents: capCents)
                },
                discard
            ]
        case .currencyChanged:
            return [
                PendingChangeAction(title: L10n.Sync.saveAnyway) {
                    outbox.resolve(write.id) { write in write.action = Self.withoutCurrency(write.action) }
                },
                discard
            ]
        case .refused:
            return [discard]
        }
    }

    /// The edit, recorded as a new expense: the row it edited is gone for good, and a delete
    /// is never undone, so this is a new row with its own id.
    private func saveAsNew(_ request: ExpenseUpdateRequest, base: Expense, replacing write: PendingWrite, outbox: Outbox) {
        let edited = PendingRows.applying(request, to: base, members: session.members)
        let clientId = UUID()
        let create = NewExpenseRequest(
            groupId: base.groupId,
            description: edited.description,
            amountCents: Money.cents(from: edited.amount),
            paidBy: edited.paidBy,
            date: edited.effectiveDate,
            category: edited.category,
            splitMode: edited.splitMode ?? .custom,
            splits: edited.splits.map {
                ExpenseSplitRequest(
                    userId: $0.userId,
                    amountCents: Money.cents(from: $0.amount),
                    percentage: $0.percentage.map { Decimal($0) }
                )
            },
            clientId: clientId,
            currency: session.currency
        )
        let row = PendingRows.expense(from: create, id: outbox.makeLocalId(), clientId: clientId, members: session.members)
        outbox.discard(write.id)
        outbox.enqueue(PendingWrite(id: clientId, groupId: base.groupId, action: .createExpense(create, row: row)))
        session.report(.expenseCreated(row))
    }

    private static func withoutCurrency(_ action: PendingWrite.Action) -> PendingWrite.Action {
        switch action {
        case .createExpense(var request, let row):
            request.currency = nil
            return .createExpense(request, row: row)
        case .editExpense(var request, let base, let row):
            request.currency = nil
            return .editExpense(request, base: base, row: row)
        case .settle(var draft, let row):
            draft.currency = nil
            return .settle(draft, row: row)
        case .deleteExpense, .deleteSettlement:
            return action
        }
    }
}

struct PendingChangeAction: Identifiable {
    let id = UUID()
    let title: String
    var role: ButtonRole? = nil
    let perform: () -> Void
}

private struct PendingChangeRow: View {
    let write: PendingWrite
    let currency: Currency
    let isSending: Bool
    let actions: [PendingChangeAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color("muted-foreground"))
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color("foreground"))
                }
                Spacer()
                Text(Money.formatted(cents: Money.cents(from: write.row.amount), currency: currency))
                    .monospacedDigit()
                    .foregroundStyle(Color("foreground"))
            }

            if let status {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(write.problem == nil ? Color("muted-foreground") : Color("negative"))
            }

            // The other member's version, so choosing between the two is an informed choice.
            if case .conflict(let theirs) = write.problem {
                Text(L10n.Sync.theirVersion(
                    theirs.description,
                    Money.formatted(cents: Money.cents(from: theirs.amount), currency: currency)
                ))
                .font(.subheadline)
                .foregroundStyle(Color("muted-foreground"))
            }

            if !actions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(actions) { action in
                        Button(role: action.role, action: action.perform) {
                            Text(action.title)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        write.row.type == .payment ? L10n.Sync.payment : write.row.description
    }

    private var kind: String {
        switch write.action {
        case .createExpense: L10n.Sync.kindNewExpense
        case .editExpense: L10n.Sync.kindEdit
        case .deleteExpense, .deleteSettlement: L10n.Sync.kindDelete
        case .settle: L10n.Sync.kindNewPayment
        }
    }

    private var status: String? {
        if isSending { return L10n.Sync.sending }
        switch write.problem {
        case nil: return L10n.Sync.rowWaiting
        case .conflict: return L10n.Sync.problemConflict
        case .deletedElsewhere: return L10n.Sync.problemDeleted
        case .overCap(let cap):
            return cap > 0
                ? L10n.Sync.problemOverCap(Money.formatted(cents: cap, currency: currency))
                : L10n.Sync.problemNothingOwed
        case .currencyChanged: return L10n.Sync.problemCurrency
        case .refused(let message): return message
        }
    }
}
