import Combine
import Foundation
import Network

/// The network calls a write is sent through, behind closures so a test controls them.
struct OutboxTransport {
    var create: (NewExpenseRequest) async throws -> Expense
    var update: (ExpenseUpdateRequest) async throws -> Expense
    var deleteExpense: (_ groupId: Int, _ expenseId: Int) async throws -> Void
    var settle: (_ groupId: Int, _ draft: SettleDraft, _ clientId: UUID) async throws -> Expense
    var deleteSettlement: (_ groupId: Int, _ expenseId: Int) async throws -> Void

    static let live = OutboxTransport(
        create: { try await ExpenseService.shared.createExpense($0) },
        update: { try await ExpenseService.shared.updateExpense($0) },
        deleteExpense: { try await ExpenseService.shared.deleteExpense(groupId: $0, expenseId: $1) },
        settle: { groupId, draft, clientId in
            try await SettlementService.shared.settleUp(
                groupId: groupId,
                withUserId: draft.payeeId,
                amountCents: draft.amountCents,
                date: draft.date,
                clientId: clientId,
                currency: draft.currency
            )
        },
        deleteSettlement: { try await SettlementService.shared.deleteSettlement(groupId: $0, expenseId: $1) }
    )
}

/// What happened to a write, for the group session that shows it.
enum OutboxEvent {
    /// The server applied it. `row` is the stored row for a create, an edit or a settlement.
    case confirmed(PendingWrite, row: Expense?)
    /// It will never be sent: the member discarded it, or the server refused it on its first
    /// send and the screen that made it showed why.
    case dropped(PendingWrite)
}

extension OutboxEvent {
    var write: PendingWrite {
        switch self {
        case .confirmed(let write, _), .dropped(let write): write
        }
    }
}

/// How a write fared on the send the screen that made it waited for.
enum SubmitResult {
    /// The server applied it; the stored row when there is one.
    case confirmed(Expense?)
    /// It is kept and will be sent later, or it waits on the member.
    case queued
    /// The server refused it outright and it was dropped. Show the error where it was made.
    case refused(Error)
}

/// Writes made on this device that the server has not confirmed, sent one at a time in the
/// order they were made, kept on disk until they land (ADR 0008).
///
/// A write that fails on the network stays and is retried with backoff, and again whenever
/// the network comes back or the app returns to the foreground. A write the server refuses
/// in a way only the member can resolve keeps a `problem` and waits.
@MainActor
final class Outbox: ObservableObject {
    static let shared = Outbox(store: .shared, transport: .live, watchesNetwork: true)

    @Published private(set) var writes: [PendingWrite] = []
    @Published private(set) var isOnline = true
    /// The write on the wire, if any. It is not merged with later writes while it is out.
    @Published private(set) var sendingId: UUID?
    private(set) var userId: Int?

    let events = PassthroughSubject<OutboxEvent, Never>()

    private let store: LocalStore
    private let transport: OutboxTransport
    private let wait: (Duration) async throws -> Void
    private var monitor: NWPathMonitor?
    private var drainTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var waiters: [UUID: CheckedContinuation<SubmitResult, Never>] = [:]
    /// Writes whose first send a screen is waiting on: a refusal drops them and is shown
    /// there instead of being kept as a problem.
    private var submitted: Set<UUID> = []
    private var nextLocalId = -1_000_000

