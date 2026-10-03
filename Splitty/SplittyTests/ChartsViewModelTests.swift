//
//  ChartsViewModelTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

@MainActor
struct ChartsViewModelTests {

    @Test func opensOnAllTimeAndAsksForItOnce() async {
        let data = ControlledStatsData(answer: stats())
        let viewModel = makeViewModel(data)

        await viewModel.load()

        #expect(viewModel.range == .allTime)
        #expect(data.queries == [StatsQuery(from: nil, to: nil, timeZone: "America/Sao_Paulo")])
        #expect(viewModel.state == .loaded)
    }

    // Food and drink is groceries plus dining out; nothing is summed on the server.
    @Test func headingTotalsRollUpFromTheirCategories() async {
        let data = ControlledStatsData(answer: stats(group: spend([
            category(.groceries, cents: 6_000),
            category(.taxi, cents: 5_000),
            category(.diningOut, cents: 3_000),
            category(.rent, cents: 1_000)
        ])))
        let viewModel = makeViewModel(data)

        await viewModel.load()

        #expect(viewModel.slices.map(\.heading) == [.foodAndDrink, .transportation, .home])
        #expect(viewModel.slices.map(\.cents) == [9_000, 5_000, 1_000])
        #expect(viewModel.slices.map(\.fraction) == [0.6, 1.0 / 3, 1.0 / 15])
        #expect(viewModel.totalCents == 15_000)
    }

    // Both halves came back in the first answer, so the toggle is instant.
    @Test func switchingToMineSendsNoRequest() async {
        let data = ControlledStatsData(answer: stats(
            group: spend([category(.groceries, cents: 9_000)]),
            mine: spend([category(.groceries, cents: 3_000)])
        ))
        let viewModel = makeViewModel(data)
        await viewModel.load()

        viewModel.select(.mine)

        #expect(data.queries.count == 1)
        #expect(viewModel.lens == .mine)
        #expect(viewModel.totalCents == 3_000)
    }

