import Foundation
import Testing
@testable import Splitty

// MARK: - Fixtures

private func debt(_ from: Int, _ to: Int, _ cents: Int) -> SimplifiedDebt {
    SimplifiedDebt(
        from: DebtMember(id: from, name: "User \(from)", avatarUrl: ""),
        to: DebtMember(id: to, name: "User \(to)", avatarUrl: ""),
        amountCents: cents
    )
}

private func summary(_ debts: [SimplifiedDebt], pending: Bool = false) -> GroupBalanceSummary {
    GroupBalanceSummary(simplifiedDebts: debts, balancesPending: pending)
}

private func newExpense(amountCents: Int = 3000, splits: [Int: Int] = [1: 1500, 2: 1500]) -> NewExpenseRequest {
    NewExpenseRequest(
        groupId: 1,
        description: "Taxi",
        amountCents: amountCents,
        paidBy: 1,
        date: Date(timeIntervalSince1970: 1_790_000_000),
        category: .general,
        splitMode: .custom,
        splits: splits.sorted { $0.key < $1.key }.map {
            ExpenseSplitRequest(userId: $0.key, amountCents: $0.value, percentage: nil)
        }
    )
}

private func stored(from request: NewExpenseRequest, id: Int, version: Int = 1) -> Expense {
    var row = PendingRows.expense(from: request, id: id, clientId: request.clientId ?? UUID(), members: TestExpense.members)
    row.version = version
    return Expense(
        id: id, groupId: row.groupId, paidBy: row.paidBy, amount: row.amount, description: row.description,
        type: row.type, category: row.category, splitMode: row.splitMode, date: row.date,
        createdAt: row.createdAt, updatedAt: row.updatedAt, paidByUser: row.paidByUser,
        splits: row.splits.enumerated().map { index, split in
            ExpenseSplit(id: id * 10 + index, expenseId: id, userId: split.userId, amount: split.amount,
                         percentage: split.percentage, user: split.user)
        },
        clientId: request.clientId, version: version
    )
}

// MARK: - LedgerMath

struct LedgerMathTests {
    @Test func anExpenseMovesThePayerUpAndEachOtherParticipantDown() {
        let row = TestExpense.make(paidBy: 1, amount: 30, splitAmounts: [1: 10, 2: 10, 3: 10])

        #expect(LedgerMath.nets(of: row) == [1: 2000, 2: -1000, 3: -1000])
    }

    @Test func aPaymentPaysDownThePayersDebt() {
        let row = TestExpense.make(paidBy: 2, amount: 5, splitAmounts: [2: 5, 1: -5], type: .payment)

        #expect(LedgerMath.nets(of: row) == [2: 500, 1: -500])
    }

    @Test func simplifiedDebtsCarryEveryNet() {
        let nets = LedgerMath.nets(from: [debt(2, 1, 700), debt(3, 1, 300)])

        #expect(nets == [1: 1000, 2: -700, 3: -300])
        #expect(nets.values.reduce(0, +) == 0)
    }

    /// The server's case in `SimplifiedDebtTests`: debts of 7, 7, 6 and credits of 12, 8
    /// force the largest creditor to change after each match, ties going to the lower id.
    @Test func simplificationMatchesTheServersGreedyOrder() {
        let nets = [1: -700, 2: -700, 5: -600, 3: 1200, 4: 800]

        let payments = LedgerMath.simplify(nets).map { "\($0.from)>\($0.to):\($0.cents)" }

        #expect(payments == ["1>3:700", "2>4:700", "5>3:500", "5>4:100"])
    }

    @Test func projectionAddsUnsentWritesAndSimplifiesAgain() {
        let base = summary([debt(2, 1, 1000)])

        let projected = LedgerMath.projected(base, adding: [2: 1000, 1: -1000], members: TestExpense.members)

        #expect(projected.simplifiedDebts.isEmpty)
    }

