//
//  ChartsView.swift
//  Splitty
//

import SwiftUI
import Charts

/// What the group spent its money on, as group spend or as the caller's share: a donut per
/// category heading and the biggest expenses. Every number comes from the stats route.
struct ChartsView: View {
    let currentUserId: Int
    let members: [GroupMember]
    /// The group screen's loaded list, which a biggest expense opens from when it can.
    let expenses: [Expense]
    /// Without an expense there is nothing to chart, so the sheet asks for one instead.
    let hasExpenses: Bool
    /// Asks the group screen to open the expense form once this sheet is gone.
    let onAddExpense: () -> Void
    let onMoneyWrite: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: ChartsViewModel
    @State private var selectedExpenseId: Int?

    init(
        groupId: Int,
        currentUserId: Int,
        members: [GroupMember],
        expenses: [Expense],
        hasExpenses: Bool,
        onAddExpense: @escaping () -> Void,
        dataSource: ChartsDataSource = .live,
        onMoneyWrite: @escaping () -> Void
    ) {
        self.currentUserId = currentUserId
        self.members = members
        self.expenses = expenses
        self.hasExpenses = hasExpenses
        self.onAddExpense = onAddExpense
        self.onMoneyWrite = onMoneyWrite
        _viewModel = StateObject(wrappedValue: ChartsViewModel(groupId: groupId, dataSource: dataSource))
    }

    /// Reduce Motion keeps every change and drops the movement.
    private var motion: Animation? { reduceMotion ? nil : .snappy }

    /// Expense rows move into their new ranks when a range arrives.
    private var dataMotion: Animation { reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.25, extraBounce: 0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if hasExpenses {
                    VStack(alignment: .leading, spacing: 16) {
                        controls
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                } else {
                    EmptyStateView(
                        symbol: "chart.pie",
                        title: L10n.Charts.noExpensesTitle,
                        detail: L10n.Charts.noExpensesDetail
                    ) {
                        PrimaryButton(title: L10n.Tabs.addExpense) {
                            onAddExpense()
                            dismiss()
                        }
                    }
                }
            }
            .background(Color("background"))
            .navigationTitle(Text(L10n.Group.charts))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color("background"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text(L10n.Common.done) }
                }
            }
            .navigationDestination(item: $selectedExpenseId) { expenseId in
                ChartsExpenseDestination(
                    groupId: viewModel.groupId,
                    expenseId: expenseId,
                    currentUserId: currentUserId,
                    members: members,
                    expenses: expenses,
                    onMoneyWrite: completedMoneyWrite
                )
            }
            // The root reappears after every pushed detail; only a first load is owed then.
            .task(id: hasExpenses) {
                if hasExpenses, viewModel.state == .loading { await viewModel.load() }
            }
            .animation(motion, value: viewModel.lens)
            .animation(motion, value: viewModel.state)
            .animation(motion, value: viewModel.isUpdating)
            .animation(motion, value: viewModel.selectedHeading)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// The group screen owns the write's refresh; the charts refetch their own range.
    private func completedMoneyWrite() {
        onMoneyWrite()
        Task { await viewModel.load() }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker(
                selection: Binding(get: { viewModel.lens }, set: { viewModel.select($0) })
            ) {
                ForEach(ChartsLens.allCases) { lens in
                    Text(lens.title).tag(lens)
                }
            } label: {
                Text(L10n.Charts.lensLabel)
            }
            .pickerStyle(.segmented)

            Picker(
                selection: Binding(get: { viewModel.range }, set: { viewModel.select($0) })
            ) {
                ForEach(ChartsRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            } label: {
                Text(L10n.Charts.rangeLabel)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(L10n.Charts.loading)
                    .foregroundStyle(Color("muted-foreground"))
            }
            .frame(maxWidth: .infinity, minHeight: 220)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)

                Button {
                    Task { await viewModel.load() }
                } label: {
                    Text(L10n.Common.tryAgain)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 8)

        case .empty:
            ChartsCard(title: L10n.Charts.byCategory) { NothingInRange() }
            ChartsCard(title: L10n.Charts.biggestExpenses) { NothingInRange() }

        case .loaded:
            ChartsCard(title: L10n.Charts.byCategory) {
                HeadingDonut(viewModel: viewModel, motion: motion)
                    .frame(height: 220)
                HeadingLegend(viewModel: viewModel, motion: motion)
            }
            .opacity(updatingOpacity)

            if let heading = viewModel.selectedHeading {
                SelectionChip(heading: heading) {
                    withAnimation(motion) { viewModel.clearSelection() }
                }
                .transition(.opacity)
            }

            ChartsCard(title: L10n.Charts.biggestExpenses) {
                BiggestExpenses(rows: viewModel.topExpenses, motion: reduceMotion ? nil : dataMotion) {
                    selectedExpenseId = $0
                }
            }
            .opacity(updatingOpacity)
        }
    }

    /// The previous range's numbers stay in place, greyed, until the new ones land.
    private var updatingOpacity: Double { viewModel.isUpdating ? 0.5 : 1 }
}

