//
//  GroupView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct GroupView: View {
    let groupId: Int
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = GroupViewModel()
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var isTitleCollapsed = false
    @State private var showingSettings = false
    @State private var showingSettleUpSheet = false
    @State private var showingBalancesSheet = false
    @State private var pendingDeletion: Expense?
    @State private var selectedExpenseId: Int?

    /// Roughly the height of the in-list title, so the toolbar picks the name up
    /// as the header leaves rather than while it is still readable.
    private let titleCollapseOffset: CGFloat = 52

    var body: some View {
        NavigationStack {
            groupScreen
        }
    }

    private var groupScreen: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView { Text(L10n.Common.loading) }
                    .foregroundColor(Color("foreground"))
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The background ignores the safe area, the stack does not: otherwise the
        // floating button anchors below the tab bar instead of above it.
        .background(Color("background").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // Without this the bar is a material: rows scrolling under it stay visible
        // as a smear behind the status bar.
        .toolbarBackground(Color("background"), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    appState.selectedTab = .groups
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color("foreground"))
                }
                .accessibilityLabel(L10n.Group.backToGroups)
            }

            ToolbarItem(placement: .principal) {
                Text(viewModel.group?.name ?? "")
                    .font(.headline)
                    .foregroundColor(Color("foreground"))
                    .opacity(isTitleCollapsed ? 1 : 0)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(Color("foreground"))
                }
                .disabled(viewModel.group == nil || currentUserId == nil)
                .accessibilityLabel(L10n.Group.settings)
            }
        }
        .navigationDestination(isPresented: $showingSettings) {
            if let group = viewModel.group, let currentUserId {
                GroupSettingsView(
                    group: group,
                    currentUserId: currentUserId,
                    onGroupSaved: {
                        viewModel.beginRefresh(groupId: groupId)
                    },
                    onGroupUnavailable: { message in
                        appState.leaveUnavailableGroup(message: message)
                    },
                    onGroupExited: { message in
                        appState.exitGroup(groupId, message: message)
                    }
                )
            }
        }
        .sheet(isPresented: $showingSettleUpSheet) {
            if let currentUserId {
                SettleUpSheet(
                    groupId: groupId,
                    members: viewModel.members,
                    currentUserId: currentUserId
                ) { result in
                    insertPendingPayment(from: result, currentUserId: currentUserId)
                }
            }
        }
        .sheet(isPresented: $showingBalancesSheet) {
            if let group = viewModel.group, let currentUserId {
                BalancesView(
                    context: BalanceSheetContext(
                        groupId: groupId,
                        initialNetCents: group.netBalanceCents,
                        balancesPending: viewModel.balancesPending
                    ),
                    currentUserId: currentUserId,
                    members: viewModel.members
                ) { result in
                    insertPendingPayment(from: result, currentUserId: currentUserId)
                }
            }
        }
        // A money write enqueues a recomputation, so the header balance is stale on return.
        // Saved sheets start a refetch and bounded polling; backing out starts neither.
        .onChange(of: showingSettleUpSheet) { _, isPresented in
            if !isPresented {
                viewModel.refreshAfterSheetDismissal(groupId: groupId)
            }
        }
        .onChange(of: showingBalancesSheet) { _, isPresented in
            if !isPresented {
                viewModel.refreshAfterSheetDismissal(groupId: groupId)
            }
        }
        // An alert, not a confirmation dialog: deleting is destructive and irreversible,
        // and the question is worth a modal that names what it is about.
        .alert(
            deletionTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { expense in
            Button(role: .destructive) {
                pendingDeletion = nil
                Task { await viewModel.delete(expense, groupId: groupId) }
            } label: { Text(L10n.Common.delete) }
            Button(role: .cancel) { pendingDeletion = nil } label: { Text(L10n.Common.cancel) }
        } message: { _ in
            Text(L10n.Group.deleteUndone)
        }
        .task {
            await viewModel.loadGroupData(groupId: groupId)
        }
        .onChange(of: appState.savedExpense?.id) { _, _ in
            guard let event = appState.savedExpense, event.groupId == groupId else { return }
            viewModel.insert(event.expense)
            viewModel.refreshAfterSheetDismissal(groupId: groupId)
        }
        .onDisappear {
            viewModel.cancelRefresh()
        }
    }

    private var currentUserId: Int? { authManager.currentUser?.id }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                headerSection
                actionButtonsSection

                if let actionErrorMessage = viewModel.actionErrorMessage {
                    Text(actionErrorMessage)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }

                timeline
            }
        }
        .background(Color("background"))
        .accessibilityIdentifier("group.timeline")
        .performanceScrollSignpost(.timelineScroll)
        .refreshable {
            await viewModel.refresh(groupId: groupId)
        }
        // The title lives in the scroll content, so the toolbar picks it up as it leaves.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > titleCollapseOffset
        } action: { _, collapsed in
            guard collapsed != isTitleCollapsed else { return }
            withAnimation(.easeInOut(duration: 0.2)) { isTitleCollapsed = collapsed }
        }
        .navigationDestination(item: $selectedExpenseId) { expenseId in
            if let currentUserId {
                detail(for: expenseId, currentUserId: currentUserId)
            }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if !viewModel.errorMessage.isEmpty {
            Text(L10n.Group.error(viewModel.errorMessage))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color("card"))
        } else if viewModel.expenses.isEmpty {
            Text(L10n.Group.noExpenses)
                .foregroundColor(Color("muted-foreground"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color("card"))
        } else {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.groupedExpenses) { groupedExpense in
                    dateHeader(for: groupedExpense)
                    ForEach(groupedExpense.expenses) { expense in
                        expenseRow(expense)
                    }
                }
            }
            .background(Color("card"))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    topTrailingRadius: 28,
                    style: .continuous
                )
            )
        }
    }

    @ViewBuilder
    private func expenseRow(_ expense: Expense) -> some View {
        if let currentUserId {
            expenseRow(expense, currentUserId: currentUserId)
        }
    }

    /// A tap rather than a `NavigationLink`: a link in a list draws a disclosure chevron,
    /// and these rows already say where they go. Any member may delete anything,
    /// including a settlement someone else recorded — membership is the only authorization
    /// boundary in the system.
    @ViewBuilder
    private func expenseRow(_ expense: Expense, currentUserId: Int) -> some View {
        if viewModel.isPendingPayment(expense) {
            ExpenseRow(expense: expense, currentUserId: currentUserId)
                .opacity(0.6)
                .accessibilityValue(L10n.Common.updating)
        } else {
            SwipeToDeleteRow {
                selectedExpenseId = expense.id
            } onDelete: {
                pendingDeletion = expense
            } content: {
                ExpenseRow(expense: expense, currentUserId: currentUserId)
            }
        }
    }

    @ViewBuilder
    private func detail(for expenseId: Int, currentUserId: Int) -> some View {
        if let expense = viewModel.expenses.first(where: { $0.id == expenseId }) {
            switch expense.type {
            case .expense:
                ExpenseDetailView(
                    expense: expense,
                    members: viewModel.members,
                    currentUserId: currentUserId,
                    onChanged: { viewModel.beginRefresh(groupId: groupId) },
                    onDeleted: { viewModel.beginRefresh(groupId: groupId) }
                )
            case .payment:
                SettlementDetailView(
                    settlement: expense,
                    members: viewModel.members,
                    currentUserId: currentUserId,
                    onChanged: { viewModel.beginRefresh(groupId: groupId) },
                    onDeleted: { viewModel.beginRefresh(groupId: groupId) }
                )
            }
        }
    }

    private var deletionTitle: String {
        guard let expense = pendingDeletion else { return L10n.Group.deleteQuestion }
        return expense.type == .payment
            ? L10n.Group.deletePayment(Money.formatted(amount: expense.amount))
            : L10n.Group.deleteExpense(expense.description)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.group?.name ?? L10n.Common.loading)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Color("foreground"))

            if let group = viewModel.group {
                Button {
                    showingSettings = true
                } label: {
                    MultipleAvatar(
                        urls: group.members.compactMap { URL(string: $0.avatarUrl) },
                        total: group.members.count
                    )
                }
                .buttonStyle(.pressable(scale: 0.96))
                .accessibilityHint(L10n.Group.settingsHint)
                .padding(.vertical, 6)
            }

            balanceText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    @ViewBuilder
    private var balanceText: some View {
        if let balanceCents = viewModel.group?.netBalanceCents {
            HStack(spacing: 6) {
                Text(BalanceCopy.overall(cents: balanceCents))
                // A recomputation is outstanding, so this number predates the last write.
                // Greyed with a spinner rather than presented as final.
                .foregroundColor(Color("muted-foreground"))
                .opacity(viewModel.balancesPending ? 0.5 : 1)

                if viewModel.balancesPending {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        } else {
            Text(L10n.Group.loadingBalance)
                .foregroundColor(Color("muted-foreground"))
        }
    }
    
    private var actionButtonsSection: some View {
        LazyHStack(spacing: 12) {
            if viewModel.members.count >= 2 {
                ActionButton(title: L10n.Group.settleUp, color: Color("foreground"), textColor: Color("background")) {
                    showingSettleUpSheet = true
                }
                .disabled(currentUserId == nil)
            }

            ActionButton(title: L10n.Group.charts, color: Color("muted"), textColor: Color("foreground")) {
                // TODO: Charts action
            }
            
            ActionButton(title: L10n.Group.balances, color: Color("muted"), textColor: Color("foreground")) {
                showingBalancesSheet = true
            }
            .disabled(viewModel.group == nil || currentUserId == nil)
            
            ActionButton(title: L10n.Group.export, color: Color("muted"), textColor: Color("foreground")) {
                // TODO: Export action
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
    
    /// A settlement sheet that saved anything owes the screen a refresh, including an
    /// edit of a row already on screen — which fabricates no new row to insert.
    private func insertPendingPayment(from result: SettleUpResult, currentUserId: Int) {
        viewModel.noteSheetWrite()

        guard !result.isEditing,
              let currentUser = viewModel.members.first(where: { $0.userId == currentUserId })
        else { return }

        viewModel.insertPendingPayment(
            groupId: groupId,
            currentUser: currentUser,
            peer: result.peer,
            amountCents: result.amountCents,
            date: result.date
        )
    }

    private func dateHeader(for groupedExpense: GroupedExpense) -> some View {
        Text(groupedExpense.dateString)
            .font(.title2.weight(.semibold))
            .foregroundColor(Color("card-foreground"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)
            .background(Color("card"))
    }
}

struct ActionButton: View {
    let title: String
    let color: Color
    let textColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(textColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(color)
                .cornerRadius(20)
        }
        .buttonStyle(.pressable(scale: 0.94))
    }
}

struct ExpenseRow: View {
    let expense: Expense
    let currentUserId: Int
    
    var body: some View {
        HStack(spacing: 16) {
            leadingIcon
            
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.description)
                    .font(.headline)
                    .foregroundColor(Color("card-foreground"))
                
                paymentText
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                balanceLabel
                balanceAmount
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color("card"))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color("border")),
            alignment: .bottom
        )
    }
    
    private var categoryIcon: some View {
        ZStack {
            Circle()
                .fill(categoryColor)
                .frame(width: 40, height: 40)
            
            Image(systemName: categoryIconName)
                .font(.system(size: 18))
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let removedDisplay {
            MemberAvatar(display: removedDisplay)
        } else {
            categoryIcon
        }
    }
    
    private var categoryColor: Color {
        switch expense.type {
        case .expense: return .blue
        case .payment: return .green
        }
    }
    
    private var categoryIconName: String {
        switch expense.type {
        case .expense: return "dollarsign.circle.fill"
        case .payment: return "arrow.left.arrow.right"
        }
    }

    private var isUserPaid: Bool { expense.paidBy == currentUserId }

    private var isUserInvolved: Bool {
        isUserPaid || expense.splits.contains { $0.userId == currentUserId }
    }

    private var paidByDisplay: MemberDisplay {
        MemberDisplay(expense.paidByUser)
    }

    private var peerDisplay: MemberDisplay? {
        expense.peer.map(MemberDisplay.init)
    }

    private var removedDisplay: MemberDisplay? {
        if paidByDisplay.isRemoved { return paidByDisplay }
        if expense.type == .payment, let peerDisplay, peerDisplay.isRemoved { return peerDisplay }
        return nil
    }
    
    private var paymentText: some View {
        SwiftUI.Group {
            // Settlements live in the same timeline as expenses, in their own row style
            // rather than a separate feed.
            if expense.type == .payment {
                Text(isUserPaid ? L10n.Group.youPaidPeer(peerDisplay?.name ?? L10n.Common.someone) : L10n.Group.payerPaidPayee(paidByDisplay.name, payeeLabel))
            } else {
                Text(isUserPaid
                     ? L10n.Group.youPaidAmount(Money.formatted(amount: expense.amount))
                     : L10n.Group.payerPaidAmount(paidByDisplay.name, Money.formatted(amount: expense.amount)))
            }
        }
        .font(.subheadline)
        .foregroundColor(Color("muted-foreground"))
    }

    private var payeeLabel: String {
        expense.peer?.id == currentUserId ? L10n.Common.youLowercase : peerDisplay?.name ?? L10n.Common.someone
    }
    
    @ViewBuilder
    private var balanceLabel: some View {
        if expense.type == .payment {
            Text(L10n.Group.payment)
                .font(.caption)
                .foregroundColor(Color("muted-foreground"))
        } else if !isUserInvolved {
            Text(L10n.Group.notInvolved)
                .font(.caption)
                .foregroundColor(Color("muted-foreground"))
        } else {
            Text(isUserPaid ? L10n.Group.youLent : L10n.Group.youBorrowed)
                .font(.caption)
                .foregroundColor(isUserPaid ? Color.green : Color.red)
        }
    }
    
    @ViewBuilder
    private var balanceAmount: some View {
        if expense.type == .payment {
            Text(Money.formatted(amount: expense.amount))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(Color("card-foreground"))
        } else if isUserInvolved {
            // Signed: what the payer lent is the total less their own share, and what
            // anyone else borrowed is their share.
            Text(Money.formatted(amount: abs(expense.getUserSplit(currentUserId: currentUserId))))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(isUserPaid ? Color.green : Color.red)
        }
    }
}


#Preview {
    GroupView(groupId: 1)
        .environmentObject(AppState())
}
