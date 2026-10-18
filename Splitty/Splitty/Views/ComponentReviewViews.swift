import SwiftUI

/// Sample content for the review gallery's component screens. The data sources answer
/// locally; group 0 does not exist, so anything that still reaches the server from a
/// pushed screen is refused rather than applied.
enum ReviewSamples {
    static let groupId = 0
    static let currentUserId = 1

    static let users: [User] = [
        user(1, "Gabriel"),
        user(2, "Ana"),
        user(3, "Bo"),
        user(4, "Cleo"),
    ]

    static let members: [GroupMember] = users.map {
        GroupMember(id: $0.id, userId: $0.id, name: $0.name, email: $0.email, avatarUrl: "")
    }

    /// A landscape photo stand-in with a grid, so panning, zooming and the bounds show.
    static let avatarPhoto: UIImage = {
        let size = CGSize(width: 1_600, height: 1_000)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.systemTeal.cgColor, UIColor.systemIndigo.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: nil) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            UIColor.white.withAlphaComponent(0.35).setStroke()
            for x in stride(from: CGFloat(0), through: size.width, by: 100) {
                context.cgContext.strokeLineSegments(between: [CGPoint(x: x, y: 0), CGPoint(x: x, y: size.height)])
            }
            for y in stride(from: CGFloat(0), through: size.height, by: 100) {
                context.cgContext.strokeLineSegments(between: [CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y)])
            }
            UIColor.systemYellow.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 650, y: 350, width: 300, height: 300))
            UIColor.systemPink.setFill()
            context.cgContext.fill(CGRect(x: 120, y: 120, width: 160, height: 160))
            context.cgContext.fill(CGRect(x: 1_320, y: 720, width: 160, height: 160))
        }
    }()

    /// Every row shape the timeline draws, spread over enough days that the last row has
    /// to scroll clear of the add button.
    static func timeline(now: Date = Date(), calendar: Calendar = .current) -> [Expense] {
        let removed = user(9, MemberDisplay.tombstoneName)
        let rows: [(days: Int, description: String, category: ExpenseCategory, payer: User, amount: Double, shares: [Int: Double])] = [
            (0, "Groceries", .groceries, users[0], 84.30, [1: 28.10, 2: 28.10, 3: 28.10]),
            (1, "Dinner at the sushi place", .diningOut, users[1], 120, [1: 40, 2: 40, 3: 40]),
            (1, "Rent", .rent, users[0], 1_500, [1: 750, 4: 750]),
            (2, "New phone", .electronics, users[0], 100, [1: 50, 2: 50]),
            (3, "Taxi from the airport after the delayed flight, split four ways", .taxi, users[2], 48, [1: 12, 2: 12, 3: 12, 4: 12]),
            (3, "Coffee", .diningOut, users[0], 4.50, [1: 4.50]),
            (5, "Concert tickets", .music, users[1], 90, [2: 45, 3: 45]),
            (9, "Electricity", .electricity, users[3], 92.16, [1: 46.08, 4: 46.08]),
            (12, "Hotel", .hotel, users[0], 640, [1: 160, 2: 160, 3: 160, 4: 160]),
            (20, "Parking", .parking, removed, 12, [9: 6, 1: 6]),
            (34, "Groceries", .groceries, users[3], 61.75, [1: 30.88, 4: 30.87]),
            (90, "Board games", .games, users[2], 36, [1: 12, 2: 12, 3: 12]),
            (400, "Plane tickets", .plane, users[0], 980, [1: 490, 2: 490]),
        ]

        var id = 0
        var expenses: [Expense] = rows.map { row in
            id += 1
            return expense(
                id: id,
                date: day(row.days, from: now, calendar: calendar),
                description: row.description,
                category: row.category,
                payer: row.payer,
                amount: row.amount,
                shares: row.shares,
                recurring: [.rent, .electronics].contains(row.category) ? .monthly : nil,
                // The phone is paid in twelve parts, the rent has no end.
                installment: row.category == .electronics ? ExpenseInstallment(number: 4, total: 12) : nil
            )
        }

        // Settlements in both directions: someone paying you, and you paying someone.
        for (days, payer, payee, amount) in [(0, users[1], users[0], 20.0), (60, users[0], users[2], 35.0)] {
            id += 1
            expenses.append(expense(
                id: id,
                date: day(days, from: now, calendar: calendar),
                description: "Payment",
                category: .general,
                payer: payer,
                amount: amount,
                shares: [payer.id: amount, payee.id: -amount],
                type: .payment
            ))
        }
        return expenses
    }

    /// Spend over the sample timeline, filtered to the range asked for the way the server
    /// would, so each range the picker moves to lands on different numbers.
    static func stats(for query: StatsQuery, expenses: [Expense]) -> GroupStats {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: query.timeZone) ?? .current
        let from = query.from.flatMap { localDate($0, calendar: calendar) }
        let to = query.to.flatMap { localDate($0, calendar: calendar) }

        let inRange = expenses.filter { expense in
            guard expense.type == .expense, let date = expense.effectiveDate else { return false }
            return (from.map { date >= $0 } ?? true) && (to.map { date < $0 } ?? true)
        }
        return GroupStats(
            group: spend(inRange) { Money.cents(from: $0.amount) },
            mine: spend(inRange) { expense in
                Money.cents(from: expense.splits.first { $0.userId == currentUserId }?.amount ?? 0)
            }
        )
    }

    /// Waits long enough for the loading and updating states to be seen, then answers.
    static func charts(expenses: [Expense], failingFirstLoad: Bool = false) -> ChartsDataSource {
        let attempts = AttemptCounter()
        return ChartsDataSource { _, query in
            try await Task.sleep(for: .milliseconds(600))
            attempts.count += 1
            if failingFirstLoad, attempts.count == 1 { throw APIError.networkError(URLError(.notConnectedToInternet)) }
            return stats(for: query, expenses: expenses)
        }
    }

    /// The Installments section of a group paying for a phone and a course in parts, and
    /// rent with no end.
    static let plans: [RecurringPlan] = [
        RecurringPlan(
            id: 1, description: "New phone", amount: 100, category: .electronics, paidBy: 1,
            frequency: .monthly, nextDueOn: "2026-11-02", endsOn: "2027-07-02",
            progress: .init(added: 4, total: 12)
        ),
        RecurringPlan(
            id: 2, description: "Rent", amount: 1_500, category: .rent, paidBy: 1,
            frequency: .monthly, nextDueOn: "2026-11-13", endsOn: nil,
            progress: .init(added: 9, total: nil)
        ),
        RecurringPlan(
            id: 3, description: "Spanish course with a very long name that wraps", amount: 45, category: .general,
            paidBy: 2, frequency: .fortnightly, nextDueOn: "2026-10-20", endsOn: "2026-12-29",
            progress: .init(added: 2, total: 8)
        ),
    ]

    /// Waits long enough for the loading state to be seen, then answers.
    static func plansSource(_ plans: [RecurringPlan]) -> PlansDataSource {
        PlansDataSource { _ in
            try await Task.sleep(for: .milliseconds(600))
            return plans
        }
    }

    /// Saving waits like a request would, then fails, so the review reaches the saving
    /// state and the error without writing anything.
    static let expenseForm = ExpenseFormDataSource(
        create: { _ in
            try await Task.sleep(for: .milliseconds(600))
            throw ReviewOnly()
        },
        update: { _ in
            try await Task.sleep(for: .milliseconds(600))
            throw ReviewOnly()
        }
    )

    /// You owe Ana $165.00 and nothing else, so recording the whole amount settles you up
    /// and a smaller amount does not.
    static let settleUpDebt = BalanceRow(
        from: DebtMember(id: users[0].id, name: users[0].name, avatarUrl: ""),
        to: DebtMember(id: users[1].id, name: users[1].name, avatarUrl: ""),
        amountCents: 16_500,
        involvement: .youPay
    )

    static let settleUpTrip = Group(id: groupId, name: "Weekend trip", description: nil,
                                    netBalanceCents: -16_500, createdAt: "2026-01-01", members: members)

    /// The group reads behind the settle-up sheet, answered locally. The debt never clears,
    /// so every opening owes it again.
    static let settleUpGroup = GroupDataSource(
        group: { _ in settleUpTrip },
        expenses: { _ in [] },
        summary: { _ in
            GroupBalanceSummary(
                simplifiedDebts: [SimplifiedDebt(from: settleUpDebt.from, to: settleUpDebt.to,
                                                 amountCents: settleUpDebt.amountCents)],
                balancesPending: false
            )
        },
        requestBalanceRefresh: { _ in },
        deleteExpense: { _, _, _ in throw ReviewOnly() },
        deletePayment: { _, _ in throw ReviewOnly() }
    )

    /// Recording waits like a request would, then succeeds without writing anything.
    static let settleUp = SettleUpDataSource(
        create: { _, _, _, _ in try await Task.sleep(for: .milliseconds(600)) },
        update: { _, _, _, _ in try await Task.sleep(for: .milliseconds(600)) }
    )

    struct ReviewOnly: LocalizedError {
        var errorDescription: String? { "Preview only. Nothing was saved." }
    }

    private final class AttemptCounter {
        var count = 0
    }

    private static func spend(_ expenses: [Expense], cents: (Expense) -> Int) -> SpendStats {
        let byCategory = Dictionary(grouping: expenses.filter { cents($0) > 0 }, by: \.category)
        let categories = byCategory.map { category, rows in
            CategoryStats(
                category: category,
                totalCents: rows.reduce(0) { $0 + cents($1) },
                expenseCount: rows.count,
                top: rows
                    .sorted { cents($0) > cents($1) }
                    .prefix(5)
                    .map { TopExpense(expenseId: $0.id, description: $0.description, date: $0.date ?? $0.createdAt, amountCents: cents($0)) }
            )
        }
        .sorted { $0.totalCents > $1.totalCents }

        return SpendStats(
            totalCents: categories.reduce(0) { $0 + $1.totalCents },
            expenseCount: categories.reduce(0) { $0 + $1.expenseCount },
            categories: categories
        )
    }

    private static func localDate(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func day(_ daysAgo: Int, from now: Date, calendar: Calendar) -> String {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: noon) ?? noon
        return date.formatted(.iso8601)
    }

    private static func expense(
        id: Int,
        date: String,
        description: String,
        category: ExpenseCategory,
        payer: User,
        amount: Double,
        shares: [Int: Double],
        type: ExpenseType = .expense,
        recurring: ExpenseRepeat? = nil,
        installment: ExpenseInstallment? = nil
    ) -> Expense {
        let people = users + [user(9, MemberDisplay.tombstoneName)]
        let splits = shares.sorted { $0.key < $1.key }.enumerated().map { index, share in
            ExpenseSplit(
                id: id * 10 + index,
                expenseId: id,
                userId: share.key,
                amount: share.value,
                percentage: nil,
                user: people.first { $0.id == share.key } ?? user(share.key, "Member \(share.key)")
            )
        }
        return Expense(
            id: id,
            groupId: groupId,
            paidBy: payer.id,
            amount: amount,
            description: description,
            type: type,
            category: category,
            splitMode: type == .expense ? .custom : nil,
            date: date,
            createdAt: date,
            updatedAt: date,
            paidByUser: payer,
            splits: splits,
            recurringExpenseId: recurring == nil ? nil : 1,
            repeatFrequency: recurring,
            installment: installment
        )
    }

    private static func user(_ id: Int, _ name: String) -> User {
        User(
            id: id,
            name: name,
            email: "\(name.lowercased())@example.com",
            createdAt: "2026-01-01T12:00:00Z",
            updatedAt: "2026-01-01T12:00:00Z"
        )
    }
}

