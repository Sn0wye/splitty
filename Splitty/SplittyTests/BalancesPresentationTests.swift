//
//  BalancesViewModelTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

@MainActor
struct BalancesPresentationTests {
    @Test func aSummaryWithNoRowsIsSettled() async {
        let session = await makeSession(summary([]))
        #expect(session.balanceState(currentUserId: 1) == .settled)
    }

    @Test func aChainRendersTheServersSingleSimplifiedDebt() async {
        let session = await makeSession(summary([
            debt(fromId: 2, fromName: "John", toId: 4, toName: "Adam", cents: 1_000)
        ]))
        let rows = session.balanceState(currentUserId: 1).rows
        #expect(rows.count == 1)
        #expect(rows.first?.from.name == "John")
        #expect(rows.first?.to.name == "Adam")
        #expect(rows.first?.amountCents == 1_000)
    }

    @Test func currentUserRowsComeFirstAndStateTheirDirection() async {
        let session = await makeSession(summary([
            debt(fromId: 2, fromName: "Ana", toId: 3, toName: "Bob", cents: 7_000),
            debt(fromId: 1, fromName: "You", toId: 4, toName: "Cara", cents: 4_000),
            debt(fromId: 5, fromName: "Dan", toId: 1, toName: "You", cents: 1_200)
        ]))
        let rows = session.balanceState(currentUserId: 1).rows
        #expect(rows.map(\.involvement) == [.youPay, .paysYou, .uninvolved])
        #expect(rows.map(\.amountCents) == [4_000, 1_200, 7_000])
        #expect(rows.map(\.to.name) == ["Cara", "You", "Bob"])
    }

    @Test func aFailureIsDistinctFromSettled() async {
        let data = ControlledGroupData()
        var source = data.source()
        source.summary = { _ in throw TestFailure() }
        let session = GroupSession(groupId: 7, dataSource: source)
        _ = try? await session.readSummary()
        #expect(session.balanceState(currentUserId: 1) == .error("Could not load balances"))
    }

    @Test func pendingDoesNotChangeWhichRowsAppear() async {
        let session = await makeSession(summary([
            debt(fromId: 1, fromName: "You", toId: 2, toName: "Ana", cents: 4_000)
        ], pending: true))
        #expect(session.balanceState(currentUserId: 1).rows.map(\.to.name) == ["Ana"])
        #expect(session.balancesPending)
        session.discard()
    }

    private func makeSession(_ summary: GroupBalanceSummary) async -> GroupSession {
        let data = ControlledGroupData()
        data.cancelBalanceRetry = true
        data.summaryForCall = { _ in summary }
        let session = GroupSession(groupId: 7, dataSource: data.source())
        _ = try? await session.readSummary()
        return session
    }

    private func summary(_ debts: [SimplifiedDebt], pending: Bool = false) -> GroupBalanceSummary {
        GroupBalanceSummary(simplifiedDebts: debts, balancesPending: pending)
    }

    private func debt(fromId: Int, fromName: String, toId: Int, toName: String, cents: Int) -> SimplifiedDebt {
        SimplifiedDebt(from: DebtMember(id: fromId, name: fromName, avatarUrl: ""),
                       to: DebtMember(id: toId, name: toName, avatarUrl: ""), amountCents: cents)
    }
}

struct BalanceDecodingTests {
    @Test func decodesSimplifiedDebtsAtTheBoundary() throws {
        let payload = #"{"simplifiedDebts":[{"from":{"id":1,"name":"You","avatarUrl":"https://example.com/you.png"},"to":{"id":2,"name":"Ana","avatarUrl":"https://example.com/ana.png"},"amount":40.25}],"balancesPending":true}"#

        let decoded = try JSONDecoder().decode(GroupBalanceSummary.self, from: Data(payload.utf8))
        let row = try #require(decoded.simplifiedDebts.first)

        #expect(row.from.id == 1)
        #expect(row.to.name == "Ana")
        #expect(row.to.avatarURL == URL(string: "https://example.com/ana.png"))
        #expect(row.amountCents == 4_025)
        #expect(decoded.balancesPending)
    }

    @Test func anEmptyAvatarURLDoesNotRejectTheSummary() throws {
        let payload = #"{"simplifiedDebts":[{"from":{"id":1,"name":"You","avatarUrl":""},"to":{"id":2,"name":"Ana","avatarUrl":""},"amount":12.00}],"balancesPending":false}"#

        let decoded = try JSONDecoder().decode(GroupBalanceSummary.self, from: Data(payload.utf8))
        let row = try #require(decoded.simplifiedDebts.first)
        #expect(row.from.avatarURL == nil)
        #expect(row.to.avatarURL == nil)
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
