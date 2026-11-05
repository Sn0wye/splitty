import Foundation

/// The money writes that go through the outbox, so they work without a network and are
/// safe to send twice (ADR 0008). What cannot be queued safely still goes straight to the
/// server: an expense that repeats (its start may not be before today when it finally
/// lands), a "this and following" edit, and a settlement edit.
extension ExpenseFormDataSource {
    /// `row` finds the row an edit starts from as the timeline shows it, queued edits
    /// included, so the edit sends only what the member changed.
    static func queued(
        outbox: Outbox,
        members: [GroupMember],
        currency: Currency,
        row: @escaping @MainActor (Int) -> Expense?
    ) -> ExpenseFormDataSource {
        ExpenseFormDataSource(
            create: { request in
                guard request.repeats == nil else {
                    return try await ExpenseService.shared.createExpense(request)
                }
                let clientId = UUID()
                var request = request
                request.clientId = clientId
                request.currency = currency
                let local = PendingRows.expense(
                    from: request,
                    id: await outbox.makeLocalId(),
                    clientId: clientId,
                    members: members
                )
                let write = PendingWrite(id: clientId, groupId: request.groupId, action: .createExpense(request, row: local))
                switch await outbox.submit(write) {
                case .confirmed(let stored): return stored ?? local
                case .queued: return local
                case .refused(let error): throw error
                }
            },
            update: { request in
                if case .following = request.reach {
                    return try await ExpenseService.shared.updateExpense(request)
                }
                guard let base = await row(request.expenseId) else {
                    return try await ExpenseService.shared.updateExpense(request)
                }
                if base.id < 0, let create = await outbox.write(touching: base.id), await outbox.isSending(create) {
                    throw OfflineWriteError.stillSending
                }
                var patch = base.id < 0 ? request : request.changes(against: base)
                patch.baseVersion = base.version
                patch.currency = currency
                guard !patch.isEmpty else { return base }
                let edited = PendingRows.applying(patch, to: base, members: members, now: Date())
                let write = PendingWrite(
                    id: UUID(),
                    groupId: request.groupId,
                    action: .editExpense(patch, base: base, row: edited)
                )
                switch await outbox.submit(write) {
                case .confirmed(let stored): return stored ?? edited
                case .queued: return edited
                case .refused(let error): throw error
                }
            }
        )
    }
}

/// How a settlement went out through the outbox.
enum SettleUpSend {
    /// The server recorded it. `clientId` matches it to the row on the next read.
    case confirmed(clientId: UUID)
    /// Kept to send later.
    case queued(clientId: UUID)
}

extension SettleUpDataSource {
    static func queued(outbox: Outbox, currency: Currency) -> SettleUpDataSource {
        var source = SettleUpDataSource.live
        source.send = { groupId, peerId, amountCents, date in
            let clientId = UUID()
            let draft = SettleDraft(payeeId: peerId, amountCents: amountCents, date: date, currency: currency)
            let payerId = await outbox.userId ?? 0
            let row = PendingRows.payment(
                draft,
                payerId: payerId,
                id: await outbox.makeLocalId(),
                groupId: groupId,
                clientId: clientId,
                members: []
            )
            let write = PendingWrite(id: clientId, groupId: groupId, action: .settle(draft, row: row))
            switch await outbox.submit(write) {
            case .confirmed: return .confirmed(clientId: clientId)
            case .queued: return .queued(clientId: clientId)
            case .refused(let error): throw error
            }
        }
        return source
    }
}

enum OfflineWriteError: LocalizedError {
    /// The row's create is on the wire; editing it now could race the server's answer.
    case stillSending

    var errorDescription: String? {
        switch self {
        case .stillSending: L10n.Sync.stillSending
        }
    }
}
