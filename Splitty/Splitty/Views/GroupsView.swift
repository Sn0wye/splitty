//
//  GroupsView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct GroupsView: View {
    @StateObject private var viewModel = GroupsViewModel()
    @State private var path: [Int] = []
    @State private var showingCreateSheet = false
    @State private var showingJoinSheet = false
    
    var body: some View {
        NavigationStack(path: $path) {
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
                            GroupCard(group: group)
                        }
                    }
                }
                .refreshable {
                    await viewModel.loadGroups()
                }
                
                Spacer()
            }
            .background(Color("background").ignoresSafeArea())
            .navigationDestination(for: Int.self) { groupId in
                GroupView(groupId: groupId)
            }
            .task {
                await viewModel.loadGroups()
            }
            .onChange(of: path) { _, newPath in
                // Coming back from a group picks up any edit made in there.
                if newPath.isEmpty {
                    Task { await viewModel.loadGroups() }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                GroupFormSheet { groupId in
                    Task {
                        await viewModel.loadGroups()
                        path.append(groupId)
                    }
                }
            }
            .sheet(isPresented: $showingJoinSheet) {
                JoinGroupSheet { group in
                    Task {
                        await viewModel.loadGroups()
                        path.append(group.id)
                    }
                }
            }
        }
    }
}

#Preview {
    GroupsView()
}
