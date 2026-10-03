import Combine
import Foundation

struct GroupLiveBalance: Equatable {
    let netBalanceCents: Int
    let balancesPending: Bool
}

@MainActor
final class GroupSessionStore: ObservableObject {
    @Published private(set) var current: GroupSession?
    @Published private(set) var signedInUserId: Int?
    var currentGroupId: Int? { current?.groupId }
    private let defaults: UserDefaults
    private var observations: [Int: AnyCancellable] = [:]
    private let dataSource: () -> GroupDataSource
    private var sessions: [Int: GroupSession] = [:]
    private var recentGroupIds: [Int] = []
    private let cacheLimit = 8

    init(defaults: UserDefaults = .standard, dataSource: @escaping () -> GroupDataSource = { .live }) {
        self.defaults = defaults
        self.dataSource = dataSource
    }

    private static func currentGroupKey(userId: Int) -> String { "currentGroupId.\(userId)" }

    func setSignedInUser(_ userId: Int?) {
        guard signedInUserId != userId else { return }
        discard()
        signedInUserId = userId
        if let userId,
           let groupId = defaults.object(forKey: Self.currentGroupKey(userId: userId)) as? Int {
            open(groupId).appear()
        }
    }

    func session(for groupId: Int) -> GroupSession? { sessions[groupId] }

    func liveBalance(for groupId: Int) -> GroupLiveBalance? {
        guard let session = sessions[groupId], let cents = session.netBalanceCents else { return nil }
        return GroupLiveBalance(netBalanceCents: cents, balancesPending: session.balancesPending)
    }

    private func persistCurrentGroup() {
        guard let signedInUserId else { return }
        let key = Self.currentGroupKey(userId: signedInUserId)
        if let currentGroupId { defaults.set(currentGroupId, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    @discardableResult
    func open(_ groupId: Int, seed: Group? = nil) -> GroupSession {
        if let session = sessions[groupId] {
            recentGroupIds.removeAll { $0 == groupId }
            recentGroupIds.append(groupId)
            current = session
            persistCurrentGroup()
            return session
        }
        let session = GroupSession(groupId: groupId, seed: seed, dataSource: dataSource())
        sessions[groupId] = session
        observations[groupId] = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        recentGroupIds.append(groupId)
        current = session
        persistCurrentGroup()
        if recentGroupIds.count > cacheLimit {
            let oldest = recentGroupIds.removeFirst()
            observations.removeValue(forKey: oldest)
            sessions.removeValue(forKey: oldest)?.discard()
        }
        return session
    }

    func remove(_ groupId: Int) {
        observations.removeValue(forKey: groupId)
        sessions.removeValue(forKey: groupId)?.discard()
        recentGroupIds.removeAll { $0 == groupId }
        if current?.groupId == groupId {
            current = nil
            persistCurrentGroup()
        }
    }

    func discard() {
        for session in sessions.values { session.discard() }
        observations.removeAll()
        sessions.removeAll()
        recentGroupIds.removeAll()
        current = nil
    }

    func report(_ write: GroupMoneyWrite, groupId: Int) {
        sessions[groupId]?.report(write)
    }

    /// Detail screens only open inside a live session, so a missing one is an eviction
    /// race rather than a row the server has already lost.
    func delete(_ row: Expense, groupId: Int) -> Task<GroupDeleteOutcome, Never> {
        sessions[groupId]?.delete(row) ?? Task { .failed(L10n.Errors.generic) }
    }
}
