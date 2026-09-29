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

    @Test func refreshKeepsCachedPeopleVisibleUntilNewResponse() async {
        let loader = HeldPeopleRefresh()
        let viewModel = PeopleViewModel { await loader.load() }

        await viewModel.load()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.activePeers.map(\.name) == ["Cached"])

        let refresh = Task { await viewModel.load() }
        await loader.waitForRefresh()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.activePeers.map(\.name) == ["Cached"])

        await loader.releaseRefresh()
        await refresh.value
        #expect(viewModel.activePeers.map(\.name) == ["Updated"])
    }

    @Test func pendingPeoplePollsUntilTheWorkerSettles() async {
        let loader = PendingPeopleLoader()
        let retry = PeopleRetryGate()
        let viewModel = PeopleViewModel(
            loadPeople: { await loader.load() },
            waitForRetry: { _ in await retry.wait() }
        )

        await viewModel.load()
        #expect(viewModel.balancesPending)
        await retry.waitForStart()
        #expect(loader.callCount == 1)
        retry.release()
        for _ in 0..<100 where viewModel.balancesPending { await Task.yield() }
        #expect(!viewModel.balancesPending)
        #expect(loader.callCount == 2)
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

private actor HeldPeopleRefresh {
    private var calls = 0
    private var refreshStarted: CheckedContinuation<Void, Never>?
    private var refreshResponse: CheckedContinuation<PeopleResponse, Never>?

    func load() async -> PeopleResponse {
        calls += 1
        if calls == 1 { return response(name: "Cached") }
        refreshStarted?.resume()
        refreshStarted = nil
        return await withCheckedContinuation { refreshResponse = $0 }
    }

    func waitForRefresh() async {
        if calls > 1 { return }
        await withCheckedContinuation { refreshStarted = $0 }
    }

    func releaseRefresh() {
        refreshResponse?.resume(returning: response(name: "Updated"))
        refreshResponse = nil
    }

    private func response(name: String) -> PeopleResponse {
        PeopleResponse(peers: [
            Peer(userId: 1, name: name, avatarURL: nil, netAmountCents: 100, groups: [])
        ], balancesPending: false)
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "Could not load people" }
}

@MainActor
private final class PendingPeopleLoader {
    private(set) var callCount = 0

    func load() -> PeopleResponse {
        callCount += 1
        return PeopleResponse(peers: [], balancesPending: callCount == 1)
    }
}

@MainActor
private final class PeopleRetryGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var retryWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { retryWaiter = $0 }
    }

    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        retryWaiter?.resume()
        retryWaiter = nil
    }
}