/// The group timeline's rows, swipe and bar on sample data, laid out the way the app
/// stacks them so the last row's clearance above the add button is the real one.
/// Deleting removes the row from this screen only; Reset brings every row back.
struct ReviewTimelineView: View {
    @Environment(\.currency) private var currency
    let onDone: () -> Void

    @State private var expenses = ReviewSamples.timeline()
    @State private var pendingDeletion: Expense?
    @State private var selectedTab: AppTab = .group
    @State private var showingAddInfo = false

    var body: some View {
        AppTabView(selection: $selectedTab) { tab in
            if tab == .group {
                timeline
            } else {
                Color("background").ignoresSafeArea()
            }
        }
        .background(Color("background").ignoresSafeArea())
        // The group screen's question, answered locally, with the same animated removal,
        // so the row leaves the same way.
        .alert(
            deletionTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { expense in
            if expense.isRecurring {
                Button(role: .destructive) { remove(expense) } label: { Text(L10n.Repeat.deleteOnlyThis) }
                Button(role: .destructive) { remove(expense) } label: { Text(L10n.Repeat.deleteThisAndFollowing) }
            } else {
                Button(role: .destructive) { remove(expense) } label: { Text(L10n.Common.delete) }
            }
            Button(role: .cancel) { pendingDeletion = nil } label: { Text(L10n.Common.cancel) }
        } message: { expense in
            Text(expense.isRecurring ? L10n.Repeat.deleteMessage : L10n.Group.deleteUndone)
        }
        .alert("Preview only", isPresented: $showingAddInfo) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text("Review the expense form from its own entry in the gallery.")
        }
    }

