import SwiftUI

/// A local design gallery. Every action here is a preview and leaves account data alone.
struct OnboardingReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScreen: ReviewScreen?
    @ObservedObject private var themeManager = ThemeManager.shared

    /// `opening` presents one screen straight away, for a launch that asks for it.
    init(opening screen: ReviewScreen? = nil) {
        _selectedScreen = State(initialValue: screen)
    }
    @State private var previewTab: AppTab = .groups
    @State private var peoplePreviewTab: AppTab = .people

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("These screens use sample content. Creating, joining, sharing, and saving are disabled in previews. A screen pushed from a component, like an expense's details, can still send a request, which the server refuses: sample group 0 does not exist.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("First run") {
                    row(.welcome)
                    row(.setup)
                    row(.create)
                    row(.join)
                }

                Section("In the app") {
                    row(.groupsEmpty)
                    row(.groupEmpty)
                    row(.peopleEmpty)
                    row(.invite)
                    row(.balanceHint)
                }

                Section {
                    row(.expenseForm)
                    row(.timeline)
                    row(.charts)
                    row(.chartsFailed)
                    row(.chartsEmpty)
                    row(.plans)
                    row(.plansEmpty)
                    row(.settleUp)
                    row(.settledUp)
                    row(.avatarCrop)
                    row(.appearance)
                } header: {
                    Text("Components")
                } footer: {
                    Text("The app's own components on sample data, for states that are hard to reach on an account: motion, gestures, sheets and the bar's add button.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("background"))
            .navigationTitle("Review onboarding")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $selectedScreen) { screen in
            preview(for: screen)
                .preferredColorScheme(themeManager.theme.colorScheme)
        }
        // A `-SplittyReview` launch replaces RootView, which applies the theme.
        // The cover sets it again: it does not follow a change made from inside it.
        .preferredColorScheme(themeManager.theme.colorScheme)
    }

    private func row(_ screen: ReviewScreen) -> some View {
        Button { selectedScreen = screen } label: {
            Label(screen.title, systemImage: screen.symbol)
                .foregroundStyle(Color("foreground"))
                .frame(minHeight: 44, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func preview(for screen: ReviewScreen) -> some View {
        switch screen {
        case .welcome, .setup:
            OnboardingView(isReview: true, startsWithChoices: screen == .setup) { _ in
                selectedScreen = nil
            }
        case .create:
            GroupFormSheet(isReview: true) { _ in }
        case .join:
            JoinGroupSheet(isReview: true) { _ in }
        case .invite:
            NavigationStack {
                InviteView(groupId: 0, groupName: "Weekend trip", isReview: true)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.Common.done) { selectedScreen = nil }
                        }
                    }
            }
        case .groupsEmpty:
            AppTabView(selection: $previewTab) { tab in
                if tab == .groups {
                    GroupsView(onAddExpense: {}, isReview: true) { selectedScreen = nil }
                        .environmentObject(AppState())
                } else {
                    Color("background").ignoresSafeArea()
                }
            }
        case .groupEmpty, .balanceHint:
            OnboardingGroupReviewView(showsBalanceHint: screen == .balanceHint) {
                selectedScreen = nil
            }
        case .peopleEmpty:
            AppTabView(selection: $peoplePreviewTab) { tab in
                if tab == .people {
                    PeopleView(
                        isReview: true,
                        onReviewDone: { selectedScreen = nil },
                        onShowGroups: { selectedScreen = .groupsEmpty }
                    )
                    .environmentObject(AppState())
                } else {
                    Color("background").ignoresSafeArea()
                }
            }
        case .expenseForm, .expenseFormReais:
            ReviewSheetHost(title: screen.title, onDone: { selectedScreen = nil }) {
                ExpenseSheet(
                    groupId: ReviewSamples.groupId,
                    currency: screen == .expenseFormReais ? .brl : .usd,
                    members: ReviewSamples.members,
                    currentUserId: ReviewSamples.currentUserId,
                    timelineExpenses: ReviewSamples.timeline(),
                    dataSource: ReviewSamples.expenseForm
                ) { _ in }
            }
        case .timeline:
            ReviewTimelineView { selectedScreen = nil }
        case .timelineEuros:
            ReviewTimelineView { selectedScreen = nil }
                .environment(\.currency, .eur)
        case .plans, .plansEmpty:
            ReviewPlansView(plans: screen == .plans ? ReviewSamples.plans : []) { selectedScreen = nil }
        case .settleUp:
            ReviewSheetHost(title: screen.title, onDone: { selectedScreen = nil }) {
                ReviewSettleUpSheet(startsFromBalanceRow: false)
            }
        case .settledUp:
            ReviewSheetHost(title: screen.title, onDone: { selectedScreen = nil }) {
                ReviewSettleUpSheet()
            }
        case .avatarCrop:
            AvatarCropView(
                image: ReviewSamples.avatarPhoto,
                onCancel: { selectedScreen = nil },
                onCrop: { _ in selectedScreen = nil }
            )
        case .appearance:
            // The real setting: picking a theme here changes the app's theme.
            NavigationStack {
                AppearanceView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.Common.done) { selectedScreen = nil }
                        }
                    }
            }
        case .charts, .chartsFailed, .chartsEmpty:
            ReviewSheetHost(title: screen.title, onDone: { selectedScreen = nil }) {
                let expenses = ReviewSamples.timeline()
                ChartsView(
                    groupId: ReviewSamples.groupId,
                    currentUserId: ReviewSamples.currentUserId,
                    members: ReviewSamples.members,
                    expenses: expenses,
                    hasExpenses: screen != .chartsEmpty,
                    onAddExpense: {},
                    dataSource: ReviewSamples.charts(
                        expenses: expenses,
                        failingFirstLoad: screen == .chartsFailed
                    )
                )
            }
        }
    }
}