    @Test func projectionNamesMembersTheSummaryDidNotMention() throws {
        let projected = LedgerMath.projected(summary([]), adding: [1: 500, 3: -500], members: TestExpense.members)

        let only = try #require(projected.simplifiedDebts.first)
        #expect(only.from.name == "Cara")
        #expect(only.to.name == "Alice")
        #expect(only.amountCents == 500)
    }

    @Test func theCapIsTheSmallerOfDebtAndCredit() {
        #expect(LedgerMath.cap([1: 800, 2: -500, 3: -300], payer: 2, payee: 1) == 500)
        #expect(LedgerMath.cap([1: 800, 2: -500, 3: -300], payer: 1, payee: 2) == 0)
    }
}

// MARK: - Pending writes

struct PendingWriteTests {
    private let base = TestExpense.make(id: 7, paidBy: 1, amount: 30, splitAmounts: [1: 15, 2: 15],
                                        splitMode: .equal, date: "2026-08-20T12:00:00Z")

    private func fullEdit(description: String? = nil, amountCents: Int = 3000, splits: [Int: Int] = [1: 1500, 2: 1500]) -> ExpenseUpdateRequest {
        ExpenseUpdateRequest(
            groupId: 1,
            expenseId: 7,
            description: description ?? base.description,
            amountCents: amountCents,
            paidBy: 1,
            date: base.effectiveDate,
            category: base.category,
            splitMode: .equal,
            splits: splits.sorted { $0.key < $1.key }.map {
                ExpenseSplitRequest(userId: $0.key, amountCents: $0.value, percentage: nil)
            }
        )
    }

    @Test func anEditSendsOnlyTheFieldGroupsThatChanged() {
        let patch = fullEdit(description: "Late dinner").changes(against: base)

        #expect(patch.description == "Late dinner")
        #expect(patch.amountCents == nil)
        #expect(patch.splits == nil)
        #expect(patch.date == nil)
        #expect(FieldGroup.sent(by: patch) == [.description])
    }

    @Test func anyMoneyChangeSendsTheWholeMoneyGroup() {
        let patch = fullEdit(amountCents: 4000, splits: [1: 2000, 2: 2000]).changes(against: base)

        #expect(patch.amountCents == 4000)
        #expect(patch.paidBy == 1)
        #expect(patch.splitMode == .equal)
        #expect(patch.splits?.map(\.amountCents) == [2000, 2000])
        #expect(patch.description == nil)
    }

    @Test func anUnchangedFormIsAnEmptyEdit() {
        #expect(fullEdit().changes(against: base).isEmpty)
    }

    @Test func anEditOfOtherFieldsRebasesOntoTheNewerRow() throws {
        var theirs = PendingRows.applying(ExpenseUpdateRequest(groupId: 1, expenseId: 7, category: .taxi), to: base, members: [])
        theirs.version = 2
        let mine = ExpenseUpdateRequest(groupId: 1, expenseId: 7, description: "Late dinner", baseVersion: 1)

        let rebased = try #require(EditMerge.rebase(mine, base: base, theirs: theirs))

        #expect(rebased.baseVersion == 2)
        #expect(rebased.description == "Late dinner")
        #expect(rebased.category == nil)
    }

    @Test func anEditOfTheSameFieldsWaitsForTheMember() {
        var theirs = PendingRows.applying(ExpenseUpdateRequest(groupId: 1, expenseId: 7, description: "Lunch"), to: base, members: [])
        theirs.version = 2
        let mine = ExpenseUpdateRequest(groupId: 1, expenseId: 7, description: "Late dinner", baseVersion: 1)

        #expect(EditMerge.rebase(mine, base: base, theirs: theirs) == nil)
    }

    @Test func anEditMovesNetsByTheDifference() {
        let edited = PendingRows.applying(fullEdit(amountCents: 4000, splits: [1: 2000, 2: 2000]), to: base, members: [])
        let write = PendingWrite(id: UUID(), groupId: 1, action: .editExpense(fullEdit(), base: base, row: edited))

        #expect(write.nets == [1: 500, 2: -500])
    }