    @Test func changingTheRangeAsksOnceForItsLocalDatesInTheDeviceZone() async {
        let data = ControlledStatsData(answer: stats())
        let viewModel = makeViewModel(data)
        await viewModel.load()

        await viewModel.select(.month).value

        #expect(data.queries.dropFirst() == [
            StatsQuery(from: "2026-03-01", to: "2026-04-01", timeZone: "America/Sao_Paulo")
        ])
        #expect(viewModel.range == .month)
    }

    // The picker moves at once, and the old numbers stay put rather than blanking the
    // screen while the new range loads.
    @Test func changingTheRangeKeepsTheNumbersOnScreenUntilTheNewOnesArrive() async {
        let data = ControlledStatsData(answer: stats(group: spend([category(.groceries, cents: 9_000)])))
        let viewModel = makeViewModel(data)
        await viewModel.load()
        data.holdsRequests = true

        let month = viewModel.select(.month)

        #expect(viewModel.range == .month)
        await data.waitForCall(2)
        #expect(viewModel.state == .loaded)
        #expect(viewModel.totalCents == 9_000)
        #expect(viewModel.isUpdating)

        data.release(call: 2, with: stats(group: spend([category(.groceries, cents: 2_000)])))
        await month.value

        #expect(viewModel.totalCents == 2_000)
        #expect(!viewModel.isUpdating)
    }

    // A slow Year answer arriving after the Month one must not overwrite it.
    @Test func aSupersededRangeAnswerIsIgnored() async {
        let data = ControlledStatsData(answer: stats())
        data.holdsRequests = true
        let viewModel = makeViewModel(data)

        let year = viewModel.select(.year)
        await data.waitForCall(1)
        let month = viewModel.select(.month)
        await data.waitForCall(2)

        data.release(call: 2, with: stats(group: spend([category(.groceries, cents: 2_000)])))
        await month.value
        data.release(call: 1, with: stats(group: spend([category(.groceries, cents: 50_000)])))
        await year.value

        #expect(viewModel.range == .month)
        #expect(viewModel.totalCents == 2_000)
    }

    @Test func aRangeWithNothingInItIsEmptyRatherThanLoaded() async {
        let data = ControlledStatsData(answer: stats(group: spend([]), mine: spend([])))
        let viewModel = makeViewModel(data)

        await viewModel.load()

        #expect(viewModel.state == .empty)
        #expect(viewModel.slices.isEmpty)
        #expect(viewModel.topExpenses.isEmpty)
    }

    // Other members spent; the caller had no share in any of it.
    @Test func mineCanBeEmptyWhileTheGroupIsNot() async {
        let data = ControlledStatsData(answer: stats(
            group: spend([category(.groceries, cents: 9_000)]),
            mine: spend([])
        ))
        let viewModel = makeViewModel(data)
        await viewModel.load()

        viewModel.select(.mine)

        #expect(viewModel.state == .empty)
    }

    @Test func aFailedLoadSaysWhyAndARetryRecovers() async {
        let data = ControlledStatsData(answer: stats())
        data.failure = APIError.networkError(URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(data)

        await viewModel.load()
        #expect(viewModel.state == .failed(L10n.Errors.network))

        data.failure = nil
        await viewModel.load()
        #expect(viewModel.state == .loaded)
    }

    // Each category sends its own five; the screen merges them, ranks by amount, then
    // newest, then highest id, and keeps five.
    @Test func biggestExpensesMergeEveryCategoryAndKeepFive() async {
        let data = ControlledStatsData(answer: stats(group: spend([
            category(.taxi, cents: 21_500, top: [
                expense(id: 4, cents: 8_000, date: "2026-03-05T12:00:00Z"),
                expense(id: 5, cents: 7_000),
                expense(id: 6, cents: 6_000),
                expense(id: 7, cents: 500)
            ]),
            category(.groceries, cents: 10_000, top: [
                expense(id: 1, cents: 9_000),
                expense(id: 2, cents: 1_000)
            ]),
            category(.rent, cents: 8_000, top: [
                expense(id: 3, cents: 8_000, date: "2026-03-02T12:00:00Z")
            ])
        ])))
        let viewModel = makeViewModel(data)

        await viewModel.load()

        #expect(viewModel.topExpenses.map(\.id) == [1, 4, 3, 5, 6])
        #expect(viewModel.topExpenses.map(\.category) == [.groceries, .taxi, .rent, .taxi, .taxi])
        #expect(viewModel.topExpenses.map(\.cents) == [9_000, 8_000, 8_000, 7_000, 6_000])
    }

    @Test func mineRanksAndPricesBiggestExpensesByShare() async {
        let data = ControlledStatsData(answer: stats(
            group: spend([
                category(.groceries, cents: 10_000, top: [expense(id: 1, cents: 10_000)]),
                category(.taxi, cents: 6_000, top: [expense(id: 2, cents: 6_000)])
            ]),
            mine: spend([
                category(.taxi, cents: 3_000, top: [expense(id: 2, cents: 3_000)]),
                category(.groceries, cents: 2_000, top: [expense(id: 1, cents: 2_000)])
            ])
        ))
        let viewModel = makeViewModel(data)
        await viewModel.load()

        viewModel.select(.mine)

        #expect(viewModel.topExpenses.map(\.id) == [2, 1])
        #expect(viewModel.topExpenses.map(\.cents) == [3_000, 2_000])
    }

    @Test func selectingAHeadingExpandsItsCategoriesAndFiltersBiggestExpenses() async {
        let data = ControlledStatsData(answer: stats(group: spend([
            category(.taxi, cents: 20_000, top: [expense(id: 1, cents: 20_000)]),
            category(.groceries, cents: 6_000, top: [
                expense(id: 2, cents: 3_000),
                expense(id: 3, cents: 2_000),
                expense(id: 4, cents: 1_000)
            ]),
            category(.diningOut, cents: 4_000, top: [
                expense(id: 5, cents: 2_500),
                expense(id: 6, cents: 1_000),
                expense(id: 7, cents: 500)
            ])
        ])))
        let viewModel = makeViewModel(data)
        await viewModel.load()

        viewModel.toggle(.foodAndDrink)

        #expect(viewModel.selectedHeading == .foodAndDrink)
        #expect(viewModel.legend.map(\.item) == [
            .heading(.transportation),
            .heading(.foodAndDrink),
            .category(.groceries),
            .category(.diningOut)
        ])
        #expect(viewModel.legend.map(\.cents) == [20_000, 10_000, 6_000, 4_000])
        // Two at $10.00 on the same day: the higher id first.
        #expect(viewModel.topExpenses.map(\.id) == [2, 5, 3, 6, 4])

        viewModel.clearSelection()

        #expect(viewModel.selectedHeading == nil)
        #expect(viewModel.legend.map(\.item) == [.heading(.transportation), .heading(.foodAndDrink)])
        #expect(viewModel.topExpenses.map(\.id) == [1, 2, 5, 3, 6])
    }

    @Test func selectingTheSelectedHeadingAgainClearsIt() async {
        let viewModel = makeViewModel(ControlledStatsData(answer: stats()))
        await viewModel.load()

        viewModel.toggle(.foodAndDrink)
        viewModel.toggle(.foodAndDrink)

        #expect(viewModel.selectedHeading == nil)
    }

    @Test func theSelectionSurvivesALensChangeWhileTheHeadingStillHasSpend() async {
        let data = ControlledStatsData(answer: stats(
            group: spend([category(.groceries, cents: 9_000), category(.taxi, cents: 4_000)]),
            mine: spend([category(.groceries, cents: 3_000)])
        ))
        let viewModel = makeViewModel(data)
        await viewModel.load()

        viewModel.toggle(.foodAndDrink)
        viewModel.select(.mine)
        #expect(viewModel.selectedHeading == .foodAndDrink)

        viewModel.select(.group)
        viewModel.toggle(.transportation)
        viewModel.select(.mine)
        #expect(viewModel.selectedHeading == nil)

        // Dropped for good: going back does not bring it back.
        viewModel.select(.group)
        #expect(viewModel.selectedHeading == nil)
    }

    @Test func theSelectionIsDroppedWhenANewRangeHasNothingUnderIt() async {
        let data = ControlledStatsData(answer: stats(group: spend([
            category(.groceries, cents: 9_000),
            category(.taxi, cents: 4_000)
        ])))
        let viewModel = makeViewModel(data)
        await viewModel.load()
        viewModel.toggle(.foodAndDrink)

        data.answer = stats(group: spend([category(.diningOut, cents: 1_000), category(.taxi, cents: 500)]))
        await viewModel.select(.year).value
        #expect(viewModel.selectedHeading == .foodAndDrink)

        data.answer = stats(group: spend([category(.taxi, cents: 500)]))
        await viewModel.select(.month).value
        #expect(viewModel.selectedHeading == nil)
    }

    // Slices are drawn largest first, so an angle value lands in the heading whose running
    // total first passes it.
    @Test func anAngleValueFindsTheSliceItFallsIn() async {
        let data = ControlledStatsData(answer: stats(group: spend([
            category(.groceries, cents: 6_000),
            category(.taxi, cents: 3_000),
            category(.rent, cents: 1_000)
        ])))
        let viewModel = makeViewModel(data)
        await viewModel.load()

        #expect(viewModel.heading(atAngleValue: 0) == .foodAndDrink)
        #expect(viewModel.heading(atAngleValue: 5_999) == .foodAndDrink)
        #expect(viewModel.heading(atAngleValue: 6_000) == .transportation)
        #expect(viewModel.heading(atAngleValue: 9_500) == .home)
        #expect(viewModel.heading(atAngleValue: 10_000) == .home)
    }

    @Test func theCentreCountsTheLensExpenses() async {
        let data = ControlledStatsData(answer: stats(
            group: SpendStats(totalCents: 9_000, expenseCount: 4, categories: [category(.groceries, cents: 9_000)]),
            mine: SpendStats(totalCents: 2_000, expenseCount: 2, categories: [category(.groceries, cents: 2_000)])
        ))
        let viewModel = makeViewModel(data)
        await viewModel.load()
        #expect(viewModel.expenseCount == 4)

        viewModel.select(.mine)
        #expect(viewModel.expenseCount == 2)
    }
}

