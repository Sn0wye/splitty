//
//  ChartsViewModel.swift
//  Splitty
//

import Foundation

struct ChartsDataSource {
    var stats: (Int, StatsQuery) async throws -> GroupStats

    static let live = ChartsDataSource(
        stats: { try await GroupService.shared.getStats(groupId: $0, query: $1) }
    )
}

/// One heading's share of the donut.
struct HeadingSlice: Identifiable, Equatable {
    let heading: ExpenseCategoryHeading
    let cents: Int
    /// Of the lens total, `0...1`.
    let fraction: Double

    var id: ExpenseCategoryHeading { heading }
}

/// A legend line: a heading, or one of the selected heading's categories beneath it.
struct ChartsLegendRow: Identifiable, Equatable {
    enum Item: Hashable {
        case heading(ExpenseCategoryHeading)
        case category(ExpenseCategory)
    }

    let item: Item
    let cents: Int
    /// Of the lens total, `0...1`, for categories as well as headings.
    let fraction: Double

    var id: Item { item }
}

/// One row of Biggest expenses, priced by the lens: the full amount under group spend,
/// the caller's split under share.
struct ChartsTopExpense: Identifiable, Equatable {
    let id: Int
    let description: String
    let category: ExpenseCategory
    let date: Date?
    let cents: Int

    init(_ expense: TopExpense, category: ExpenseCategory) {
        id = expense.expenseId
        description = expense.description
        self.category = category
        date = expense.effectiveDate
        cents = expense.amountCents
    }

    /// The server's order: amount, then date, then id, all descending.
    static func ranksAbove(_ lhs: ChartsTopExpense, _ rhs: ChartsTopExpense) -> Bool {
        if lhs.cents != rhs.cents { return lhs.cents > rhs.cents }
        let lhsDate = lhs.date ?? .distantPast
        let rhsDate = rhs.date ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return lhs.id > rhs.id
    }
}