    @Test func aDeleteUndoesTheRowsNets() {
        let write = PendingWrite(id: UUID(), groupId: 1, action: .deleteExpense(base: base))

        #expect(write.nets == [1: -1500, 2: 1500])
    }

    @Test func aQueuedWriteSurvivesEncoding() throws {
        let request = newExpense()
        let row = PendingRows.expense(from: request, id: -1_000_000, clientId: UUID(), members: TestExpense.members)
        let write = PendingWrite(id: UUID(), groupId: 1, action: .createExpense(request, row: row), problem: .overCap(capCents: 500))

        let decoded = try JSONDecoder().decode(PendingWrite.self, from: JSONEncoder().encode(write))

        #expect(decoded == write)
    }
}

// MARK: - LocalStore

struct LocalStoreTests {
    @Test func valuesAreKeptPerUser() {
        let store = LocalStore(url: nil)
        store.set(["a"], user: 1, key: "k")
        store.set(["b"], user: 2, key: "k")

        #expect(store.value([String].self, user: 1, key: "k") == ["a"])
        #expect(store.value([String].self, user: 2, key: "k") == ["b"])
    }

    @Test func pendingWritesKeepTheirOrder() {
        let store = LocalStore(url: nil)
        let writes = (0..<3).map { index in
            PendingWrite(id: UUID(), groupId: index, action: .deleteExpense(base: TestExpense.make(id: index + 1, paidBy: 1, amount: 1, splitAmounts: [1: 1])))
        }
        store.savePendingWrites(writes, user: 1)

        #expect(store.pendingWrites(user: 1).map(\.id) == writes.map(\.id))
        #expect(store.pendingWrites(user: 2).isEmpty)
    }

    @Test func removingAUserLeavesOthers() {
        let store = LocalStore(url: nil)
        store.set(1, user: 1, key: "k")
        store.set(2, user: 2, key: "k")

        store.removeAll(user: 1)

        #expect(store.value(Int.self, user: 1, key: "k") == nil)
        #expect(store.value(Int.self, user: 2, key: "k") == 2)
    }
}

// MARK: - Outbox

/// A server the outbox talks to, answering each call with what the test queued.
@MainActor
private final class FakeServer {
    var creates: [NewExpenseRequest] = []
    var updates: [ExpenseUpdateRequest] = []
    var deletes: [Int] = []
    var settles: [(SettleDraft, UUID)] = []
    var createAnswers: [Result<Expense, Error>] = []
    var updateAnswers: [Result<Expense, Error>] = []
    var deleteAnswers: [Error?] = []
    var settleAnswers: [Result<Expense, Error>] = []

    var transport: OutboxTransport {
        OutboxTransport(
            create: { request in try await MainActor.run { self.creates.append(request); return try self.createAnswers.removeFirst().get() } },
            update: { request in try await MainActor.run { self.updates.append(request); return try self.updateAnswers.removeFirst().get() } },
            deleteExpense: { _, id in try await MainActor.run {
                self.deletes.append(id)
                if !self.deleteAnswers.isEmpty, let error = self.deleteAnswers.removeFirst() { throw error }
            } },
            settle: { _, draft, clientId in try await MainActor.run {
                self.settles.append((draft, clientId))
                return try self.settleAnswers.removeFirst().get()
            } },
            deleteSettlement: { _, id in try await MainActor.run { self.deletes.append(id) } }
        )
    }
}

private let offline = APIError.networkError(URLError(.notConnectedToInternet))

@MainActor
struct OutboxTests {
    private func outbox(_ server: FakeServer, store: LocalStore = LocalStore(url: nil)) -> Outbox {
        // Retries never fire on their own: a test resumes the outbox when it wants a resend.
        let outbox = Outbox(store: store, transport: server.transport, wait: { _ in try await Task.sleep(for: .seconds(3600)) })
        outbox.setUser(1)
        return outbox
    }

