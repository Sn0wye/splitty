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
    @State private var isTitleCollapsed = false

    /// Roughly the height of the in-list title, as on a group's screen.
    private let titleCollapseOffset: CGFloat = 52

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    header

                    if let groupNotice = appState.groupNotice {
                        Text(groupNotice)
                            .font(.subheadline)
                            .foregroundStyle(Color("foreground"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color("muted"), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 20)
                    }

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
                            GroupCard(group: group, liveBalance: appState.groupSessions.liveBalance(for: group.id)) {
                                appState.openGroup(group.id, seed: group)
                            }
                        }

                        groupActions
                    }
                }
            }
            .accessibilityIdentifier("groups.scroll")
            .performanceScrollSignpost(.groupsScroll)
            .refreshable {
                if !isReview { await viewModel.loadGroups() }
            }
            // Same as a group's screen: the title scrolls with the list, and the bar picks
            // it up as it leaves.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > titleCollapseOffset
            } action: { _, collapsed in
                guard collapsed != isTitleCollapsed else { return }
                withAnimation(.easeInOut(duration: 0.2)) { isTitleCollapsed = collapsed }
            }
            .background(Color("background").ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color("background"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.Groups.title)
                        .font(.headline)
                        .foregroundColor(Color("foreground"))
                        .opacity(isTitleCollapsed ? 1 : 0)
                }

                if isReview {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.Common.done) { onReviewDone?() }
                    }
                } else {
                    // An avatar in the corner reads as "your account" everywhere else on
                    // the phone, so it goes there rather than sitting inert.
                    if let user = authManager.currentUser {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                appState.selectedTab = .settings
                            } label: {
                                MemberAvatar(display: MemberDisplay(user), size: 32)
                            }
                            .buttonStyle(.pressable(scale: 0.92))
                            .accessibilityLabel(L10n.Settings.account)
                        }
                        .hidingSharedBackground()
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
                        appState.openGroup(group.id, seed: group)
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.Groups.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Color("foreground"))

            if let overallBalanceCents = viewModel.overallBalanceCents {
                Text(BalanceCopy.overall(cents: overallBalanceCents))
                    .foregroundColor(Color("muted-foreground"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    /// Where a new group comes from, at the end of the list rather than as a second "+"
    /// in the bar: the coral one already means "add an expense". The empty list's own
    /// invitation, a size down, minus the headline: someone with groups has started.
    private var groupActions: some View {
        VStack(spacing: 14) {
            BrandBadge(symbol: "person.2", size: 48)

            Text(L10n.Onboarding.emptyGroupsDetail)
                .font(.subheadline)
                .foregroundStyle(Color("muted-foreground"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                PrimaryButton(title: L10n.Onboarding.createGroup) { showingCreateSheet = true }
                OnboardingSecondaryButton(title: L10n.Groups.joinWithCode) { showingJoinSheet = true }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 32)
        .padding(.bottom, 20)
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
        EmptyStateView(
            symbol: "person.2",
            title: L10n.Onboarding.emptyGroupsTitle,
            detail: L10n.Onboarding.emptyGroupsDetail
        ) {
            PrimaryButton(title: L10n.Onboarding.createGroup, action: onCreate)
            OnboardingSecondaryButton(title: L10n.Groups.joinWithCode, action: onJoin)
        }
    }
}

private extension ToolbarContent {
    /// The avatar is its own circle; the bar's glass capsule around it would be a second one.
    @ToolbarContentBuilder
    func hidingSharedBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

#Preview {
    GroupsView()
        .environmentObject(AppState())
}
