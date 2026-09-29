import Foundation

enum PeopleDisplayState: Equatable {
    case loading
    case loaded
    case empty
    case error(String)
}

@MainActor
final class PeopleViewModel: ObservableObject {
    @Published private(set) var state: PeopleDisplayState = .loading
    @Published private(set) var activePeers: [Peer] = []
    @Published private(set) var settledPeers: [Peer] = []
    @Published private(set) var balancesPending = false

    private let loadPeople: () async throws -> PeopleResponse
    private let waitForRetry: (Duration) async throws -> Void
    private var pollTask: Task<Void, Never>?
    private var hasCachedResponse = false
    private var loadGeneration = 0

    init(
        loadPeople: @escaping () async throws -> PeopleResponse = GroupService.shared.getPeople,
        waitForRetry: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.loadPeople = loadPeople
        self.waitForRetry = waitForRetry
    }

    func load() async {
        pollTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        if !hasCachedResponse { state = .loading }
        do {
            let response = try await loadPeople()
            guard !Task.isCancelled, generation == loadGeneration else { return }
            apply(response)
            if response.balancesPending {
                let fetch = loadPeople
                let wait = waitForRetry
                pollTask = Task { [weak self] in
                    await BalanceRefreshPolicy.poll(
                        fetch: fetch,
                        wait: wait,
                        isPending: { $0.balancesPending }
                    ) { [weak self] response in
                        guard let self, generation == loadGeneration else { return false }
                        apply(response)
                        return true
                    }
                }
            }
        } catch where error.isCancellation {
            return
        } catch {
            guard generation == loadGeneration else { return }
            if !hasCachedResponse { state = .error(error.displayMessage) }
        }
    }

    func apply(_ response: PeopleResponse) {
        hasCachedResponse = true
        balancesPending = response.balancesPending
        activePeers = response.peers
            .filter { $0.netAmountCents != 0 }
            .sorted(by: activePeerOrder)
        settledPeers = response.peers
            .filter { $0.netAmountCents == 0 }
            .sorted(by: peerNameOrder)
        state = response.peers.isEmpty ? .empty : .loaded
    }

    private func activePeerOrder(_ lhs: Peer, _ rhs: Peer) -> Bool {
        if lhs.magnitudeCents != rhs.magnitudeCents {
            return lhs.magnitudeCents > rhs.magnitudeCents
        }
        return peerNameOrder(lhs, rhs)
    }

    private func peerNameOrder(_ lhs: Peer, _ rhs: Peer) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