@MainActor
final class ChartsViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded
        case empty
        case failed(String)
    }

    private enum Phase: Equatable {
        case loading
        case ready(GroupStats)
        case failed(String)
    }

    let groupId: Int

    @Published private(set) var lens: ChartsLens = .group
    @Published private(set) var range: ChartsRange = .allTime
    /// Expands the heading in the legend and filters Biggest expenses to it.
    @Published private(set) var selectedHeading: ExpenseCategoryHeading?
    @Published private var phase: Phase = .loading

    private let dataSource: ChartsDataSource
    private let now: () -> Date
    private let calendar: Calendar

    /// Counts started loads. A load that is no longer the newest publishes nothing, so a
    /// slow answer for an earlier range never replaces a newer one.
    private var loadGeneration = 0

    init(
        groupId: Int,
        dataSource: ChartsDataSource = .live,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = ChartsViewModel.deviceCalendar
    ) {
        self.groupId = groupId
        self.dataSource = dataSource
        self.now = now
        self.calendar = calendar
    }

    /// Gregorian whatever the device calendar is, since the server reads Gregorian dates,
    /// in the device's own zone.
    nonisolated static var deviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    var state: State {
        switch phase {
        case .loading: .loading
        case .failed(let message): .failed(message)
        case .ready(let stats): stats[lens].categories.isEmpty ? .empty : .loaded
        }
    }

    private var spend: SpendStats? {
        guard case .ready(let stats) = phase else { return nil }
        return stats[lens]
    }

    var totalCents: Int { spend?.totalCents ?? 0 }
    var expenseCount: Int { spend?.expenseCount ?? 0 }

    /// Headings are derived here rather than on the server, so moving a category between
    /// headings stays a client-only change. Largest first; ties in heading order.
    var slices: [HeadingSlice] {
        guard let spend else { return [] }
        var byHeading: [ExpenseCategoryHeading: Int] = [:]
        for category in spend.categories {
            byHeading[Self.heading(of: category.category), default: 0] += category.totalCents
        }
        return Self.ranked(byHeading, order: ExpenseCategoryHeading.allCases)
            .map { HeadingSlice(heading: $0.key, cents: $0.value, fraction: fraction(of: $0.value)) }
    }

    /// Every heading, with the selected one followed by its categories.
    var legend: [ChartsLegendRow] {
        guard let spend else { return [] }
        return slices.flatMap { slice in
            let row = ChartsLegendRow(item: .heading(slice.heading), cents: slice.cents, fraction: slice.fraction)
            guard slice.heading == selectedHeading else { return [row] }

            var byCategory: [ExpenseCategory: Int] = [:]
            for category in spend.categories where Self.heading(of: category.category) == slice.heading {
                byCategory[category.category, default: 0] += category.totalCents
            }
            let leaves = Self.ranked(byCategory, order: ExpenseCategory.allCases).map {
                ChartsLegendRow(item: .category($0.key), cents: $0.value, fraction: fraction(of: $0.value))
            }
            return [row] + leaves
        }
    }

    /// The five largest expenses. Every one of them is in its own category's top five, so
    /// merging those lists and taking five again is exact.
    var topExpenses: [ChartsTopExpense] {
        guard let spend else { return [] }
        return Array(
            spend.categories
                .filter { selectedHeading == nil || Self.heading(of: $0.category) == selectedHeading }
                .flatMap { category in category.top.map { ChartsTopExpense($0, category: category.category) } }
                .sorted(by: ChartsTopExpense.ranksAbove)
                .prefix(5)
        )
    }

    private func fraction(of cents: Int) -> Double {
        totalCents == 0 ? 0 : Double(cents) / Double(totalCents)
    }

    private static func heading(of category: ExpenseCategory) -> ExpenseCategoryHeading {
        category.heading ?? .uncategorized
    }

    /// Non-zero entries, largest first, ties in `order`.
    private static func ranked<Key: Hashable>(_ totals: [Key: Int], order: [Key]) -> [(key: Key, value: Int)] {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return totals
            .filter { $0.value != 0 }
            .sorted { lhs, rhs in
                lhs.value != rhs.value
                    ? lhs.value > rhs.value
                    : rank[lhs.key, default: .max] < rank[rhs.key, default: .max]
            }
    }

    /// Selecting the selected heading again clears it.
    func toggle(_ heading: ExpenseCategoryHeading) {
        selectedHeading = selectedHeading == heading ? nil : heading
    }

    /// The heading a donut angle value falls in: slices are drawn in `slices` order, each
    /// spanning its own cents.
    func heading(atAngleValue value: Int) -> ExpenseCategoryHeading? {
        var running = 0
        for slice in slices {
            running += slice.cents
            if value < running { return slice.heading }
        }
        return slices.last?.heading
    }

    func clearSelection() {
        selectedHeading = nil
    }

    /// A selection only survives while its heading still has spend, so the filter never
    /// narrows the screen to nothing.
    private func dropEmptySelection() {
        guard let selectedHeading, spend != nil else { return }
        if !slices.contains(where: { $0.heading == selectedHeading }) {
            self.selectedHeading = nil
        }
    }

    /// Both halves are already loaded, so this never fetches.
    func select(_ lens: ChartsLens) {
        self.lens = lens
        dropEmptySelection()
    }

    func select(_ range: ChartsRange) async {
        guard range != self.range else { return }
        self.range = range
        phase = .loading
        await load()
    }

    /// Fetches the current range. Whatever is on screen stays there until the answer
    /// arrives, so a refresh after a write does not blank the sheet.
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let query = range.query(now: now(), calendar: calendar)
        do {
            let stats = try await dataSource.stats(groupId, query)
            guard generation == loadGeneration else { return }
            phase = .ready(stats)
            dropEmptySelection()
        } catch {
            guard generation == loadGeneration, !error.isCancellation else { return }
            phase = .failed(error.displayMessage)
        }
    }
}