/// `-SplittyReview` opens the gallery instead of the app, and `-SplittyReview <screen>`
/// opens one of its screens, so a UI review reaches the same state on every launch
/// without signing in or tapping through Settings.
struct ReviewLaunch: Equatable {
    static let argument = "-SplittyReview"

    /// Nil when the value names no screen; the gallery list opens instead.
    let screen: ReviewScreen?

    static var current: ReviewLaunch? { parse(ProcessInfo.processInfo.arguments) }

    static func parse(_ arguments: [String]) -> ReviewLaunch? {
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        let value = arguments.dropFirst(index + 1).first
        return ReviewLaunch(screen: value.flatMap(ReviewScreen.init(rawValue:)))
    }
}

/// Raw values are what `-SplittyReview` takes.
enum ReviewScreen: String, CaseIterable, Identifiable {
    case welcome
    case setup
    case create
    case join
    case invite
    case groupsEmpty
    case groupEmpty
    case peopleEmpty
    case balanceHint
    case expenseForm
    case expenseFormReais
    case timeline
    case timelineEuros
    case charts
    case chartsFailed
    case chartsEmpty
    case plans
    case plansEmpty
    case settleUp
    case settledUp
    case avatarCrop
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Walkthrough"
        case .setup: "Create or join"
        case .create: "Create group form"
        case .join: "Join group form"
        case .invite: "Invite people"
        case .groupsEmpty: "No groups"
        case .groupEmpty: "No expenses"
        case .peopleEmpty: "No people"
        case .balanceHint: "First balance"
        case .expenseForm: "Expense form"
        case .expenseFormReais: "Expense form, reais"
        case .timeline: "Timeline"
        case .timelineEuros: "Timeline, euros"
        case .charts: "Charts"
        case .chartsFailed: "Charts, first load fails"
        case .chartsEmpty: "Charts, no expenses"
        case .plans: "Plans"
        case .plansEmpty: "Plans, no installments"
        case .settleUp: "Settle up"
        case .settledUp: "Settled up"
        case .avatarCrop: "Avatar crop"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "sparkles.rectangle.stack"
        case .setup: "person.2"
        case .create: "plus.circle"
        case .join: "number.square"
        case .invite: "square.and.arrow.up"
        case .groupsEmpty: "square.grid.2x2"
        case .groupEmpty: "tray"
        case .peopleEmpty: "person.2"
        case .balanceHint: "arrow.left.arrow.right"
        case .expenseForm: "number"
        case .expenseFormReais: "brazilianrealsign"
        case .timeline: "list.bullet.rectangle"
        case .timelineEuros: "eurosign"
        case .charts: "chart.pie"
        case .chartsFailed: "exclamationmark.triangle"
        case .chartsEmpty: "chart.pie.fill"
        case .plans: "repeat"
        case .plansEmpty: "repeat.circle"
        case .settleUp: "person.crop.circle"
        case .settledUp: "checkmark.circle"
        case .avatarCrop: "crop"
        case .appearance: "circle.lefthalf.filled"
        }
    }
}

private struct OnboardingGroupReviewView: View {
    let showsBalanceHint: Bool
    let onDone: () -> Void

    @State private var showingInvite = false
    @State private var showingAddInfo = false
    @State private var selectedTab: AppTab = .group

    var body: some View {
        AppTabView(selection: $selectedTab) { tab in
            if tab == .group {
                groupScreen
            } else {
                Color("background").ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingInvite) {
            NavigationStack {
                InviteView(groupId: 0, groupName: "Weekend trip", isReview: true)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.Common.done) { showingInvite = false }
                        }
                    }
            }
        }
        .alert("Preview only", isPresented: $showingAddInfo) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text("Adding an expense here would change your account. This review uses sample content.")
        }
    }

    private var groupScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weekend trip")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color("foreground"))
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color("muted-foreground"))
                        Text(L10n.Balances.allSettled)
                            .font(.subheadline)
                            .foregroundStyle(Color("muted-foreground"))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    HStack(spacing: 12) {
                        ActionButton(
                            title: L10n.Group.balances,
                            color: Color("muted"),
                            textColor: Color("foreground"),
                            action: {}
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)

                    if showsBalanceHint {
                        VStack(spacing: 0) {
                            FirstBalanceTip()
                            sampleExpense
                        }
                        .background(Color("card"))
                    } else {
                        GroupEmptyState(
                            memberCount: 1,
                            onAddExpense: { showingAddInfo = true },
                            onInvite: { showingInvite = true }
                        )
                    }
                }
            }
            .background(Color("background").ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done, action: onDone)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    AddExpenseButton { showingAddInfo = true }
                }
            }
        }
    }

    private var sampleExpense: some View {
        HStack(spacing: 16) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color("category-food"), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Onboarding.exampleExpense)
                    .font(.headline)
                Text(L10n.Onboarding.examplePayer)
                    .font(.subheadline)
                    .foregroundStyle(Color("muted-foreground"))
            }
            Spacer()
            Text("$30.00")
                .font(.headline.monospacedDigit())
        }
        .foregroundStyle(Color("card-foreground"))
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
