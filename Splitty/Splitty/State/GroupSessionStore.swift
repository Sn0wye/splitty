import Foundation

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
}

@MainActor
final class GroupSessionStore: ObservableObject {
    @Published private(set) var current: GroupSession?
    private let dataSource: () -> GroupDataSource

    init(dataSource: @escaping () -> GroupDataSource = { .live }) {
        self.dataSource = dataSource
    }

    @discardableResult
    func open(_ groupId: Int, seed: Group? = nil) -> GroupSession {
        if let current, current.groupId == groupId { return current }
        discard()
        let session = GroupSession(groupId: groupId, seed: seed, dataSource: dataSource())
        current = session
        return session
    }

    func discard() {
        current?.discard()
        current = nil
    }
}