@MainActor
/// Charts is always reachable; without an expense it asks for one instead of charting.
struct ChartsEmptyGroupTests {
    @Test func aGroupWithOnlySettlementsAsksForAnExpense() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.expensesForCall = { _ in
            [TestExpense.make(id: 1, paidBy: 1, amount: 10, splitAmounts: [1: 10, 2: -10], type: .payment)]
        }
        let session = GroupSession(groupId: 1, dataSource: data.source())
        await session.appear().value
        #expect(!session.hasExpenses)
    }

    @Test func oneExpenseIsEnoughToChart() async {
        let data = ControlledGroupData()
        data.autoRelease = true
        data.expensesForCall = { _ in
            [TestExpense.make(id: 1, paidBy: 1, amount: 10, splitAmounts: [1: 10, 2: -10], type: .payment),
             TestExpense.make(id: 2, paidBy: 1, amount: 30, splitAmounts: [1: 15, 2: 15])]
        }
        let session = GroupSession(groupId: 1, dataSource: data.source())
        await session.appear().value
        #expect(session.hasExpenses)
    }

    @Test func anEmptyGroupAsksForAnExpense() {
        #expect(!GroupSession(groupId: 1).hasExpenses)
    }
}

// MARK: - Fixtures

extension ChartsViewModelTests {
    /// 2026-03-14 12:00 in São Paulo.
    static let now = Date(timeIntervalSince1970: 1_773_500_400)

