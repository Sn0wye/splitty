//
//  GroupsView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct GroupsView: View {
    @StateObject private var viewModel = GroupsViewModel()
    @StateObject private var authManager = AuthenticationManager.shared
    @EnvironmentObject private var appState: AppState
    @State private var showingCreateSheet = false
    @State private var showingJoinSheet = false
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {

                HStack {
                    VStack(alignment: .leading) {
                        Text("Groups")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        if let overallBalanceCents = viewModel.overallBalanceCents {
                            Text(BalanceCopy.overall(cents: overallBalanceCents))
                                .foregroundColor(Color("muted-foreground"))
                        }
                    }
                    
                    Spacer()
                    
                    Menu {
                        Button("New group") { showingCreateSheet = true }
                        Button("Join with code") { showingJoinSheet = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(Color("foreground"))
                    }
                    .padding(.trailing, 12)
                    
                    if let user = authManager.currentUser {
                        MemberAvatar(display: MemberDisplay(user))
                    }
                }
                .padding([.top, .horizontal])

                if let groupNotice = appState.groupNotice {
                    Text(groupNotice)
                        .font(.subheadline)
                        .foregroundStyle(Color("foreground"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color("muted"), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }
                
                
                ScrollView(.vertical) {
                    VStack(spacing: 10) {
                        ForEach(viewModel.groups) { group in
                            GroupCard(group: group) {
                                appState.openGroup(group.id)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("groups.scroll")
                .performanceScrollSignpost(.groupsScroll)
                .refreshable {
                    await viewModel.loadGroups()
                }
                
                Spacer()
            }
            .background(Color("background").ignoresSafeArea())
            .task {
                await viewModel.loadGroups()
            }
            .onAppear {
                removeExitedGroup()
            }
            .onChange(of: appState.exitedGroupId) { _, _ in
                removeExitedGroup()
            }
            .onChange(of: appState.selectedTab) { _, newTab in
                // Coming back from a group picks up any edit made in there.
                if newTab == .groups {
                    Task { await viewModel.loadGroups() }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                GroupFormSheet { groupId in
                    Task {
                        await viewModel.loadGroups()
                        appState.openGroup(groupId)
                    }
                }
            }
            .sheet(isPresented: $showingJoinSheet) {
                JoinGroupSheet { group in
                    Task {
                        await viewModel.loadGroups()
                        appState.openGroup(group.id)
                    }
                }
            }
        }
    }

    private func removeExitedGroup() {
        guard let exitedGroupId = appState.exitedGroupId else { return }
        viewModel.removeGroup(id: exitedGroupId)
    }
}

#Preview {
    GroupsView()
        .environmentObject(AppState())
}