    private var timeline: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Expense.groupExpensesByDate(expenses)) { day in
                        TimelineDateHeader(title: day.dateString)
                        ForEach(day.expenses) { expense in
                            SwipeToDeleteRow {
                            } onDelete: {
                                pendingDeletion = expense
                            } content: {
                                ExpenseRow(expense: expense, currentUserId: ReviewSamples.currentUserId)
                            }
                        }
                    }
                }
                .background(Color("card"))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 28,
                        topTrailingRadius: 28,
                        style: .continuous
                    )
                )
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Color("background"))
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { expenses = ReviewSamples.timeline() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done, action: onDone)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    AddExpenseButton { showingAddInfo = true }
                }
            }
        }
    }

    private var deletionTitle: String {
        guard let expense = pendingDeletion else { return L10n.Group.deleteQuestion }
        return expense.type == .payment
            ? L10n.Group.deletePayment(Money.formatted(amount: expense.amount, currency: currency))
            : L10n.Group.deleteExpense(expense.description)
    }

    private func remove(_ expense: Expense) {
        pendingDeletion = nil
        withAnimation(.snappy) {
            expenses.removeAll { $0.id == expense.id }
        }
    }
}

/// The Plans screen under the group screen's toggle, on sample data. Pull to refresh
/// reloads it; opening a row says where it would go.
struct ReviewPlansView: View {
    let onDone: () -> Void

