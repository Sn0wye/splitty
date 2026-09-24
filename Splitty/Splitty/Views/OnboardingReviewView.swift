import SwiftUI

/// A local design gallery. Every action here is a preview and leaves account data alone.
struct OnboardingReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScreen: ReviewScreen?
    @State private var previewTab: AppTab = .groups
    @State private var peoplePreviewTab: AppTab = .people

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("These screens use sample content. Creating, joining, and sharing are disabled in previews.")
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
        }
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
            VStack(spacing: 0) {
                GroupsView(isReview: true) { selectedScreen = nil }
                    .environmentObject(AppState())
                BottomBar(
                    selection: $previewTab,
                    isAdding: false,
                    isAddEnabled: false,
                    onAdd: {}
                )
            }
            .background(Color("background").ignoresSafeArea())
        case .groupEmpty, .balanceHint:
            OnboardingGroupReviewView(showsBalanceHint: screen == .balanceHint) {
                selectedScreen = nil
            }
        case .peopleEmpty:
            VStack(spacing: 0) {
                PeopleView(isReview: true) { selectedScreen = nil }
                    .environmentObject(AppState())
                BottomBar(
                    selection: $peoplePreviewTab,
                    isAdding: false,
                    isAddEnabled: false,
                    onAdd: {}
                )
            }
            .background(Color("background").ignoresSafeArea())
        }
    }
}

private enum ReviewScreen: String, Identifiable {
    case welcome
    case setup
    case create
    case join
    case invite
    case groupsEmpty
    case groupEmpty
    case peopleEmpty
    case balanceHint

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
        VStack(spacing: 0) {
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
                            GroupEmptyState(memberCount: 1) { showingInvite = true }
                        }
                    }
                }
                .background(Color("background").ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.Common.done, action: onDone)
                    }
                }
            }

            BottomBar(
                selection: $selectedTab,
                isAdding: false,
                isAddEnabled: true
            ) { showingAddInfo = true }
        }
        .background(Color("background"))
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
