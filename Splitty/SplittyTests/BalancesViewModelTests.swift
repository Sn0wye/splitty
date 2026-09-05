//
//  BalancesViewModelTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

@MainActor
struct BalancesViewModelTests {
    @Test func zeroRowsAreHiddenAndAnAllZeroSummaryIsSettled() {
        let viewModel = makeViewModel(initialNetCents: 1_200)
        viewModel.apply(summary([balance(peerId: 2, name: "Ana", cents: 0)]), currentUserId: 1)

        #expect(viewModel.state == .settled)
        #expect(viewModel.netCents == 0)
    }

    @Test func aSummaryWithNoRowsIsSettled() {
        let viewModel = makeViewModel()
        viewModel.apply(summary([]), currentUserId: 1)
        #expect(viewModel.state == .settled)
    }

    @Test func debtsComeBeforeCreditsAndLargestAmountsComeFirst() {
        let viewModel = makeViewModel()
        viewModel.apply(summary([
            balance(peerId: 2, name: "Small credit", cents: 300),
            balance(peerId: 3, name: "Small debt", cents: -200),
            balance(peerId: 4, name: "Large credit", cents: 900),
            balance(peerId: 5, name: "Large debt", cents: -800)
        ]), currentUserId: 1)

        #expect(viewModel.rows.map(\.peerName) == ["Large debt", "Small debt", "Large credit", "Small credit"])
    }

    @Test func directionIsWrittenInWords() {
        let viewModel = makeViewModel()
        viewModel.apply(summary([
            balance(peerId: 2, name: "Ana", cents: -4_000),
            balance(peerId: 3, name: "Bob", cents: 1_200)
        ]), currentUserId: 1)

        #expect(viewModel.rows.map(\.statement) == ["You owe Ana $40.00", "Bob owes you $12.00"])
    }

    @Test func summaryNetReplacesTheAlreadyLoadedGroupNet() {
        let viewModel = makeViewModel(initialNetCents: 9_999)
        #expect(viewModel.netCents == 9_999)

        viewModel.apply(summary([
            balance(peerId: 2, name: "Hidden", cents: 0),
            balance(peerId: 3, name: "Ana", cents: -4_000),
            balance(peerId: 4, name: "Bob", cents: 1_200)
        ]), currentUserId: 1)

        #expect(viewModel.netCents == -2_800)
    }

    @Test func aFailureIsDistinctFromSettled() {
        let viewModel = makeViewModel()
        viewModel.fail(with: TestFailure())

        #expect(viewModel.state == .error("Could not load balances"))
    }

    @Test func pendingDoesNotChangeWhichRowsAppear() {
        let viewModel = makeViewModel()
        viewModel.apply(
            summary([balance(peerId: 2, name: "Ana", cents: -4_000)], pending: true),
            currentUserId: 1
        )

        #expect(viewModel.balancesPending)
        #expect(viewModel.rows.map(\.peerName) == ["Ana"])
    }

    @Test func onlyTheCurrentUsersRowsContribute() {
        let viewModel = makeViewModel()
        viewModel.apply(summary([
            balance(userId: 9, peerId: 2, name: "Other side", cents: 4_000),
            balance(peerId: 3, name: "Ana", cents: -1_000)
        ]), currentUserId: 1)

        #expect(viewModel.rows.map(\.peerName) == ["Ana"])
        #expect(viewModel.netCents == -1_000)
    }

    private func makeViewModel(initialNetCents: Int = 0) -> BalancesViewModel {
        BalancesViewModel(
            context: BalanceSheetContext(groupId: 7, initialNetCents: initialNetCents, balancesPending: false)
        )
    }

    private func summary(_ balances: [Balance], pending: Bool = false) -> GroupBalanceSummary {
        GroupBalanceSummary(balances: balances, balancesPending: pending)
    }

    private func balance(userId: Int = 1, peerId: Int, name: String, cents: Int) -> Balance {
        Balance(
            userId: userId,
            peerId: peerId,
            amountCents: cents,
            user: user(id: userId, name: "You"),
            peer: user(id: peerId, name: name)
        )
    }

    private func user(id: Int, name: String) -> User {
        User(id: id, name: name, email: "\(id)@example.com", createdAt: "2026-01-01", updatedAt: "2026-01-01")
    }
}

struct BalanceDecodingTests {
    @Test func decodesSummaryMoneyAndInlinedPeerAtTheBoundary() throws {
        let payload = #"{"balances":[{"userId":1,"peerId":2,"amount":-40.25,"user":{"id":1,"name":"You","email":"you@example.com","createdAt":"2026-01-01","updatedAt":"2026-01-01"},"peer":{"id":2,"name":"Ana","email":"ana@example.com","avatarUrl":"https://example.com/ana.png","createdAt":"2026-01-01","updatedAt":"2026-01-01"}}],"balancesPending":true}"#

        let decoded = try JSONDecoder().decode(GroupBalanceSummary.self, from: Data(payload.utf8))
        let row = try #require(decoded.balances.first)

        #expect(row.peerId == 2)
        #expect(row.peer.name == "Ana")
        #expect(row.peer.avatarURL == URL(string: "https://example.com/ana.png"))
        #expect(row.amountCents == -4_025)
        #expect(decoded.balancesPending)
    }

    @Test func decodesGroupNetBalanceToCentsAtTheBoundary() throws {
        let payload = #"{"id":7,"name":"Trip","description":null,"netBalance":12.34,"createdAt":"2026-01-01","members":[]}"#
        let group = try JSONDecoder().decode(Group.self, from: Data(payload.utf8))
        #expect(group.netBalanceCents == 1_234)
    }
}

@MainActor
struct GroupsOverallBalanceTests {
    @Test func sumsLoadedGroupNets() {
        let viewModel = GroupsViewModel()
        viewModel.groups = [group(id: 1, cents: 1_234), group(id: 2, cents: -234)]
        #expect(viewModel.overallBalanceCents == 1_000)
    }

    @Test func hasNoOverallFigureWithoutGroups() {
        #expect(GroupsViewModel().overallBalanceCents == nil)
    }

    private func group(id: Int, cents: Int) -> Group {
        Group(id: id, name: "Group \(id)", description: nil, netBalanceCents: cents, createdAt: "2026-01-01", members: [])
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "Could not load balances" }
}