// MARK: - By category

private struct HeadingDonut: View {
    @ObservedObject var viewModel: ChartsViewModel
    let motion: Animation?

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angleSelection: Int?
    @State private var chartSlices: [HeadingSlice]

    private let innerRadiusRatio = 0.62

    init(viewModel: ChartsViewModel, motion: Animation?) {
        self.viewModel = viewModel
        self.motion = motion
        _chartSlices = State(initialValue: viewModel.slices)
    }

    var body: some View {
        Chart(chartSlices) { slice in
            SectorMark(
                angle: .value(L10n.Charts.amount, slice.cents),
                innerRadius: .ratio(innerRadiusRatio),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(slice.heading.tint)
            .opacity(viewModel.selectedHeading == nil || viewModel.selectedHeading == slice.heading ? 1 : 0.35)
            .accessibilityLabel(slice.heading.title)
            .accessibilityValue(ChartsCopy.amountAndPercent(cents: slice.cents, fraction: slice.fraction, locale: locale))
        }
        .chartAngleSelection(value: $angleSelection)
        // Taps only, each one selecting afresh, so tapping the selected slice again clears
        // it however the default gesture would have held its value.
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { tap in
                guard isOnRing(tap.location, plotSize: proxy.plotSize) else { return }
                proxy.selectAngleValue(at: proxy.angle(at: tap.location))
            }
        }
        .chartBackground { _ in
            VStack(spacing: 2) {
                Text(Money.formatted(cents: viewModel.totalCents))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(motion, value: viewModel.totalCents)
                    .foregroundStyle(Color("card-foreground"))
                Text(L10n.Charts.expenseCount(viewModel.expenseCount))
                    .font(.caption)
                    .foregroundStyle(Color("muted-foreground"))
            }
            .accessibilityElement(children: .combine)
        }
        .onChange(of: angleSelection) { _, value in
            guard let value else { return }
            if let heading = viewModel.heading(atAngleValue: value) {
                withAnimation(motion) { viewModel.toggle(heading) }
            }
            angleSelection = nil
        }
        .onChange(of: viewModel.slices) { _, slices in
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1)) {
                chartSlices = slices
            }
        }
    }

    /// A tap in the hole is on the total, not on whichever slice shares its angle.
    private func isOnRing(_ location: CGPoint, plotSize: CGSize) -> Bool {
        let outerRadius = min(plotSize.width, plotSize.height) / 2
        let distance = hypot(location.x - plotSize.width / 2, location.y - plotSize.height / 2)
        return distance >= outerRadius * innerRadiusRatio && distance <= outerRadius
    }
}

