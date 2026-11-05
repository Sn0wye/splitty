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
    @StateObject private var peopleViewModel = PeopleViewModel(
        loadPeople: PerformanceScenarioLaunch.isEnabled ? { PerformanceScenarios.people } : GroupService.shared.getPeople
    )
    @State private var addDestination: AddExpenseDestination?
    @State private var isResolvingAdd = false
    @State private var addErrorMessage: String?

    var body: some View {
        AppTabView(selection: $appState.selectedTab) { tab in
            switch tab {
            case .groups:
                // "+" lives on a pushed group's screen and adds to that group.
                GroupsView(onAddGroupExpense: { Task { await beginAddingExpense() } })
            case .people:
                PeopleView(viewModel: peopleViewModel)
            case .settings:
                SettingsView()
            }
        }
        .background(Color("background").ignoresSafeArea())
        .environmentObject(appState)
        .sheet(item: $addDestination) { destination in
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
                            currency: group.currency,
                            members: group.members,
                            currentUserId: currentUserId,
                            dataSource: appState.groupSessions.outbox.map {
                                .queued(outbox: $0, members: group.members, currency: group.currency) { _ in nil }
                            } ?? .live
                        ) { write in
                            appState.groupSessions.report(write, groupId: group.id)
                        }
                    }
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

    private func beginAddingExpense() async {
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
            if let destination = try await appState.resolveAddExpenseDestination(fetchGroups: fetchGroups) {
                addDestination = destination
            } else {
                addErrorMessage = L10n.Errors.groupUnavailable
            }
        } catch where error.isCancellation {
            return
        } catch {
            addErrorMessage = error.displayMessage
        }
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
            currency: session.currency,
            members: group.members,
            currentUserId: currentUserId,
            timelineExpenses: session.expenses,
            dataSource: session.expenseFormDataSource(),
            onSaved: onSaved
        )
    }
}

extension AddExpenseDestination: Identifiable {
    var id: String {
        switch self {
        case .createGroup: "create-group"
        case .expense(let group): "expense-\(group.id)"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
