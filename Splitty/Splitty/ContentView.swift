//
//  ContentView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var addDestination: AddExpenseDestination?
    @State private var pendingExpenseGroup: Group?
    @State private var isResolvingAdd = false
    @State private var addErrorMessage: String?

    var body: some View {
        // A VStack, not a safeAreaInset: an inset is something content draws under,
        // and a list does exactly that, taking anything anchored to its bottom edge
        // (the add button) behind the bar with it. Stacked, the bar owns its space.
        VStack(spacing: 0) {
            ZStack {
                switch appState.selectedTab {
                case .groups:
                    GroupsView()
                case .group:
                    CurrentGroupView()
                case .people:
                    PeopleView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomBar(
                selection: $appState.selectedTab,
                isAdding: isResolvingAdd,
                isAddEnabled: authManager.currentUser != nil
            ) {
                Task { await beginAddingExpense() }
            }
        }
        .background(Color("background").ignoresSafeArea())
        .environmentObject(appState)
        .sheet(item: $addDestination, onDismiss: continueAfterGroupChoice) { destination in
            switch destination {
            case .createGroup:
                GroupFormSheet { groupId in
                    appState.openGroup(groupId)
                }
            case .expense(let group):
                if let currentUserId = authManager.currentUser?.id {
                    ExpenseSheet(
                        groupId: group.id,
                        members: group.members,
                        currentUserId: currentUserId
                    ) { saved in
                        appState.recordSavedExpense(saved, groupId: group.id)
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
            "Could not start an expense",
            isPresented: Binding(
                get: { addErrorMessage != nil },
                set: { if !$0 { addErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { addErrorMessage = nil }
        } message: {
            Text(addErrorMessage ?? "")
        }
    }

    private func beginAddingExpense() async {
        guard authManager.currentUser != nil, !isResolvingAdd else { return }
        isResolvingAdd = true
        defer { isResolvingAdd = false }

        do {
            let groups = if PerformanceScenarioLaunch.isEnabled {
                PerformanceScenarios.groups
            } else {
                try await GroupService.shared.getGroups()
            }
            addDestination = .resolve(groups: groups, currentGroupId: appState.currentGroupId)
        } catch where error.isCancellation {
            return
        } catch {
            addErrorMessage = error.displayMessage
        }
    }

    private func continueAfterGroupChoice() {
        guard let group = pendingExpenseGroup else { return }
        pendingExpenseGroup = nil
        addDestination = .expense(group)
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
            .navigationTitle("Choose a group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The "Group" tab: renders whichever group was last opened.
private struct CurrentGroupView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if let groupId = appState.currentGroupId {
            GroupView(groupId: groupId)
                .id(groupId)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.system(size: 32, weight: .light))
                Text("No group selected")
                    .font(.headline)
                Text("Pick a group from the Groups tab.")
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
}
