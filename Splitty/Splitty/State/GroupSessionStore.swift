import Foundation

enum GroupMoneyWrite {
    case expenseCreated(Expense)
    case expenseEdited(Expense)
    case paymentRecorded(payee: GroupMember, amountCents: Int, date: Date, currentUserId: Int)
    case paymentEdited(id: Int, amountCents: Int, date: Date)
}

/// One group's snapshot and its work, independent of the Group tab's view lifetime.
@MainActor
final class GroupSession {
    let groupId: Int
    let snapshot: GroupViewModel
    private var initialLoad: Task<Void, Never>?
    private var finishedInitialLoad = false

    init(groupId: Int, seed: Group?, dataSource: GroupDataSource) {
        self.groupId = groupId
        snapshot = GroupViewModel(dataSource: dataSource)
        if let seed { snapshot.seed(seed) }
    }

    @discardableResult
    func appear() -> Task<Void, Never> {
        if !finishedInitialLoad {
            if let initialLoad {
                if !snapshot.hasCompletedInitialRead { return initialLoad }
                initialLoad.cancel()
                finishedInitialLoad = true
                return snapshot.beginRefresh(groupId: groupId)
            }
            let task = Task { [weak self] in
                guard let self else { return }
                await snapshot.loadGroupData(groupId: groupId)
                finishedInitialLoad = true
            }
            initialLoad = task
            return task
        }
        return snapshot.beginRefresh(groupId: groupId)
    }

    func discard() {
        initialLoad?.cancel()
        snapshot.cancelRefresh()
    }

    @discardableResult
    func report(_ write: GroupMoneyWrite) -> Task<Void, Never> {
        snapshot.report(write, groupId: groupId)
    }

    @discardableResult
    func delete(_ row: Expense) -> Task<Bool, Never> {
        snapshot.delete(row, groupId: groupId)
    }
}

@MainActor
final class GroupSessionStore: ObservableObject {
    @Published private(set) var current: GroupSession?
    private let dataSource: () -> GroupDataSource
    private var sessions: [Int: GroupSession] = [:]
    private var recentGroupIds: [Int] = []
    private let cacheLimit = 8

    init(dataSource: @escaping () -> GroupDataSource = { .live }) {
        self.dataSource = dataSource
    }

    @discardableResult
    func open(_ groupId: Int, seed: Group? = nil) -> GroupSession {
        if let session = sessions[groupId] {
            recentGroupIds.removeAll { $0 == groupId }
            recentGroupIds.append(groupId)
            current = session
            return session
        }
        let session = GroupSession(groupId: groupId, seed: seed, dataSource: dataSource())
        sessions[groupId] = session
        recentGroupIds.append(groupId)
        current = session
        if recentGroupIds.count > cacheLimit {
            let oldest = recentGroupIds.removeFirst()
            sessions.removeValue(forKey: oldest)?.discard()
        }
        return session
    }

    func remove(_ groupId: Int) {
        sessions.removeValue(forKey: groupId)?.discard()
        recentGroupIds.removeAll { $0 == groupId }
        if current?.groupId == groupId { current = nil }
    }

    func discard() {
        for session in sessions.values { session.discard() }
        sessions.removeAll()
        recentGroupIds.removeAll()
        current = nil
    }

    func report(_ write: GroupMoneyWrite, groupId: Int) {
        guard let current, current.groupId == groupId else { return }
        current.report(write)
    }

    func delete(_ row: Expense, groupId: Int) -> Task<Bool, Never>? {
        guard let current, current.groupId == groupId else { return nil }
        return current.delete(row)
    }
}