private struct HeadingLegend: View {
    @ObservedObject var viewModel: ChartsViewModel
    let motion: Animation?

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.legend) { row in
                switch row.item {
                case .heading(let heading):
                    Button {
                        withAnimation(motion) { viewModel.toggle(heading) }
                    } label: {
                        headingRow(row, heading: heading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(heading.title)
                    .accessibilityValue(ChartsCopy.amountAndPercent(cents: row.cents, fraction: row.fraction, locale: locale))
                    .accessibilityHint(L10n.Charts.filterHint)
                    .accessibilityAddTraits(viewModel.selectedHeading == heading ? .isSelected : [])

                case .category(let category):
                    categoryRow(row, category: category)
                        .transition(.opacity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(category.name)
                        .accessibilityValue(ChartsCopy.amountAndPercent(cents: row.cents, fraction: row.fraction, locale: locale))
                }
            }
        }
    }

    private func headingRow(_ row: ChartsLegendRow, heading: ExpenseCategoryHeading) -> some View {
        let isSelected = viewModel.selectedHeading == heading
        return HStack(spacing: 10) {
            Circle()
                .fill(heading.tint)
                .frame(width: 10, height: 10)
            Text(heading.title)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(Color("card-foreground"))
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color("muted-foreground"))
                .rotationEffect(.degrees(isSelected ? 0 : -90))
            Spacer(minLength: 8)
            figures(row)
        }
        .font(.subheadline)
        .contentShape(Rectangle())
    }

    private func categoryRow(_ row: ChartsLegendRow, category: ExpenseCategory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.glyph)
                .font(.caption)
                .foregroundStyle(category.tint)
                .frame(width: 18)
            Text(category.name)
                .foregroundStyle(Color("muted-foreground"))
            Spacer(minLength: 8)
            figures(row)
        }
        .font(.footnote)
        .padding(.leading, 20)
    }

    private func figures(_ row: ChartsLegendRow) -> some View {
        HStack(spacing: 10) {
            Text(row.fraction, format: .percent.precision(.fractionLength(0)))
                .contentTransition(.numericText())
                .animation(motion, value: row.fraction)
                .foregroundStyle(Color("muted-foreground"))
            Text(Money.formatted(cents: row.cents))
                .contentTransition(.numericText())
                .animation(motion, value: row.cents)
                .foregroundStyle(Color("card-foreground"))
                .frame(minWidth: 80, alignment: .trailing)
        }
        .monospacedDigit()
    }
}

private struct SelectionChip: View {
    let heading: ExpenseCategoryHeading
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(heading.tint)
                .frame(width: 8, height: 8)
            Text(heading.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color("foreground"))
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color("muted-foreground"))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Charts.showAllCategories)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(Color("muted"), in: Capsule())
    }
}

// MARK: - Biggest expenses

private struct BiggestExpenses: View {
    let rows: [ChartsTopExpense]
    let motion: Animation?
    let onOpen: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button { onOpen(row.id) } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color("muted-foreground"))
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Image(systemName: row.category.glyph)
                            .foregroundStyle(row.category.tint)
                            .frame(width: 32, height: 32)
                            .background(row.category.tint.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.description)
                                .lineLimit(1)
                                .foregroundStyle(Color("card-foreground"))
                            if let date = row.date {
                                Text(date, format: .dateTime.day().month(.abbreviated).year())
                                    .font(.caption)
                                    .foregroundStyle(Color("muted-foreground"))
                            }
                        }
                        Spacer(minLength: 8)
                        Text(Money.formatted(cents: row.cents))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Color("card-foreground"))
                    }
                    .font(.subheadline)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        }
        .animation(motion, value: rows)
    }
}

/// Opens a biggest expense from the group's loaded list, reading it by id when the list
/// does not have it.
private struct ChartsExpenseDestination: View {
    let groupId: Int
    let expenseId: Int
    let currentUserId: Int
    let members: [GroupMember]
    let expenses: [Expense]
    let onMoneyWrite: () -> Void

