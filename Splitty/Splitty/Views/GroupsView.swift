//
//  GroupsView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct GroupsView: View {
    @StateObject private var viewModel = GroupsViewModel()
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
                        
                        Text("Overall, you are owed $320.43")
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
                    
                    Avatar()
                }
                .padding([.top, .horizontal])
                
                
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(viewModel.groups) { group in
                            GroupCard(group: group) {
                                appState.openGroup(group.id)
                            }
                        }
                    }
                }
                .refreshable {
                    await viewModel.loadGroups()
                }
                
                Spacer()
            }
            .background(Color("background").ignoresSafeArea())
            .task {
                await viewModel.loadGroups()
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
}

#Preview {
    GroupsView()
        .environmentObject(AppState())
}
