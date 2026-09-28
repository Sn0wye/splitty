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
    private var hasCachedResponse = false
    private var loadGeneration = 0

    init(loadPeople: @escaping () async throws -> PeopleResponse = GroupService.shared.getPeople) {
        self.loadPeople = loadPeople
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        if !hasCachedResponse { state = .loading }
        do {
            let response = try await loadPeople()
            guard !Task.isCancelled, generation == loadGeneration else { return }
            apply(response)
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
