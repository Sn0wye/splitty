import Foundation
import Testing
@testable import Splitty

@MainActor
struct PeopleViewModelTests {
    @Test func activePeersAreSortedByMagnitudeAndSettledPeersByName() {
        let viewModel = PeopleViewModel(loadPeople: { .empty })

        viewModel.apply(PeopleResponse(peers: [
            peer(id: 1, name: "Zoe", cents: 0),
            peer(id: 2, name: "Small credit", cents: 300),
            peer(id: 3, name: "Large debt", cents: -900),
            peer(id: 4, name: "Ana", cents: 0),
            peer(id: 5, name: "Large credit", cents: 900)
        ], balancesPending: false))

        #expect(viewModel.activePeers.map(\.name) == ["Large credit", "Large debt", "Small credit"])
        #expect(viewModel.settledPeers.map(\.name) == ["Ana", "Zoe"])
    }

    @Test func pendingFlagDoesNotChangeTheSections() {
        let viewModel = PeopleViewModel(loadPeople: { .empty })

        viewModel.apply(PeopleResponse(
            peers: [peer(id: 1, name: "Ana", cents: -250)],
            balancesPending: true
        ))

        #expect(viewModel.balancesPending)
        #expect(viewModel.activePeers.map(\.name) == ["Ana"])
        #expect(viewModel.settledPeers.isEmpty)
    }

    @Test func anEmptyResponseHasAnEmptyState() {
        let viewModel = PeopleViewModel(loadPeople: { .empty })

        viewModel.apply(.empty)

        #expect(viewModel.state == .empty)
    }

    @Test func retryReplacesAnErrorWithLoadedPeople() async {
        let loader = SequencedPeopleLoader(results: [
            .failure(TestFailure()),
            .success(PeopleResponse(
                peers: [peer(id: 1, name: "Ana", cents: 500)],
                balancesPending: false
            ))
        ])
        let viewModel = PeopleViewModel { try await loader.load() }

        await viewModel.load()
        #expect(viewModel.state == .error("Could not load people"))

        await viewModel.load()
        #expect(viewModel.activePeers.map(\.name) == ["Ana"])
    }

    @Test func decodesMoneyAndBreakdownAtTheBoundary() throws {
        let payload = #"{"peers":[{"userId":2,"name":"Ana","avatarUrl":"https://example.com/ana.png","netAmount":-12.34,"groups":[{"groupId":7,"groupName":"Home","amount":-10.00},{"groupId":8,"groupName":"Trip","amount":-2.34}]}],"balancesPending":true}"#

        let response = try JSONDecoder().decode(PeopleResponse.self, from: Data(payload.utf8))
        let ana = try #require(response.peers.first)

        #expect(ana.netAmountCents == -1_234)
        #expect(ana.groups.map(\.amountCents) == [-1_000, -234])
        #expect(ana.avatarURL == URL(string: "https://example.com/ana.png"))
        #expect(response.balancesPending)
    }

    private func peer(id: Int, name: String, cents: Int) -> Peer {
        Peer(userId: id, name: name, avatarURL: nil, netAmountCents: cents, groups: [])
    }
}

private actor SequencedPeopleLoader {
    private var results: [Result<PeopleResponse, Error>]

    init(results: [Result<PeopleResponse, Error>]) {
        self.results = results
    }

    func load() throws -> PeopleResponse {
        try results.removeFirst().get()
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "Could not load people" }
}