    private func create(_ outbox: Outbox, _ request: NewExpenseRequest = newExpense()) -> PendingWrite {
        let clientId = UUID()
        var request = request
        request.clientId = clientId
        let row = PendingRows.expense(from: request, id: outbox.makeLocalId(), clientId: clientId, members: TestExpense.members)
        return PendingWrite(id: clientId, groupId: 1, action: .createExpense(request, row: row))
    }

    @Test func aWriteSentOnlineReturnsTheStoredRowAndLeavesNothingQueued() async {
        let server = FakeServer()
        let outbox = outbox(server)
        let write = create(outbox)
        server.createAnswers = [.success(stored(from: newExpense(), id: 40))]

        let result = await outbox.submit(write)

        guard case .confirmed(let row) = result else { Issue.record("expected confirmed, got \(result)"); return }
        #expect(row?.id == 40)
        #expect(outbox.writes.isEmpty)
        #expect(server.creates.first?.clientId == write.id)
    }

    @Test func aWriteThatFailsOnTheNetworkIsKeptAcrossLaunches() async {
        let server = FakeServer()
        let store = LocalStore(url: nil)
        let first = outbox(server, store: store)
        let write = create(first)
        server.createAnswers = [.failure(offline)]

        let result = await first.submit(write)

        guard case .queued = result else { Issue.record("expected queued, got \(result)"); return }
        let relaunched = Outbox(store: store, transport: server.transport, wait: { _ in try await Task.sleep(for: .seconds(3600)) })
        server.createAnswers = [.failure(offline)]
        relaunched.setUser(1)
        #expect(relaunched.writes.map(\.id) == [write.id])
    }

    @Test func aResendCarriesTheSameClientId() async {
        let server = FakeServer()
        let outbox = outbox(server)
        let write = create(outbox)
        server.createAnswers = [.failure(offline), .success(stored(from: newExpense(), id: 41))]
        _ = await outbox.submit(write)

        outbox.resume()
        await waitUntil { outbox.writes.isEmpty }

        #expect(server.creates.count == 2)
        #expect(Set(server.creates.map(\.clientId)) == [write.id])
    }

    @Test func anEditOfARowNotYetCreatedGoesOutWithTheCreate() async {
        let server = FakeServer()
        let outbox = outbox(server)
        let write = create(outbox)
        server.createAnswers = [.failure(offline)]
        _ = await outbox.submit(write)

        let edit = ExpenseUpdateRequest(groupId: 1, expenseId: write.row.id, description: "Airport taxi")
        let edited = PendingRows.applying(edit, to: write.row, members: TestExpense.members)
        let folded = outbox.enqueue(PendingWrite(id: UUID(), groupId: 1, action: .editExpense(edit, base: write.row, row: edited)))

        #expect(folded == nil)
        #expect(outbox.writes.count == 1)
        guard case .createExpense(let request, let row) = outbox.writes.first?.action else { Issue.record("not a create"); return }
        #expect(request.description == "Airport taxi")
        #expect(row.description == "Airport taxi")
    }

    @Test func deletingARowNotYetCreatedDropsBoth() async {
        let server = FakeServer()
        let outbox = outbox(server)
        let write = create(outbox)
        server.createAnswers = [.failure(offline)]
        _ = await outbox.submit(write)
        var dropped: [UUID] = []
        let subscription = outbox.events.sink { if case .dropped(let write) = $0 { dropped.append(write.id) } }

        outbox.enqueue(PendingWrite(id: UUID(), groupId: 1, action: .deleteExpense(base: write.row)))

        #expect(outbox.writes.isEmpty)
        #expect(dropped == [write.id])
        subscription.cancel()
    }

