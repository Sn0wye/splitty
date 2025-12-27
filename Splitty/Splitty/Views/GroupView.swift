//
//  GroupView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct GroupView: View {
    let groupId: Int
    @StateObject private var viewModel = GroupViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Black background to match app theme
                Color.black
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    ProgressView("Loading...")
                        .foregroundColor(.white)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Header Section
                            headerSection
                            
                            // Action Buttons
                            actionButtonsSection
                            
                            // Expenses List
                            expensesList
                        }
                    }
                    
                    // Floating Add Button
                    // VStack {
                    //     Spacer()
                    //     HStack {
                    //         Spacer()
                            
                    //         Button(action: {
                    //             // TODO: Add expense action
                    //         }) {
                    //             Image(systemName: "plus")
                    //                 .font(.title2)
                    //                 .fontWeight(.bold)
                    //                 .foregroundColor(.white)
                    //                 .frame(width: 56, height: 56)
                    //                 .background(
                    //                     Circle()
                    //                         .fill(Color.green)
                    //                         .shadow(radius: 4)
                    //                 )
                    //         }
                    //         .padding(.trailing, 20)
                    //         .padding(.bottom, 100) // Account for tab bar
                    //     }
                    // }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Groups")
                        }
                        .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        // TODO: Edit action
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            viewModel.loadGroupData(groupId: groupId)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Group avatar and name
            HStack(spacing: 16) {
                // Group avatar with member avatars
                ZStack {
                    MultipleAvatar(urls: viewModel.group?.members.compactMap { member in
                        return URL(string: member.avatarUrl)
                    } ?? [])
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.group?.name ?? "Loading...")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
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
            if balance > 0 {
                Text("You are owed $\(String(format: "%.2f", balance)) overall")
                    .foregroundColor(.white.opacity(0.9))
            } else if balance < 0 {
                Text("You owe $\(String(format: "%.2f", abs(balance))) overall")
                    .foregroundColor(.white.opacity(0.9))
            } else {
                Text("You are all settled up")
                    .foregroundColor(.white.opacity(0.9))
            }
        } else {
            Text("Loading balance...")
                .foregroundColor(.white.opacity(0.9))
        }
    }
    
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            ActionButton(title: "Settle up", color: .white, textColor: .black) {
                // TODO: Settle up action
            }
            
            ActionButton(title: "Remind...", color: .white.opacity(0.2), textColor: .white) {
                // TODO: Remind action
            }
            
            ActionButton(title: "Charts", color: .white.opacity(0.2), textColor: .white) {
                // TODO: Charts action
            }
            
            ActionButton(title: "Export", color: .white.opacity(0.2), textColor: .white) {
                // TODO: Export action
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
    
    private var expensesList: some View {
        VStack {
            if !viewModel.errorMessage.isEmpty {
                Text("Error: \(viewModel.errorMessage)")
                    .foregroundColor(.red)
                    .padding()
            } else if viewModel.expenses.isEmpty {
                Text("No expenses found (\(viewModel.expenses.count) total, \(viewModel.groupedExpenses.count) grouped)")
                    .padding()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.groupedExpenses, id: \.dateString) { groupedExpense in
                        VStack(spacing: 0) {
                            // Date header
                            dateHeader(for: groupedExpense)
                            
                            // Expenses for this date
                            ForEach(groupedExpense.expenses) { expense in
                                ExpenseRow(expense: expense)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.gray.opacity(0.2))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .padding(.top, 0)
    }
    
    private func dateHeader(for groupedExpense: GroupedExpense) -> some View {
        HStack {
            Text(groupedExpense.dateString)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text("Latest")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.2))
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
    }
}

struct ExpenseRow: View {
    let expense: Expense
    private let currentUserId = 4 // TODO: Get from AuthService
    
    var body: some View {
        HStack(spacing: 16) {
            // Category icon
            categoryIcon
            
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.description)
                    .font(.headline)
                    .foregroundColor(.primary)
                
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
        .background(Color.gray.opacity(0.2))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(.gray.opacity(0.3)),
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
        // Default colors since we don't have category in the new model
        switch expense.type {
        case .expense: return .blue
        case .payment: return .green
        }
    }
    
    private var categoryIconName: String {
        switch expense.type {
        case .expense: return "dollarsign.circle.fill"
        case .payment: return "arrow.down.circle.fill"
        }
    }
    
    private var paymentText: some View {
        let displayInfo = expense.getDisplayInfo(currentUserId: currentUserId)
        return Text(displayInfo.isUserPaid ? "You paid $\(String(format: "%.2f", expense.amount))" : "\(expense.paidByUser.name) paid $\(String(format: "%.2f", expense.amount))")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    
    private var balanceLabel: some View {
        let displayInfo = expense.getDisplayInfo(currentUserId: currentUserId)
        return Text(displayInfo.isUserPaid ? "you lent" : "you borrowed")
            .font(.caption)
            .foregroundColor(displayInfo.isUserPaid ? Color.green : Color.red)
    }
    
    private var balanceAmount: some View {
        let displayInfo = expense.getDisplayInfo(currentUserId: currentUserId)
        return Text("$\(String(format: "%.2f", abs(displayInfo.userSplit)))")
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(displayInfo.isUserPaid ? Color.green : Color.red)
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
}
