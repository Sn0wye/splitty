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

    init(loadPeople: @escaping () async throws -> PeopleResponse = GroupService.shared.getPeople) {
        self.loadPeople = loadPeople
    }

    func load() async {
        state = .loading
        do {
            apply(try await loadPeople())
        } catch where error.isCancellation {
            return
        } catch {
            state = .error(error.displayMessage)
        }
    }

    func apply(_ response: PeopleResponse) {
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