    @Test func aConflictOverOtherFieldsIsResentAgainstTheNewerRow() async {
        let server = FakeServer()
        let outbox = outbox(server)
        var base = stored(from: newExpense(), id: 50)
        base.version = 1
        var theirs = PendingRows.applying(ExpenseUpdateRequest(groupId: 1, expenseId: 50, category: .taxi), to: base, members: [])
        theirs.version = 2
        let mine = ExpenseUpdateRequest(groupId: 1, expenseId: 50, description: "Airport taxi", baseVersion: 1)
        let row = PendingRows.applying(mine, to: base, members: [])
        server.updateAnswers = [.failure(APIError.versionConflict(current: theirs, message: nil)), .success(theirs)]

        let result = await outbox.submit(PendingWrite(id: UUID(), groupId: 1, action: .editExpense(mine, base: base, row: row)))

        guard case .confirmed = result else { Issue.record("expected confirmed, got \(result)"); return }
        #expect(server.updates.map(\.baseVersion) == [1, 2])
        #expect(server.updates.last?.description == "Airport taxi")
        #expect(server.updates.last?.category == nil)
    }

    @Test func aConflictOverTheSameFieldsWaitsForTheMember() async {
        let server = FakeServer()
        let outbox = outbox(server)
        var base = stored(from: newExpense(), id: 51)
        base.version = 1
        var theirs = PendingRows.applying(ExpenseUpdateRequest(groupId: 1, expenseId: 51, description: "Bus"), to: base, members: [])
        theirs.version = 2
        let mine = ExpenseUpdateRequest(groupId: 1, expenseId: 51, description: "Airport taxi", baseVersion: 1)
        let row = PendingRows.applying(mine, to: base, members: [])
        server.updateAnswers = [.failure(APIError.versionConflict(current: theirs, message: nil))]

        let result = await outbox.submit(PendingWrite(id: UUID(), groupId: 1, action: .editExpense(mine, base: base, row: row)))

        guard case .queued = result else { Issue.record("expected queued, got \(result)"); return }
        #expect(outbox.writes.first?.problem == .conflict(theirs: theirs))
    }

    @Test func anEditOfARowDeletedElsewhereWaitsForTheMember() async {
        let server = FakeServer()
        let outbox = outbox(server)
        let base = stored(from: newExpense(), id: 52)
        let mine = ExpenseUpdateRequest(groupId: 1, expenseId: 52, description: "Airport taxi", baseVersion: 1)
        server.updateAnswers = [.failure(APIError.httpError(404, message: nil))]

        _ = await outbox.submit(PendingWrite(id: UUID(), groupId: 1, action: .editExpense(mine, base: base, row: base)))

        #expect(outbox.writes.first?.problem == .deletedElsewhere)
    }

    @Test func aDeleteOfARowAlreadyGoneIsDone() async {
        let server = FakeServer()
        let outbox = outbox(server)
        server.deleteAnswers = [APIError.httpError(404, message: nil)]

        let result = await outbox.submit(PendingWrite(id: UUID(), groupId: 1, action: .deleteExpense(base: stored(from: newExpense(), id: 53))))

        guard case .confirmed = result else { Issue.record("expected confirmed, got \(result)"); return }
        #expect(outbox.writes.isEmpty)
    }

    @Test func aRefusalOnTheFirstSendIsReturnedAndNothingIsKept() async {
        let server = FakeServer()
        let outbox = outbox(server)
        server.createAnswers = [.failure(APIError.httpError(400, message: "Expense splits must sum to the total."))]

        let result = await outbox.submit(create(outbox))

        guard case .refused(let error) = result else { Issue.record("expected refused, got \(result)"); return }
        #expect(error.displayMessage == "Expense splits must sum to the total.")
        #expect(outbox.writes.isEmpty)
    }

    @Test func aSettlementOverTheCapKeepsTheCapForTheMember() async {
        let server = FakeServer()
        let outbox = outbox(server)
        let draft = SettleDraft(payeeId: 2, amountCents: 1200, date: Date())
        let row = PendingRows.payment(draft, payerId: 1, id: outbox.makeLocalId(), groupId: 1, clientId: UUID(), members: TestExpense.members)
        let write = PendingWrite(id: row.clientId!, groupId: 1, action: .settle(draft, row: row))
        server.settleAnswers = [.failure(offline)]
        _ = await outbox.submit(write)
        server.settleAnswers = [.failure(APIError.settlementExceedsCap(capCents: 1000, message: nil))]

        outbox.resume()
        await waitUntil { outbox.writes.first?.problem != nil }

        #expect(outbox.writes.first?.problem == .overCap(capCents: 1000))
        #expect(server.settles.map(\.1) == [write.id, write.id])
    }

