//
//  ChartsPrototypeView.swift
//  Splitty
//
//  PROTOTYPE — throwaway, do not ship. Answered "which charts are worth keeping on the
//  group Charts screen?". This is layout A (dashboard stack), the one that won; layouts B
//  (ranked list) and C (one chart per page) were rejected and removed. Verdict: keep By
//  category and Biggest expenses, defer Over time, cut the summary tiles and Paid vs share.
//  Aggregates the expense list on the client; the real feature aggregates on the server.
//  Copy is hardcoded English on purpose. Launch a Debug build with `-chartsPrototype` to
//  open it on fixture data.
//

import SwiftUI
import Charts

// MARK: - Controls

enum ChartsPrototypeRange: String, CaseIterable, Identifiable {
    case thisMonth = "Month"
    case last3Months = "3 months"
    case thisYear = "Year"
    case allTime = "All time"

    var id: Self { self }

    func start(now: Date, calendar: Calendar) -> Date? {
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? now
        switch self {
        case .thisMonth: return month
        case .last3Months: return calendar.date(byAdding: .month, value: -2, to: month)
        case .thisYear: return calendar.dateInterval(of: .year, for: now)?.start
        case .allTime: return nil
        }
    }

    /// Short ranges bucket by week, long ones by month.
    var bucketUnit: Calendar.Component {
        switch self {
        case .thisMonth, .last3Months: .weekOfYear
        case .thisYear, .allTime: .month
        }
    }
}

/// Group = group spend, Mine = share.
enum ChartsPrototypeLens: String, CaseIterable, Identifiable {
    case group = "Group"
    case mine = "Mine"

    var id: Self { self }
}

// MARK: - Aggregation

struct ChartsPrototypeData {
    struct HeadingSlice: Identifiable {
        let heading: ExpenseCategoryHeading
        let cents: Int
        var id: ExpenseCategoryHeading { heading }
        var tint: Color { heading.categories.first?.tint ?? .gray }
    }

    struct CategorySlice: Identifiable {
        let category: ExpenseCategory
        let cents: Int
        var id: ExpenseCategory { category }
    }

    struct Bucket: Identifiable {
        let start: Date
        let cents: Int
        var id: Date { start }
    }

    struct MemberRow: Identifiable {
        let userId: Int
        let name: String
        let paid: Int
        let share: Int
        var id: Int { userId }
    }

    struct Top: Identifiable {
        let id: Int
        let description: String
        let category: ExpenseCategory
        let date: Date?
        let cents: Int
    }

    // Independent of the lens.
    let groupSpend: Int
    let myShare: Int
    let myPaid: Int
    let members: [MemberRow]

    // Follow the lens.
    let lensTotal: Int
    let headings: [HeadingSlice]
    let categories: [CategorySlice]
    let buckets: [Bucket]
    let bucketUnit: Calendar.Component
    let top: [Top]
    let expenseCount: Int

