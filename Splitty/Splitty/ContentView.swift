//
//  ContentView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var peopleViewModel = PeopleViewModel()
    @State private var addDestination: AddExpenseDestination?
    @State private var pendingExpenseGroup: Group?
    @State private var isResolvingAdd = false
    @State private var addErrorMessage: String?
    // PROTOTYPE: glass navbar variants. See PrototypeGlassNavbar.swift.
    @State private var navbarVariant = PrototypeNavbarVariant.launch

    var body: some View {
        prototypeShell
            .overlay(alignment: .topLeading) {
                PrototypeNavbarSwitcher(variant: $navbarVariant)
                    .padding(.leading, 12)
                    .offset(y: -8)
            }
            .animation(.default, value: navbarVariant)
            .background(Color("background").ignoresSafeArea())
            .modifier(presentations)
            .environmentObject(appState)
    }

    @ViewBuilder
    private var prototypeShell: some View {
        if #available(iOS 26.0, *), navbarVariant == .b {
            PrototypeNativeTabShell(selection: $appState.selectedTab) { tab in
                switch tab {
                case .groups:
                    // From the list, "+" always asks which group.
                    GroupsView()
                        .environment(\.prototypeAddExpense, addAction(askForGroup: true))
                case .group:
                    CurrentGroupView {
                        Task { await beginAddingExpense() }
                    }
                    .environment(\.prototypeAddExpense, addAction(askForGroup: false))
                case .people: PeopleView(viewModel: peopleViewModel)
                case .settings: SettingsView()
                }
            }
        } else {
            currentShell
        }
    }

    private var tabContent: some View {
        ZStack {
            // Keep the list and its header alive while viewing a group. Recreating
            // the header on every tab switch flashes the avatar and add menu.
            GroupsView()
                .opacity(appState.selectedTab == .groups ? 1 : 0)
                .allowsHitTesting(appState.selectedTab == .groups)
                .accessibilityHidden(appState.selectedTab != .groups)

            switch appState.selectedTab {
            case .groups:
                EmptyView()
            case .group:
                CurrentGroupView {
                    Task { await beginAddingExpense() }
                }
            case .people:
                PeopleView(viewModel: peopleViewModel)
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentShell: some View {
        // A VStack, not a safeAreaInset: the inset never reaches scroll views inside a
        // NavigationStack, so lists would end under the bar. Stacked, the bar owns its
        // space and only overhangs the content by the strip beside the add button.
        VStack(spacing: 0) {
            tabContent
                // Rows scroll on under the overhang, but the last one still comes to rest
                // above the add button.
                .contentMargins(.bottom, BottomBar.overhang, for: .scrollContent)

            BottomBar(
                selection: $appState.selectedTab,
                isAdding: isResolvingAdd,
                isAddEnabled: authManager.currentUser != nil
            ) {
                Task { await beginAddingExpense() }
            }
            .padding(.top, -BottomBar.overhang)
        }
    }

    private var presentations: Presentations {
        Presentations(
            addDestination: $addDestination,
            pendingExpenseGroup: $pendingExpenseGroup,
            addErrorMessage: $addErrorMessage
        )
    }

    private func addAction(askForGroup: Bool) -> (() -> Void)? {
        guard authManager.currentUser != nil, !isResolvingAdd else { return nil }
        return { Task { await beginAddingExpense(askForGroup: askForGroup) } }
    }

    private func beginAddingExpense(askForGroup: Bool = false) async {
        guard authManager.currentUser != nil, !isResolvingAdd else { return }
        isResolvingAdd = true
        defer { isResolvingAdd = false }

        let fetchGroups: () async throws -> [Group] = {
            if PerformanceScenarioLaunch.isEnabled {
                PerformanceScenarios.groups
            } else {
                try await GroupService.shared.getGroups()
            }
        }
        do {
            addDestination = askForGroup
                ? .resolve(groups: try await fetchGroups(), currentGroupId: nil)
                : try await appState.resolveAddExpenseDestination(fetchGroups: fetchGroups)
        } catch where error.isCancellation {
            return
        } catch {
            addErrorMessage = error.displayMessage
        }
    }
}

// PROTOTYPE: the sheet and alert, lifted out of ContentView.body unchanged so the
// shell above can switch without retyping them.
private struct Presentations: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @StateObject private var authManager = AuthenticationManager.shared
    @Binding var addDestination: AddExpenseDestination?
    @Binding var pendingExpenseGroup: Group?
    @Binding var addErrorMessage: String?

    func body(content: Content) -> some View {
        content
        .sheet(item: $addDestination, onDismiss: continueAfterGroupChoice) { destination in
            switch destination {
            case .createGroup:
                GroupFormSheet { groupId in
                    appState.openGroup(groupId)
                }
            case .expense(let group):
                if let currentUserId = authManager.currentUser?.id {
                    if let session = appState.groupSessions.session(for: group.id) {
                        SessionExpenseSheet(
                            group: group,
                            currentUserId: currentUserId,
                            session: session
                        ) { write in
                            appState.groupSessions.report(write, groupId: group.id)
                        }
                    } else {
                        ExpenseSheet(
                            groupId: group.id,
                            members: group.members,
                            currentUserId: currentUserId
                        ) { write in
                            appState.groupSessions.report(write, groupId: group.id)
                        }
                    }
                }
            case .chooseGroup(let groups):
                ExpenseGroupPicker(groups: groups) { group in
                    pendingExpenseGroup = group
                    addDestination = nil
                }
            }
        }
        .alert(
            L10n.Groups.couldNotStartExpense,
            isPresented: Binding(
                get: { addErrorMessage != nil },
                set: { if !$0 { addErrorMessage = nil } }
            )
        ) {
            Button(role: .cancel) { addErrorMessage = nil } label: { Text(L10n.Common.ok) }
        } message: {
            Text(addErrorMessage ?? "")
        }
    }

    private func continueAfterGroupChoice() {
        guard let group = pendingExpenseGroup else { return }
        pendingExpenseGroup = nil
        addDestination = .expense(group)
    }
}

private struct SessionExpenseSheet: View {
    let group: Group
    let currentUserId: Int
    @ObservedObject var session: GroupSession
    let onSaved: (GroupMoneyWrite) -> Void

    var body: some View {
        ExpenseSheet(
            groupId: group.id,
            members: group.members,
            currentUserId: currentUserId,
            timelineExpenses: session.expenses,
            onSaved: onSaved
        )
    }
}

extension AddExpenseDestination: Identifiable {
    var id: String {
        switch self {
        case .createGroup: "create-group"
        case .expense(let group): "expense-\(group.id)"
        case .chooseGroup: "choose-group"
        }
    }
}

private struct ExpenseGroupPicker: View {
    let groups: [Group]
    let onSelect: (Group) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(groups) { group in
                Button {
                    onSelect(group)
                } label: {
                    HStack {
                        Text(group.name)
                            .foregroundStyle(Color("foreground"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color("muted-foreground"))
                    }
                    .contentShape(Rectangle())
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("background"))
            .navigationTitle(Text(L10n.Groups.choose))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(L10n.Common.cancel) }
                }
            }
        }
    }
}

/// The "Group" tab: renders whichever group was last opened.
private struct CurrentGroupView: View {
    @EnvironmentObject private var appState: AppState
    let onAddExpense: () -> Void

    var body: some View {
        if let session = appState.groupSessions.current {
            GroupView(session: session, onAddExpense: onAddExpense)
                .id(session.groupId)
        } else {
            VStack(spacing: 8) {
                BrandBadge(symbol: "person.2")
                    .padding(.bottom, 6)
                Text(L10n.Groups.noneSelected)
                    .font(.headline)
                Text(L10n.Groups.pickFromTab)
                    .font(.subheadline)
                    .foregroundColor(Color("muted-foreground"))
            }
            .foregroundColor(Color("foreground"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("background"))
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