    @Test func writesGoOutInTheOrderTheyWereMade() async {
        let server = FakeServer()
        let outbox = outbox(server)
        let first = create(outbox, newExpense(amountCents: 1000, splits: [1: 500, 2: 500]))
        let second = create(outbox, newExpense(amountCents: 2000, splits: [1: 1000, 2: 1000]))
        server.createAnswers = [.failure(offline)]
        _ = await outbox.submit(first)
        outbox.enqueue(second)
        server.createAnswers = [.success(stored(from: newExpense(), id: 60)), .success(stored(from: newExpense(), id: 61))]

        outbox.resume()
        await waitUntil { outbox.writes.isEmpty }

        #expect(server.creates.map(\.amountCents) == [1000, 1000, 2000])
    }

    @Test func discardingAWriteDropsItAndTellsTheSession() async {
        let server = FakeServer()
        let outbox = outbox(server)
        let write = create(outbox)
        server.createAnswers = [.failure(offline)]
        _ = await outbox.submit(write)
        var dropped: [UUID] = []
        let subscription = outbox.events.sink { if case .dropped(let write) = $0 { dropped.append(write.id) } }

        outbox.discard(write.id)

        #expect(outbox.writes.isEmpty)
        #expect(dropped == [write.id])
        subscription.cancel()
    }
}

// MARK: - A group session without a network

@MainActor
struct OfflineGroupSessionTests {
    private let group = Group(id: 1, name: "Lisbon trip", description: nil, netBalanceCents: -500,
                              createdAt: "2026-01-01T12:00:00Z", members: TestExpense.members)

    private func unreachable() -> GroupDataSource {
        GroupDataSource(
            group: { _ in throw offline },
            expenses: { _ in throw offline },
            summary: { _ in throw offline },
            waitForBalanceRetry: { _ in try await Task.sleep(for: .seconds(3600)) },
            requestBalanceRefresh: { _ in throw offline },
            deleteExpense: { _, _, _ in throw offline },
            deletePayment: { _, _ in throw offline }
        )
    }

    private func outbox(_ server: FakeServer, store: LocalStore) -> Outbox {
        let outbox = Outbox(store: store, transport: server.transport, wait: { _ in try await Task.sleep(for: .seconds(3600)) })
        outbox.setUser(1)
        return outbox
    }

    @Test func aSavedGroupOpensWithItsRowsWhenTheReadFails() async {
        let store = LocalStore(url: nil)
        let cache = GroupCache(store: store, userId: 1)
        let row = TestExpense.make(id: 9, paidBy: 2, amount: 10, splitAmounts: [1: 5, 2: 5])
        cache.save(GroupSnapshot(group: group, expenses: [row], summary: summary([debt(1, 2, 500)]), savedAt: Date()), groupId: 1)

        let session = GroupSession(groupId: 1, dataSource: unreachable(), cache: cache)

        #expect(session.hasLoadedExpenses)
        #expect(session.expenses.map(\.id) == [9])
        // Not called old before the server had a chance to answer.
        #expect(session.savedAt == nil)
        await session.appear().value
        #expect(session.expenses.map(\.id) == [9])
        #expect(session.errorMessage.isEmpty)
        #expect(session.savedAt != nil)
    }

    @Test func aQueuedExpenseShowsAndCountsInTheEstimate() async {
        let store = LocalStore(url: nil)
        let server = FakeServer()
        let outbox = outbox(server, store: store)
        let session = GroupSession(groupId: 1, seed: group, dataSource: unreachable(), cache: GroupCache(store: store, userId: 1), outbox: outbox)
        server.createAnswers = [.failure(offline)]

        let source = session.expenseFormDataSource()
        let row = try? await source.create(newExpense())
        session.report(.expenseCreated(row!))

        #expect(session.expenses.contains { $0.id == row!.id })
        #expect(session.syncState(for: row!) == .waiting)
        // Alice paid 30 for both: Bob owes her 15 more than the server knows.
        #expect(session.netBalanceCents == -500 + 1500)
        #expect(session.hasUnsentWrites)
        #expect(!session.balancesPending)
    }

