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
    @State private var showingEditSheet = false
    @State private var showingExpenseSheet = false
    @State private var pendingDeletion: Expense?
    @State private var selectedExpenseId: Int?

    private let addButtonSize: CGFloat = 56

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
                ProgressView("Loading...")
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
                .accessibilityLabel("Back to groups")
            }

            ToolbarItem(placement: .principal) {
                Text(viewModel.group?.name ?? "")
                    .font(.headline)
                    .foregroundColor(Color("foreground"))
                    .opacity(isTitleCollapsed ? 1 : 0)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingEditSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(Color("foreground"))
                }
                .disabled(viewModel.group == nil)
                .accessibilityLabel("Edit group")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            GroupFormSheet(group: viewModel.group) { _ in
                Task { await viewModel.loadGroupData(groupId: groupId) }
            }
        }
        .sheet(isPresented: $showingExpenseSheet) {
            if let currentUserId {
                ExpenseSheet(
                    groupId: groupId,
                    members: viewModel.members,
                    currentUserId: currentUserId
                ) { saved in
                    viewModel.insert(saved)
                }
            }
        }
        // A money write enqueues a recomputation, so the header balance is stale on return.
        // One refetch, no polling: the flag it reads exists for exactly this.
        .onChange(of: showingExpenseSheet) { _, isPresented in
            if !isPresented {
                Task { await viewModel.refresh(groupId: groupId) }
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
            Button("Delete", role: .destructive) {
                pendingDeletion = nil
                Task { await viewModel.delete(expense, groupId: groupId) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("This cannot be undone.")
        }
        .task {
            await viewModel.loadGroupData(groupId: groupId)
        }
    }

    private var currentUserId: Int? { authManager.currentUser?.id }

    private var content: some View {
        List {
            Section {
                VStack(spacing: 0) {
                    headerSection
                    actionButtonsSection
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color("background"))
                .listRowSeparator(.hidden)
            }

            if let actionErrorMessage = viewModel.actionErrorMessage {
                Section {
                    Text(actionErrorMessage)
                        .foregroundColor(.red)
                        .listRowBackground(Color("card"))
                }
            }

            if !viewModel.errorMessage.isEmpty {
                Section {
                    Text("Error: \(viewModel.errorMessage)")
                        .foregroundColor(.red)
                        .listRowBackground(Color("card"))
                }
            } else if viewModel.expenses.isEmpty {
                Section {
                    Text("No expenses yet. Add the first one.")
                        .foregroundColor(Color("muted-foreground"))
                        .listRowBackground(Color("card"))
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach(viewModel.groupedExpenses, id: \.dateString) { groupedExpense in
                    Section {
                        ForEach(groupedExpense.expenses) { expense in
                            expenseRow(expense)
                        }
                    } header: {
                        dateHeader(for: groupedExpense)
                    }
                }
            }

        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color("background"))
        // A list draws itself under the safe area, so a button stacked on top of one
        // anchors under the tab bar. As an inset it sits inside the safe area instead,
        // and the space it reserves is exactly what keeps the last row uncovered.
        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            addExpenseButton
        }
        // The title lives in the list, not in a large-title bar, so the handoff to the
        // toolbar is driven off the scroll position.
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
    private func expenseRow(_ expense: Expense) -> some View {
        if let currentUserId {
            expenseRow(expense, currentUserId: currentUserId)
        }
    }

    /// A tap rather than a `NavigationLink`: a link in a list draws a disclosure chevron,
    /// and these rows already say where they go. Any member may delete anything,
    /// including a settlement someone else recorded — membership is the only authorization
    /// boundary in the system.
    private func expenseRow(_ expense: Expense, currentUserId: Int) -> some View {
        SwipeToDeleteRow {
            selectedExpenseId = expense.id
        } onDelete: {
            pendingDeletion = expense
        } content: {
            ExpenseRow(expense: expense, currentUserId: currentUserId)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color("card"))
        .listRowSeparator(.hidden)
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
                    onChanged: { Task { await viewModel.refresh(groupId: groupId) } },
                    onDeleted: { Task { await viewModel.refresh(groupId: groupId) } }
                )
            case .payment:
                SettlementDetailView(
                    settlement: expense,
                    members: viewModel.members,
                    currentUserId: currentUserId,
                    onDeleted: { Task { await viewModel.refresh(groupId: groupId) } }
                )
            }
        }
    }

    private var deletionTitle: String {
        guard let expense = pendingDeletion else { return "Delete?" }
        return expense.type == .payment
            ? "Delete the \(Money.formatted(amount: expense.amount)) payment?"
            : "Delete \"\(expense.description)\"?"
    }

    private var addExpenseButton: some View {
        Button {
            showingExpenseSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Color("background"))
                .frame(width: addButtonSize, height: addButtonSize)
                .background(Color("foreground"))
                .clipShape(Circle())
                .shadow(radius: 8, y: 4)
        }
        // The deepest press in the app: a 56pt disc under a thumb has to move a visible
        // amount before the dip reads, and the shadow compressing with it sells the push.
        .buttonStyle(.pressable(scale: 0.9))
        .padding(.trailing, 20)
        .padding(.vertical, 16)
        .disabled(currentUserId == nil || viewModel.group == nil)
        .accessibilityIdentifier("group.addExpense")
        .accessibilityLabel("Add expense")
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    MultipleAvatar(urls: viewModel.group?.members.compactMap { member in
                        return URL(string: member.avatarUrl)
                    } ?? [])
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.group?.name ?? "Loading...")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(Color("foreground"))
                    
                    balanceText
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }
    
    @ViewBuilder
    private var balanceText: some View {
        if let balance = viewModel.group?.netBalance {
            HStack(spacing: 6) {
                SwiftUI.Group {
                    if balance > 0 {
                        Text("You are owed \(Money.formatted(amount: balance)) overall")
                    } else if balance < 0 {
                        Text("You owe \(Money.formatted(amount: abs(balance))) overall")
                    } else {
                        Text("You are all settled up")
                    }
                }
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
            Text("Loading balance...")
                .foregroundColor(Color("muted-foreground"))
        }
    }
    
    private var actionButtonsSection: some View {
        LazyHStack(spacing: 12) {
            ActionButton(title: "Settle up", color: Color("foreground"), textColor: Color("background")) {
                // TODO: Settle up action
            }
            
            ActionButton(title: "Charts", color: Color("muted"), textColor: Color("foreground")) {
                // TODO: Charts action
            }
            
            ActionButton(title: "Balances", color: Color("muted"), textColor: Color("foreground")) {
                // TODO: Balances action
            }
            
            ActionButton(title: "Export", color: Color("muted"), textColor: Color("foreground")) {
                // TODO: Export action
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
    
    private func dateHeader(for groupedExpense: GroupedExpense) -> some View {
        HStack {
            Text(groupedExpense.dateString)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(Color("card-foreground"))
            
            Spacer()
            
            Text("Latest")
                .font(.subheadline)
                .foregroundColor(Color("muted-foreground"))
            
            Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundColor(Color("muted-foreground"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color("card"))
        .listRowInsets(EdgeInsets())
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
            // Category icon
            categoryIcon
            
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

    private var peerName: String {
        expense.peer?.name ?? "someone"
    }
    
    private var paymentText: some View {
        SwiftUI.Group {
            // Settlements live in the same timeline as expenses, in their own row style
            // rather than a separate feed.
            if expense.type == .payment {
                Text(isUserPaid ? "You paid \(peerName)" : "\(expense.paidByUser.name) paid \(payeeLabel)")
            } else {
                Text(isUserPaid
                     ? "You paid \(Money.formatted(amount: expense.amount))"
                     : "\(expense.paidByUser.name) paid \(Money.formatted(amount: expense.amount))")
            }
        }
        .font(.subheadline)
        .foregroundColor(Color("muted-foreground"))
    }

    private var payeeLabel: String {
        expense.peer?.id == currentUserId ? "you" : peerName
    }
    
    @ViewBuilder
    private var balanceLabel: some View {
        if expense.type == .payment {
            Text("payment")
                .font(.caption)
                .foregroundColor(Color("muted-foreground"))
        } else {
            Text(isUserPaid ? "you lent" : "you borrowed")
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
        } else {
            // Signed: what the payer lent is the total less their own share, and what
            // anyone else borrowed is their share.
            Text(Money.formatted(amount: abs(expense.getUserSplit(currentUserId: currentUserId))))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(isUserPaid ? Color.green : Color.red)
        }
    }
}

// Extension to add corner radius to specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    GroupView(groupId: 1)
        .environmentObject(AppState())
}