    func makeViewModel(_ data: ControlledStatsData) -> ChartsViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return ChartsViewModel(
            groupId: 7,
            dataSource: data.source(),
            now: { Self.now },
            calendar: calendar
        )
    }

    func stats(group: SpendStats? = nil, mine: SpendStats? = nil) -> GroupStats {
        let group = group ?? spend([category(.groceries, cents: 1_000)])
        return GroupStats(group: group, mine: mine ?? group)
    }

    func spend(_ categories: [CategoryStats]) -> SpendStats {
        SpendStats(
            totalCents: categories.reduce(0) { $0 + $1.totalCents },
            expenseCount: categories.reduce(0) { $0 + $1.expenseCount },
            categories: categories
        )
    }

    func category(_ category: ExpenseCategory, cents: Int, top: [TopExpense]? = nil) -> CategoryStats {
        let top = top ?? [expense(id: cents, cents: cents)]
        return CategoryStats(category: category, totalCents: cents, expenseCount: top.count, top: top)
    }

    func expense(id: Int, cents: Int, date: String = "2026-03-01T12:00:00Z") -> TopExpense {
        TopExpense(expenseId: id, description: "Expense \(id)", date: date, amountCents: cents)
    }
}

/// Answers every request with `answer` unless a test holds requests open to decide the
/// order they come back in.
@MainActor
final class ControlledStatsData {
    var answer: GroupStats
    var failure: Error?
    var holdsRequests = false
    private(set) var queries: [StatsQuery] = []
    private var held: [Int: CheckedContinuation<GroupStats, Error>] = [:]
    private var arrivals: [Int: CheckedContinuation<Void, Never>] = [:]

    init(answer: GroupStats) {
        self.answer = answer
    }

    func source() -> ChartsDataSource {
        ChartsDataSource(stats: { [self] groupId, query in
            try await respond(groupId: groupId, query: query)
        })
    }

    private func respond(groupId: Int, query: StatsQuery) async throws -> GroupStats {
        queries.append(query)
        let call = queries.count
        arrivals.removeValue(forKey: call)?.resume()
        if let failure { throw failure }
        guard holdsRequests else { return answer }
        return try await withCheckedThrowingContinuation { held[call] = $0 }
    }

    func waitForCall(_ call: Int) async {
        guard queries.count < call else { return }
        await withCheckedContinuation { arrivals[call] = $0 }
    }

    func release(call: Int, with stats: GroupStats) {
        held.removeValue(forKey: call)?.resume(returning: stats)
    }
}

struct GroupStatsDecodingTests {
    @Test func decodesAmountsToCentsAtTheBoundary() throws {
        let payload = #"""
        {"group":{"total":62.5,"expenseCount":2,"categories":[{"category":"dining_out","total":62.5,"expenseCount":2,"top":[{"expenseId":9,"description":"Sushi","date":"2026-03-01T22:15:00Z","amount":50.25},{"expenseId":8,"description":"Pizza","date":"2026-02-27T19:00:00","amount":12.25}]}]},
         "mine":{"total":0,"expenseCount":0,"categories":[]}}
        """#

        let stats = try JSONDecoder().decode(GroupStats.self, from: Data(payload.utf8))
        let dining = try #require(stats.group.categories.first)

        #expect(stats.group.totalCents == 6_250)
        #expect(dining.category == .diningOut)
        #expect(dining.top.map(\.amountCents) == [5_025, 1_225])
        #expect(dining.top.first?.effectiveDate == Expense.parseTimestamp("2026-03-01T22:15:00Z"))
        #expect(dining.top.last?.effectiveDate != nil)
        #expect(stats.mine.categories.isEmpty)
    }

    // A category added by a newer server files under General rather than failing the screen.
    @Test func anUnknownCategoryReadsAsGeneral() throws {
        let payload = #"{"category":"space_travel","total":1,"expenseCount":1,"top":[]}"#
        let category = try JSONDecoder().decode(CategoryStats.self, from: Data(payload.utf8))
        #expect(category.category == .general)
        #expect(category.totalCents == 100)
    }
}