    static let retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60), .seconds(300)]

    init(
        store: LocalStore,
        transport: OutboxTransport,
        watchesNetwork: Bool = false,
        isOnline: Bool = true,
        wait: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.transport = transport
        self.wait = wait
        self.isOnline = isOnline
        if watchesNetwork { startMonitoring() }
    }

    // MARK: - Who

    /// Loads `userId`'s queue and starts sending it. Nil stops sending and forgets the
    /// queue in memory; what is on disk stays, so the same user signing back in continues.
    func setUser(_ userId: Int?) {
        guard self.userId != userId else { return }
        drainTask?.cancel()
        drainTask = nil
        retryTask?.cancel()
        retryTask = nil
        sendingId = nil
        self.userId = userId
        writes = userId.map(store.pendingWrites(user:)) ?? []
        nextLocalId = min(-1_000_000, (writes.map(\.row.id).min() ?? 0) - 1)
        drain()
    }

    /// Deletes everything kept for the signed-in user, queue included. For a sign-out the
    /// member chose or a deleted account; a forced sign-out keeps it.
    func purgeSignedInUser() {
        guard let userId else { return }
        store.removeAll(user: userId)
        setUser(nil)
    }

    var cache: GroupCache? { userId.map { GroupCache(store: store, userId: $0) } }

    // MARK: - Reading

    func writes(for groupId: Int) -> [PendingWrite] {
        writes.filter { $0.groupId == groupId }
    }

    /// The write that touches `expenseId`, newest first: a create shows its own negative id.
    func write(touching expenseId: Int) -> PendingWrite? {
        writes.last { $0.row.id == expenseId }
    }

    func isSending(_ write: PendingWrite) -> Bool { sendingId == write.id }

    /// A negative id for a row that exists only on this device. Far from the ids the session
    /// gives its own pending payments, so the two never meet.
    func makeLocalId() -> Int {
        defer { nextLocalId -= 1 }
        return nextLocalId
    }

    // MARK: - Writing

    /// Queues `write`, merged with a queued write to the same row where that is safe, and
    /// waits up to `timeout` for its first send. A refusal on that send drops the write and
    /// returns the error, so the screen that made it can say why, the same as online.
    func submit(_ write: PendingWrite, timeout: Duration = .seconds(8)) async -> SubmitResult {
        guard let queued = enqueue(write) else { return .queued }
        guard isOnline else { return .queued }
        submitted.insert(queued.id)
        let result = await withCheckedContinuation { continuation in
            waiters[queued.id] = continuation
            drain()
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resume(queued.id, with: .queued)
            }
        }
        submitted.remove(queued.id)
        return result
    }

    /// Queues `write` and persists the queue. Returns the write that will be sent, or nil
    /// when `write` folded into one already queued (an edit of a row not yet created, say).
    @discardableResult
    func enqueue(_ write: PendingWrite) -> PendingWrite? {
        let result = merge(write)
        persist()
        drain()
        return result
    }

    /// Drops a write the member chose not to keep. The write on the wire cannot be recalled.
    func discard(_ id: UUID) {
        guard sendingId != id, let index = writes.firstIndex(where: { $0.id == id }) else { return }
        let write = writes.remove(at: index)
        persist()
        events.send(.dropped(write))
        drain()
    }

    /// Drops every write of a group this member can no longer write to.
    func dropWrites(groupId: Int) {
        let dropped = writes.filter { $0.groupId == groupId && $0.id != sendingId }
        guard !dropped.isEmpty else { return }
        writes.removeAll { write in dropped.contains { $0.id == write.id } }
        persist()
        for write in dropped { events.send(.dropped(write)) }
    }

    /// Clears a write's problem with the change the member chose, and sends it again.
    func resolve(_ id: UUID, with change: (inout PendingWrite) -> Void) {
        guard let index = writes.firstIndex(where: { $0.id == id }) else { return }
        change(&writes[index])
        writes[index].problem = nil
        writes[index].attempts = 0
        persist()
        drain()
    }

    /// Sends what is waiting now rather than at the next retry.
    func resume() {
        retryTask?.cancel()
        retryTask = nil
        drain()
    }

    // MARK: - Merging

    private func merge(_ write: PendingWrite) -> PendingWrite? {
        let target = write.row.id
        let queued = writes.lastIndex { $0.row.id == target && $0.id != sendingId && $0.problem == nil }

        switch write.action {
        case .editExpense(let request, _, let row):
            guard let index = queued else { break }
            switch writes[index].action {
            case .createExpense(let create, _):
                // Not created yet: the create goes out with the edited values instead.
                writes[index].action = .createExpense(Self.applying(request, to: create), row: row)
                return nil
            case .editExpense(let earlier, let base, _):
                // One edit against the first base, carrying both edits' fields.
                writes[index].action = .editExpense(Self.combining(earlier, request), base: base, row: row)
                return nil
            default:
                break
            }
        case .deleteExpense, .deleteSettlement:
            guard let index = queued else { break }
            switch writes[index].action {
            case .createExpense, .settle:
                // Never reached the server, so there is nothing to delete there.
                let dropped = writes.remove(at: index)
                events.send(.dropped(dropped))
                return nil
            case .editExpense(_, let base, _):
                writes.remove(at: index)
                let delete = PendingWrite(
                    id: write.id,
                    groupId: write.groupId,
                    action: write.isSettlement ? .deleteSettlement(base: base) : .deleteExpense(base: base)
                )
                writes.append(delete)
                return delete
            default:
                break
            }
        default:
            break
        }
        writes.append(write)
        return write
    }

    private static func applying(_ edit: ExpenseUpdateRequest, to create: NewExpenseRequest) -> NewExpenseRequest {
        var merged = create
        merged = NewExpenseRequest(
            groupId: create.groupId,
            description: edit.description ?? create.description,
            amountCents: edit.amountCents ?? create.amountCents,
            paidBy: edit.paidBy ?? create.paidBy,
            date: edit.date ?? create.date,
            category: edit.category ?? create.category,
            splitMode: edit.splitMode ?? create.splitMode,
            splits: edit.splits ?? create.splits,
            repeats: create.repeats,
            clientId: create.clientId,
            currency: edit.currency ?? create.currency
        )
        return merged
    }

    private static func combining(_ earlier: ExpenseUpdateRequest, _ later: ExpenseUpdateRequest) -> ExpenseUpdateRequest {
        var combined = earlier
        if later.amountCents != nil || later.paidBy != nil || later.splitMode != nil || later.splits != nil {
            combined.amountCents = later.amountCents
            combined.paidBy = later.paidBy
            combined.splitMode = later.splitMode
            combined.splits = later.splits
        }
        if let description = later.description { combined.description = description }
        if let category = later.category { combined.category = category }
        if let date = later.date { combined.date = date }
        if let currency = later.currency { combined.currency = currency }
        return combined
    }

    // MARK: - Sending

    private func drain() {
        guard drainTask == nil, retryTask == nil, userId != nil else { return }
        drainTask = Task { [weak self] in
            await self?.sendAll()
            self?.drainTask = nil
        }
    }

    private func sendAll() async {
        while !Task.isCancelled, let next = nextReady() {
            sendingId = next.id
            let outcome = await send(next)
            sendingId = nil
            guard !Task.isCancelled else { return }

            switch outcome {
            case .confirmed(let row):
                writes.removeAll { $0.id == next.id }
                persist()
                events.send(.confirmed(next, row: row))
                resume(next.id, with: .confirmed(row))
            case .retry(let rebased):
                if let rebased, let index = writes.firstIndex(where: { $0.id == next.id }) {
                    writes[index] = rebased
                    persist()
                    continue
                }
                if let index = writes.firstIndex(where: { $0.id == next.id }) {
                    writes[index].attempts += 1
                    persist()
                    scheduleRetry(after: writes[index].attempts)
                }
                resume(next.id, with: .queued)
                return
            case .problem(let problem, let error):
                if submitted.contains(next.id), Self.dropsOnFirstSend(problem) {
                    writes.removeAll { $0.id == next.id }
                    persist()
                    events.send(.dropped(next))
                    resume(next.id, with: .refused(error))
                } else {
                    if let index = writes.firstIndex(where: { $0.id == next.id }) {
                        writes[index].problem = problem
                        persist()
                    }
                    resume(next.id, with: .queued)
                }
            }
        }
    }

    /// The first write in order with no problem whose row no earlier write with a problem
    /// touches, so a write the member must resolve holds back only what depends on it.
    private func nextReady() -> PendingWrite? {
        var blockedRows: Set<Int> = []
        for write in writes {
            if write.problem != nil {
                blockedRows.insert(write.row.id)
                continue
            }
            if blockedRows.contains(write.row.id) { continue }
            return write
        }
        return nil
    }

    private enum Outcome {
        case confirmed(Expense?)
        /// Try again later, or at once with `rebased` when an edit was merged onto a newer row.
        case retry(rebased: PendingWrite?)
        case problem(PendingWrite.Problem, Error)
    }

    private func send(_ write: PendingWrite) async -> Outcome {
        do {
            switch write.action {
            case .createExpense(let request, _):
                var request = request
                request.clientId = write.id
                return .confirmed(try await transport.create(request))
            case .editExpense(let request, _, _):
                var request = request
                request.opId = write.id
                return .confirmed(try await transport.update(request))
            case .deleteExpense(let base):
                try await transport.deleteExpense(write.groupId, base.id)
                return .confirmed(nil)
            case .settle(let draft, _):
                return .confirmed(try await transport.settle(write.groupId, draft, write.id))
            case .deleteSettlement(let base):
                try await transport.deleteSettlement(write.groupId, base.id)
                return .confirmed(nil)
            }
        } catch {
            return classify(error, for: write)
        }
    }

    private func classify(_ error: Error, for write: PendingWrite) -> Outcome {
        if error.isCancellation { return .retry(rebased: nil) }
        guard let apiError = error as? APIError else { return .retry(rebased: nil) }

        switch apiError {
        case .networkError, .missingBaseURL, .invalidBaseURL, .invalidResponse, .noAuthToken:
            return .retry(rebased: nil)
        case .decodingError:
            // The server answered 2xx: the write landed, and the next read brings the row.
            // Retrying would resend into the same answer forever.
            return .confirmed(nil)
        case .httpError(let status, _) where status >= 500 || status == 408 || status == 429 || status == 401:
            return .retry(rebased: nil)
        case .refused(_, .balancesPending, _):
            return .retry(rebased: nil)
        case .httpError(404, _):
            // A delete of a row that is gone already holds. An edit of one lost to a delete.
            if write.isDelete { return .confirmed(nil) }
            if case .editExpense = write.action { return .problem(.deletedElsewhere, error) }
            return .problem(.refused(message: apiError.displayMessage), error)
        case .versionConflict(let theirs, _):
            guard case .editExpense(let request, let base, let row) = write.action else {
                return .problem(.refused(message: apiError.displayMessage), error)
            }
            if let rebased = EditMerge.rebase(request, base: base, theirs: theirs) {
                var merged = write
                merged.action = .editExpense(rebased, base: theirs, row: row)
                return .retry(rebased: merged)
            }
            return .problem(.conflict(theirs: theirs), error)
        case .settlementExceedsCap(let cap, _):
            return .problem(.overCap(capCents: cap), error)
        case .refused(_, .currencyChanged, _):
            return .problem(.currencyChanged, error)
        default:
            return .problem(.refused(message: apiError.displayMessage), error)
        }
    }

    /// Refusals the screen that made the write can show as it always has. A conflict or a
    /// row deleted elsewhere is kept instead: the member resolves it from the queue.
    private static func dropsOnFirstSend(_ problem: PendingWrite.Problem) -> Bool {
        switch problem {
        case .refused, .overCap, .currencyChanged: true
        case .conflict, .deletedElsewhere: false
        }
    }

    private func scheduleRetry(after attempts: Int) {
        retryTask?.cancel()
        let delay = Self.retryDelays[min(max(attempts - 1, 0), Self.retryDelays.count - 1)]
        retryTask = Task { [weak self] in
            do { try await self?.wait(delay) } catch { return }
            self?.retryTask = nil
            self?.drain()
        }
    }

    private func resume(_ id: UUID, with result: SubmitResult) {
        waiters.removeValue(forKey: id)?.resume(returning: result)
    }

    private func persist() {
        guard let userId else { return }
        store.savePendingWrites(writes, user: userId)
    }

    // MARK: - Network

    private func startMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                // A path that says it is up is a reason to try, not a promise: a captive
                // portal looks the same. A failed send just schedules the next retry.
                if online { self.resume() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.splitty.outbox.path"))
        self.monitor = monitor
    }
}

/// One user's saved groups.
struct GroupCache {
    let store: LocalStore
    let userId: Int

    func snapshot(groupId: Int) -> GroupSnapshot? {
        store.value(GroupSnapshot.self, user: userId, key: GroupSnapshot.key(groupId: groupId))
    }

    func save(_ snapshot: GroupSnapshot, groupId: Int) {
        store.set(snapshot, user: userId, key: GroupSnapshot.key(groupId: groupId))
    }

    func remove(groupId: Int) {
        store.removeValue(user: userId, key: GroupSnapshot.key(groupId: groupId))
    }

    var groups: GroupsSnapshot? {
        store.value(GroupsSnapshot.self, user: userId, key: GroupsSnapshot.key)
    }

    func save(groups: [Group]) {
        store.set(GroupsSnapshot(groups: groups, savedAt: Date()), user: userId, key: GroupsSnapshot.key)
    }
}
