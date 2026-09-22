//
//  BalancesViewModelTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

@MainActor
struct BalancesViewModelTests {
    @Test func aSummaryWithNoRowsIsSettled() {
        let viewModel = makeViewModel()
        viewModel.apply(summary([]), currentUserId: 1)
        #expect(viewModel.state == .settled)
    }

    @Test func aChainRendersTheServersSingleSimplifiedDebt() {
        let viewModel = makeViewModel()
        viewModel.apply(summary([
            debt(fromId: 2, fromName: "John", toId: 4, toName: "Adam", cents: 1_000)
        ]), currentUserId: 1)

        #expect(viewModel.rows.count == 1)
        #expect(viewModel.rows.first?.statement == "John owes Adam $10.00")
    }

    @Test func currentUserRowsComeFirstAndStateTheirDirection() {
        let viewModel = makeViewModel()
        viewModel.apply(summary([
            debt(fromId: 2, fromName: "Ana", toId: 3, toName: "Bob", cents: 7_000),
            debt(fromId: 1, fromName: "You", toId: 4, toName: "Cara", cents: 4_000),
            debt(fromId: 5, fromName: "Dan", toId: 1, toName: "You", cents: 1_200)
        ]), currentUserId: 1)

        #expect(viewModel.rows.map(\.involvement) == [.youPay, .paysYou, .uninvolved])
        #expect(viewModel.rows.map(\.statement) == [
            "You owe Cara $40.00",
            "Dan owes you $12.00",
            "Ana owes Bob $70.00"
        ])
    }

    @Test func simplifiedDebtsReplaceTheAlreadyLoadedGroupNet() {
        let viewModel = makeViewModel(initialNetCents: 9_999)
        #expect(viewModel.netCents == 9_999)

        viewModel.apply(summary([
            debt(fromId: 1, fromName: "You", toId: 3, toName: "Ana", cents: 4_000),
            debt(fromId: 4, fromName: "Bob", toId: 1, toName: "You", cents: 1_200),
            debt(fromId: 4, fromName: "Bob", toId: 3, toName: "Ana", cents: 900)
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
            summary([debt(fromId: 1, fromName: "You", toId: 2, toName: "Ana", cents: 4_000)], pending: true),
            currentUserId: 1
        )

        #expect(viewModel.balancesPending)
        #expect(viewModel.rows.map(\.to.name) == ["Ana"])
    }

    @Test func aPendingSummaryRefreshesUntilTheWorkerSettles() async {
        let pending = summary([debt(fromId: 1, fromName: "You", toId: 2, toName: "Ana", cents: 4_000)], pending: true)
        let settled = summary([debt(fromId: 1, fromName: "You", toId: 2, toName: "Ana", cents: 1_500)])
        let data = ControlledBalanceData(summaries: Array(repeating: pending, count: 9) + [settled])
        let viewModel = BalancesViewModel(
            context: BalanceSheetContext(groupId: 7, initialNetCents: 0, balancesPending: false),
            dataSource: data.source()
        )

        await viewModel.load(currentUserId: 1)

        #expect(data.summaryCallCount == 10)
        #expect(data.retryCount == 9)
        #expect(viewModel.netCents == -1_500)
        #expect(!viewModel.balancesPending)
    }

    private func makeViewModel(initialNetCents: Int = 0) -> BalancesViewModel {
        BalancesViewModel(
            context: BalanceSheetContext(groupId: 7, initialNetCents: initialNetCents, balancesPending: false)
        )
    }

    private func summary(_ debts: [SimplifiedDebt], pending: Bool = false) -> GroupBalanceSummary {
        GroupBalanceSummary(simplifiedDebts: debts, balancesPending: pending)
    }

    private func debt(
        fromId: Int,
        fromName: String,
        toId: Int,
        toName: String,
        cents: Int
    ) -> SimplifiedDebt {
        SimplifiedDebt(
            from: DebtMember(id: fromId, name: fromName, avatarUrl: ""),
            to: DebtMember(id: toId, name: toName, avatarUrl: ""),
            amountCents: cents,
        )
    }
}

@MainActor
private final class ControlledBalanceData {
    private let summaries: [GroupBalanceSummary]
    private(set) var summaryCallCount = 0
    private(set) var retryCount = 0

    init(summaries: [GroupBalanceSummary]) {
        self.summaries = summaries
    }

    func source() -> BalanceDataSource {
        BalanceDataSource(
            summary: { [self] _ in await nextSummary() },
            requestRefresh: { _ in },
            waitForRetry: { [self] _ in await noteRetry() }
        )
    }

    private func nextSummary() -> GroupBalanceSummary {
        let index = min(summaryCallCount, summaries.count - 1)
        summaryCallCount += 1
        return summaries[index]
    }

    private func noteRetry() {
        retryCount += 1
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