    @StateObject private var viewModel: PlansViewModel
    @State private var opened: RecurringPlan?

    init(plans: [RecurringPlan], onDone: @escaping () -> Void) {
        self.onDone = onDone
        _viewModel = StateObject(wrappedValue: PlansViewModel(
            groupId: ReviewSamples.groupId,
            dataSource: ReviewSamples.plansSource(plans)
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                PlansView(viewModel: viewModel) { opened = $0 }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            }
            .refreshable { await viewModel.load() }
            .background(Color("background"))
            .navigationTitle(L10n.Plans.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done, action: onDone)
                }
            }
        }
        .alert("Preview only", isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text("In the app this opens the newest expense of \(opened?.description ?? "").")
        }
    }
}

/// Presents a sheet over a plain screen, the way the app presents it, and offers it
/// again once dismissed so the dismissal and a fresh opening can both be reviewed.
/// The real settle-up sheet on `ReviewSamples.settleUpDebt`: recording the whole amount
/// plays the settled-up moment, a smaller one dismisses as usual.
struct ReviewSettleUpSheet: View {
    @StateObject private var session = GroupSession(
        groupId: ReviewSamples.groupId,
        seed: ReviewSamples.settleUpTrip,
        dataSource: ReviewSamples.settleUpGroup
    )

    var body: some View {
        SettleUpSheet(
            session: session,
            currentUserId: ReviewSamples.currentUserId,
            preselectedRow: ReviewSamples.settleUpDebt,
            dataSource: ReviewSamples.settleUp
        )
        .task { await session.appear().value }
    }
}

struct ReviewSheetHost<Sheet: View>: View {
    let title: String
    let onDone: () -> Void
    @ViewBuilder let sheet: () -> Sheet

    @State private var isPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color("foreground"))
                Button("Open again") { isPresented = true }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("background").ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done, action: onDone)
                }
            }
        }
        .sheet(isPresented: $isPresented, content: sheet)
        .task { isPresented = true }
    }
}