    @State private var fetched: Expense?
    @State private var errorMessage: String?
    @State private var attempt = 0

    var body: some View {
        if let expense = expenses.first(where: { $0.id == expenseId }) ?? fetched {
            ExpenseDetailView(
                expense: expense,
                members: members,
                currentUserId: currentUserId,
                timelineExpenses: expenses,
                onChanged: onMoneyWrite,
                onDeleted: onMoneyWrite
            )
            // A delete refreshes the list before the pop lands; the row that just left it
            // stays on screen rather than being read again.
            .onAppear { fetched = expense }
        } else if let errorMessage {
            VStack(spacing: 12) {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button {
                    self.errorMessage = nil
                    attempt += 1
                } label: {
                    Text(L10n.Common.tryAgain)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        } else {
            ProgressView { Text(L10n.Common.loading) }
                .task(id: attempt) { await fetch() }
        }
    }

    private func fetch() async {
        do {
            fetched = try await ExpenseService.shared.getExpense(groupId: groupId, expenseId: expenseId)
        } catch {
            if !error.isCancellation { errorMessage = error.displayMessage }
        }
    }
}

// MARK: - Small pieces

private struct ChartsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color("card-foreground"))
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("card"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color("border")))
    }
}

private struct NothingInRange: View {
    var body: some View {
        Text(L10n.Charts.nothingInRange)
            .font(.subheadline)
            .foregroundStyle(Color("muted-foreground"))
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

private enum ChartsCopy {
    /// `$120.00, 40%` for VoiceOver.
    static func amountAndPercent(cents: Int, fraction: Double, locale: Locale) -> String {
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)).locale(locale))
        return L10n.Charts.amountAndPercent(Money.formatted(cents: cents), percent)
    }
}

extension ChartsLens {
    var title: String {
        switch self {
        case .group: L10n.Charts.lensGroup
        case .mine: L10n.Charts.lensMine
        }
    }
}

extension ChartsRange {
    var title: String {
        switch self {
        case .month: L10n.Charts.rangeMonth
        case .threeMonths: L10n.Charts.rangeThreeMonths
        case .year: L10n.Charts.rangeYear
        case .allTime: L10n.Charts.rangeAllTime
        }
    }
}

#Preview {
    let top = { (id: Int, description: String, cents: Int) in
        TopExpense(expenseId: id, description: description, date: "2026-09-12T19:00:00Z", amountCents: cents)
    }
    let group = SpendStats(totalCents: 1_034_500, expenseCount: 41, categories: [
        CategoryStats(category: .plane, totalCents: 248_000, expenseCount: 1, top: [top(1, "Flights to Lisbon", 248_000)]),
        CategoryStats(category: .hotel, totalCents: 186_500, expenseCount: 1, top: [top(2, "Airbnb Lisbon", 186_500)]),
        CategoryStats(category: .groceries, totalCents: 182_000, expenseCount: 14, top: [top(3, "Groceries", 17_800), top(4, "Groceries", 16_200)]),
        CategoryStats(category: .electricity, totalCents: 150_000, expenseCount: 6, top: [top(5, "Electricity", 31_000)]),
        CategoryStats(category: .diningOut, totalCents: 148_000, expenseCount: 10, top: [top(6, "Sushi", 25_400), top(7, "Pizza night", 13_200)]),
        CategoryStats(category: .movies, totalCents: 70_000, expenseCount: 5, top: [top(8, "Movie tickets", 8_800)]),
        CategoryStats(category: .general, totalCents: 50_000, expenseCount: 4, top: [top(9, "Misc", 5_600)])
    ])
    ChartsView(
        groupId: 1,
        currentUserId: 1,
        members: [],
        expenses: [],
        hasExpenses: true,
        onAddExpense: {},
        dataSource: ChartsDataSource(stats: { _, _ in GroupStats(group: group, mine: group) }),
        onMoneyWrite: {}
    )
}