    init(
        expenses: [Expense],
        currentUserId: Int,
        lens: ChartsPrototypeLens,
        range: ChartsPrototypeRange,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let start = range.start(now: now, calendar: calendar)
        let inRange = expenses.filter { expense in
            guard expense.type == .expense else { return false }
            guard let start else { return true }
            guard let date = expense.effectiveDate else { return false }
            return date >= start
        }

        func lensCents(_ expense: Expense) -> Int {
            switch lens {
            case .group:
                return Money.cents(from: expense.amount)
            case .mine:
                return expense.splits
                    .filter { $0.userId == currentUserId }
                    .reduce(0) { $0 + Money.cents(from: $1.amount) }
            }
        }

        groupSpend = inRange.reduce(0) { $0 + Money.cents(from: $1.amount) }
        myPaid = inRange
            .filter { $0.paidBy == currentUserId }
            .reduce(0) { $0 + Money.cents(from: $1.amount) }
        myShare = inRange
            .flatMap(\.splits)
            .filter { $0.userId == currentUserId }
            .reduce(0) { $0 + Money.cents(from: $1.amount) }

        var names: [Int: String] = [:]
        var paid: [Int: Int] = [:]
        var share: [Int: Int] = [:]
        for expense in inRange {
            names[expense.paidBy] = expense.paidByUser.name
            paid[expense.paidBy, default: 0] += Money.cents(from: expense.amount)
            for split in expense.splits {
                names[split.userId] = split.user.name
                share[split.userId, default: 0] += Money.cents(from: split.amount)
            }
        }
        members = names
            .map { id, name in
                MemberRow(
                    userId: id,
                    name: id == currentUserId ? "You" : name,
                    paid: paid[id] ?? 0,
                    share: share[id] ?? 0
                )
            }
            .sorted { max($0.paid, $0.share) > max($1.paid, $1.share) }

        let weighted = inRange
            .map { (expense: $0, cents: lensCents($0)) }
            .filter { $0.cents > 0 }
        expenseCount = weighted.count
        lensTotal = weighted.reduce(0) { $0 + $1.cents }

        var byHeading: [ExpenseCategoryHeading: Int] = [:]
        var byCategory: [ExpenseCategory: Int] = [:]
        for item in weighted {
            byHeading[item.expense.category.heading ?? .uncategorized, default: 0] += item.cents
            byCategory[item.expense.category, default: 0] += item.cents
        }
        headings = byHeading
            .map { HeadingSlice(heading: $0.key, cents: $0.value) }
            .sorted { $0.cents > $1.cents }
        categories = byCategory
            .map { CategorySlice(category: $0.key, cents: $0.value) }
            .sorted { $0.cents > $1.cents }

        let unit = range.bucketUnit
        bucketUnit = unit
        var byBucket: [Date: Int] = [:]
        for item in weighted {
            guard let date = item.expense.effectiveDate,
                  let bucket = calendar.dateInterval(of: unit, for: date)?.start else { continue }
            byBucket[bucket, default: 0] += item.cents
        }
        // Fill the gaps so an empty month reads as zero rather than vanishing.
        var filled: [Bucket] = []
        let dates = byBucket.keys
        if let first = [start.flatMap { calendar.dateInterval(of: unit, for: $0)?.start }, dates.min()]
                .compactMap({ $0 }).min(),
           let last = [calendar.dateInterval(of: unit, for: now)?.start, dates.max()]
                .compactMap({ $0 }).max() {
            var cursor = first
            while cursor <= last {
                filled.append(Bucket(start: cursor, cents: byBucket[cursor] ?? 0))
                guard let next = calendar.date(byAdding: unit, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
        buckets = filled

        top = weighted
            .sorted { $0.cents > $1.cents }
            .prefix(5)
            .map {
                Top(
                    id: $0.expense.id,
                    description: $0.expense.description,
                    category: $0.expense.category,
                    date: $0.expense.effectiveDate,
                    cents: $0.cents
                )
            }
    }
}

// MARK: - Screen

struct ChartsPrototypeView: View {
    let expenses: [Expense]
    let currentUserId: Int

    @Environment(\.dismiss) private var dismiss
    @State private var lens: ChartsPrototypeLens = .group
    @State private var range: ChartsPrototypeRange = .allTime

    private var data: ChartsPrototypeData {
        ChartsPrototypeData(expenses: expenses, currentUserId: currentUserId, lens: lens, range: range)
    }

    var body: some View {
        NavigationStack {
            StackVariant(data: data, lens: lens, controls: controls)
            .background(Color("background"))
            .navigationTitle("Charts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .animation(.snappy, value: lens)
            .animation(.snappy, value: range)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Lens", selection: $lens) {
                ForEach(ChartsPrototypeLens.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Range", selection: $range) {
                ForEach(ChartsPrototypeRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Layout A: dashboard stack

/// Everything on one scroll: stat tiles, donut, bars, grouped bars, list.
private struct StackVariant<Controls: View>: View {
    let data: ChartsPrototypeData
    let lens: ChartsPrototypeLens
    let controls: Controls

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                HStack(spacing: 10) {
                    StatTile(title: "Group spend", cents: data.groupSpend)
                    StatTile(title: "Your share", cents: data.myShare)
                    StatTile(title: "You paid", cents: data.myPaid)
                }
                Card(title: "By category") {
                    CategoryDonut(data: data)
                        .frame(height: 220)
                    HeadingLegend(data: data)
                }
                Card(title: "Over time") {
                    TimeBars(data: data).frame(height: 180)
                }
                Card(title: "Paid vs share") {
                    PaidVsShareBars(data: data).frame(height: 200)
                }
                Card(title: "Biggest expenses") {
                    TopList(data: data)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Chart pieces

private struct CategoryDonut: View {
    let data: ChartsPrototypeData

    var body: some View {
        if data.headings.isEmpty {
            EmptyChart()
        } else {
            Chart(data.headings) { slice in
                SectorMark(
                    angle: .value("Amount", slice.cents),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(slice.tint)
            }
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text(Money.formatted(cents: data.lensTotal))
                        .font(.title3.weight(.bold))
                    Text("\(data.expenseCount) expenses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct HeadingLegend: View {
    let data: ChartsPrototypeData

    var body: some View {
        VStack(spacing: 8) {
            ForEach(data.headings) { slice in
                HStack {
                    Circle().fill(slice.tint).frame(width: 10, height: 10)
                    Text(slice.heading.title)
                    Spacer()
                    Text(percent(slice.cents)).foregroundStyle(.secondary)
                    Text(Money.formatted(cents: slice.cents))
                        .monospacedDigit()
                        .frame(minWidth: 80, alignment: .trailing)
                }
                .font(.subheadline)
            }
        }
    }

    private func percent(_ cents: Int) -> String {
        guard data.lensTotal > 0 else { return "" }
        return "\(Int((Double(cents) / Double(data.lensTotal) * 100).rounded()))%"
    }
}

private struct TimeBars: View {
    let data: ChartsPrototypeData

    var body: some View {
        if data.buckets.isEmpty {
            EmptyChart()
        } else {
            Chart(data.buckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.start, unit: data.bucketUnit),
                    y: .value("Amount", Money.amount(cents: bucket.cents))
                )
                .foregroundStyle(Color("foreground"))
                .cornerRadius(3)
            }
            .chartYAxis { dollarAxis }
        }
    }
}

private struct PaidVsShareBars: View {
    let data: ChartsPrototypeData

    var body: some View {
        if data.members.isEmpty {
            EmptyChart()
        } else {
            Chart {
                ForEach(data.members) { member in
                    BarMark(
                        x: .value("Member", member.name),
                        y: .value("Amount", Money.amount(cents: member.paid))
                    )
                    .foregroundStyle(by: .value("Kind", "Paid"))
                    .position(by: .value("Kind", "Paid"))
                    BarMark(
                        x: .value("Member", member.name),
                        y: .value("Amount", Money.amount(cents: member.share))
                    )
                    .foregroundStyle(by: .value("Kind", "Share"))
                    .position(by: .value("Kind", "Share"))
                }
            }
            .chartForegroundStyleScale(["Paid": Color("foreground"), "Share": Color("muted-foreground")])
            .chartYAxis { dollarAxis }
        }
    }
}

private struct TopList: View {
    let data: ChartsPrototypeData

    var body: some View {
        if data.top.isEmpty {
            EmptyChart()
        } else {
            VStack(spacing: 12) {
                ForEach(Array(data.top.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Image(systemName: item.category.glyph)
                            .foregroundStyle(item.category.tint)
                            .frame(width: 32, height: 32)
                            .background(item.category.tint.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.description).lineLimit(1)
                            if let date = item.date {
                                Text(date, format: .dateTime.day().month(.abbreviated).year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(Money.formatted(cents: item.cents)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

// MARK: - Small pieces

@AxisContentBuilder
private var dollarAxis: some AxisContent {
    AxisMarks(position: .leading) { value in
        AxisGridLine()
        AxisValueLabel {
            if let amount = value.as(Double.self) {
                Text("$\(Int(amount))")
            }
        }
    }
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("card"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color("border")))
    }
}

private struct StatTile: View {
    let title: String
    let cents: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Money.formatted(cents: cents))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("card"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color("border")))
    }
}

private struct EmptyChart: View {
    var body: some View {
        Text("Nothing in this range")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

// MARK: - Fixtures (DEBUG only)

#if DEBUG
/// Launch with `-chartsPrototype` to open the screen straight on these, no API or sign-in.
/// Fourteen months of a four-person household, generated deterministically relative to
/// today, plus two settlements (which must not show up) and one future-dated trip.
enum ChartsPrototypeFixtures {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-chartsPrototype")
    }

    static let currentUserId = 1

    private static let users: [User] = [
        User(id: 1, name: "Gabriel", email: "gabriel@example.com", createdAt: stamp(.now), updatedAt: stamp(.now)),
        User(id: 2, name: "Ana", email: "ana@example.com", createdAt: stamp(.now), updatedAt: stamp(.now)),
        User(id: 3, name: "Bruno", email: "bruno@example.com", createdAt: stamp(.now), updatedAt: stamp(.now)),
        User(id: 4, name: "Carla", email: "carla@example.com", createdAt: stamp(.now), updatedAt: stamp(.now)),
    ]

    private static let templates: [(String, ExpenseCategory, ClosedRange<Int>)] = [
        ("Groceries", .groceries, 4_000...18_000),
        ("Pizza night", .diningOut, 6_000...14_000),
        ("Sushi", .diningOut, 12_000...26_000),
        ("Uber", .taxi, 1_500...5_500),
        ("Gas", .gasFuel, 8_000...20_000),
        ("Electricity", .electricity, 18_000...32_000),
        ("Internet", .tvPhoneInternet, 12_000...12_000),
        ("Cleaning supplies", .householdSupplies, 2_000...7_000),
        ("Movie tickets", .movies, 5_000...9_000),
        ("Beer", .liquor, 3_000...9_000),
        ("Pharmacy", .medical, 2_500...8_000),
        ("Misc", .general, 1_000...6_000),
    ]

    static let expenses: [Expense] = {
        let calendar = Calendar.current
        let now = Date.now
        var seed: UInt64 = 42
        func next(_ range: ClosedRange<Int>) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let span = UInt64(range.upperBound - range.lowerBound + 1)
            return range.lowerBound + Int((seed >> 33) % span)
        }

        var rows: [Expense] = []
        var id = 1
        func add(_ description: String, _ category: ExpenseCategory, cents: Int, paidBy: Int,
                 participants: [Int], date: Date, type: ExpenseType = .expense) {
            let sorted = participants.sorted()
            let base = cents / sorted.count
            let remainder = cents % sorted.count
            let splits = sorted.enumerated().map { index, userId in
                ExpenseSplit(
                    id: id * 10 + index,
                    expenseId: id,
                    userId: userId,
                    amount: Money.amount(cents: base + (index < remainder ? 1 : 0)),
                    percentage: nil,
                    user: users[userId - 1]
                )
            }
            rows.append(Expense(
                id: id, groupId: 1, paidBy: paidBy, amount: Money.amount(cents: cents),
                description: description, type: type,
                category: type == .payment ? .payment : category,
                splitMode: type == .payment ? nil : .equal,
                date: stamp(date), createdAt: stamp(date), updatedAt: stamp(date),
                paidByUser: users[paidBy - 1], splits: splits
            ))
            id += 1
        }

        for daysAgo in stride(from: 420, through: 0, by: -1) where next(0...9) < 3 {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let template = templates[next(0...(templates.count - 1))]
            let everyone = [1, 2, 3, 4]
            let participants = next(0...3) == 0 ? Array(everyone.dropFirst(next(0...1)).prefix(next(2...3))) : everyone
            let payer = participants[next(0...(participants.count - 1))]
            add(template.0, template.1, cents: next(template.2), paidBy: payer,
                participants: participants, date: date)
        }

        // A trip: one big month, and one booking dated next month.
        if let trip = calendar.date(byAdding: .month, value: -5, to: now) {
            add("Flights to Lisbon", .plane, cents: 248_000, paidBy: 2, participants: [1, 2, 3, 4], date: trip)
            add("Airbnb Lisbon", .hotel, cents: 186_500, paidBy: 1, participants: [1, 2, 3, 4], date: trip)
        }
        if let future = calendar.date(byAdding: .day, value: 20, to: now) {
            add("Concert tickets", .music, cents: 64_000, paidBy: 3, participants: [1, 3], date: future)
        }

        // Settlements: must be excluded everywhere.
        if let paid = calendar.date(byAdding: .day, value: -3, to: now) {
            add("Payment", .payment, cents: 50_000, paidBy: 1, participants: [2], date: paid, type: .payment)
            add("Payment", .payment, cents: 30_000, paidBy: 4, participants: [3], date: paid, type: .payment)
        }
        return rows
    }()

    private static func stamp(_ date: Date) -> String {
        date.ISO8601Format()
    }
}
#endif