    @Test func aQueuedWriteIsShownAgainAfterARelaunch() {
        let store = LocalStore(url: nil)
        let server = FakeServer()
        let first = outbox(server, store: store)
        var request = newExpense()
        let clientId = UUID()
        request.clientId = clientId
        let row = PendingRows.expense(from: request, id: first.makeLocalId(), clientId: clientId, members: TestExpense.members)
        server.createAnswers = [.failure(offline)]
        first.enqueue(PendingWrite(id: clientId, groupId: 1, action: .createExpense(request, row: row)))

        let relaunched = outbox(server, store: store)
        let session = GroupSession(groupId: 1, seed: group, dataSource: unreachable(), outbox: relaunched)

        #expect(session.expenses.map(\.id) == [row.id])
        #expect(session.netBalanceCents == -500 + 1500)
    }

    @Test func aConfirmedWriteReplacesTheLocalRowAndKeepsTheEstimate() async {
        let store = LocalStore(url: nil)
        let server = FakeServer()
        let outbox = outbox(server, store: store)
        let session = GroupSession(groupId: 1, seed: group, dataSource: unreachable(), outbox: outbox)
        server.createAnswers = [.failure(offline)]
        let local = try! await session.expenseFormDataSource().create(newExpense())
        session.report(.expenseCreated(local))
        let request = { () -> NewExpenseRequest in var r = newExpense(); r.clientId = local.clientId; return r }()
        server.createAnswers = [.success(stored(from: request, id: 70))]

        outbox.resume()
        await waitUntil { outbox.writes.isEmpty }

        #expect(session.expenses.map(\.id) == [70])
        #expect(session.netBalanceCents == -500 + 1500)
        #expect(session.balancesPending)
    }

    @Test func aDeleteMadeOfflineHidesTheRowUntilSent() async {
        let store = LocalStore(url: nil)
        let server = FakeServer()
        let outbox = outbox(server, store: store)
        let row = TestExpense.make(id: 9, paidBy: 2, amount: 10, splitAmounts: [1: 5, 2: 5])
        let cache = GroupCache(store: store, userId: 1)
        cache.save(GroupSnapshot(group: group, expenses: [row], summary: summary([debt(1, 2, 500)]), savedAt: Date()), groupId: 1)
        let session = GroupSession(groupId: 1, dataSource: unreachable(), cache: cache, outbox: outbox)
        server.deleteAnswers = [offline]

        let outcome = await session.delete(row).value

        #expect(outcome == .deleted)
        #expect(session.expenses.isEmpty)
        #expect(outbox.writes.count == 1)
        // Bob paid 10 for both; deleting it takes back the 5 Alice owed.
        #expect(session.netBalanceCents == -500 + 500)
        #expect(session.displaySummary?.simplifiedDebts.isEmpty == true)
    }

    @Test func discardingAQueuedDeleteBringsTheRowBack() async {
        let store = LocalStore(url: nil)
        let server = FakeServer()
        let outbox = outbox(server, store: store)
        let row = TestExpense.make(id: 9, paidBy: 2, amount: 10, splitAmounts: [1: 5, 2: 5])
        let cache = GroupCache(store: store, userId: 1)
        cache.save(GroupSnapshot(group: group, expenses: [row], summary: nil, savedAt: Date()), groupId: 1)
        let session = GroupSession(groupId: 1, dataSource: unreachable(), cache: cache, outbox: outbox)
        server.deleteAnswers = [offline]
        _ = await session.delete(row).value

        outbox.discard(try! #require(outbox.writes.first).id)

        #expect(session.expenses.map(\.id) == [9])
        #expect(session.netBalanceCents == -500)
    }
}

// MARK: - Helpers

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(5)) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
