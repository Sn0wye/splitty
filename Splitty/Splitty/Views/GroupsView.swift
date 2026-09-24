//
//  GroupsView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct GroupsView: View {
    var isReview = false
    var onReviewDone: (() -> Void)?

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
                        Text(L10n.Groups.title)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        if let overallBalanceCents = viewModel.overallBalanceCents {
                            Text(BalanceCopy.overall(cents: overallBalanceCents))
                                .foregroundColor(Color("muted-foreground"))
                        }
                    }
                    
                    Spacer()
                    
                    Menu {
                        Button { showingCreateSheet = true } label: { Text(L10n.Groups.newGroup) }
                        Button { showingJoinSheet = true } label: { Text(L10n.Groups.joinWithCode) }
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
                        if let errorMessage = viewModel.errorMessage, viewModel.groups.isEmpty {
                            VStack(spacing: 16) {
                                Text(errorMessage)
                                    .foregroundStyle(Color("muted-foreground"))
                                    .multilineTextAlignment(.center)
                                Button(L10n.Common.tryAgain) {
                                    Task { await viewModel.loadGroups() }
                                }
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(28)
                        } else if !viewModel.isLoading && viewModel.groups.isEmpty {
                            GroupsEmptyState(
                                onCreate: { showingCreateSheet = true },
                                onJoin: { showingJoinSheet = true }
                            )
                        } else {
                            ForEach(viewModel.groups) { group in
                                GroupCard(group: group) {
                                    appState.openGroup(group.id)
                                }
                            }
                        }
                    }
                }
                .accessibilityIdentifier("groups.scroll")
                .performanceScrollSignpost(.groupsScroll)
                .refreshable {
                    if !isReview { await viewModel.loadGroups() }
                }
                
                Spacer()
            }
            .background(Color("background").ignoresSafeArea())
            .toolbar {
                if isReview {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.Common.done) { onReviewDone?() }
                    }
                }
            }
            .task {
                if !isReview { await viewModel.loadGroups() }
            }
            .onAppear {
                removeExitedGroup()
            }
            .onChange(of: appState.exitedGroupId) { _, _ in
                removeExitedGroup()
            }
            .onChange(of: appState.selectedTab) { _, newTab in
                // Coming back from a group picks up any edit made in there.
                if newTab == .groups && !isReview {
                    Task { await viewModel.loadGroups() }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                GroupFormSheet(isReview: isReview) { groupId in
                    Task {
                        await viewModel.loadGroups()
                        appState.openGroup(groupId)
                    }
                }
            }
            .sheet(isPresented: $showingJoinSheet) {
                JoinGroupSheet(isReview: isReview) { group in
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

struct GroupsEmptyState: View {
    let onCreate: () -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color("foreground"))
                .padding(.bottom, 6)

            Text(L10n.Onboarding.emptyGroupsTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color("foreground"))

            Text(L10n.Onboarding.emptyGroupsDetail)
                .font(.subheadline)
                .foregroundStyle(Color("muted-foreground"))
                .multilineTextAlignment(.center)

            PrimaryButton(title: L10n.Onboarding.createGroup, action: onCreate)
                .padding(.top, 8)

            OnboardingSecondaryButton(title: L10n.Groups.joinWithCode, action: onJoin)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 44)
    }
}

#Preview {
    GroupsView()
        .environmentObject(AppState())
}
