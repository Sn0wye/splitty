//
//  AppState.swift
//  Splitty
//

import SwiftUI

enum AppTab: Int {
    case groups
    case group
    case people
    case settings

    var title: String {
        switch self {
        case .groups: L10n.Tabs.groups
        case .group: L10n.Tabs.group
        case .people: L10n.Tabs.people
        case .settings: L10n.Tabs.settings
        }
    }

    var icon: String {
        switch self {
        case .groups: return "square.grid.2x2"
        case .group: return "person.2"
        case .people: return "arrow.left.arrow.right"
        case .settings: return "gearshape"
        }
    }
}

enum AddExpenseDestination: Equatable {
    case createGroup
    case expense(Group)
    case chooseGroup([Group])

    static func resolve(groups: [Group], currentGroupId: Int?) -> AddExpenseDestination {
        if let currentGroup = groups.first(where: { $0.id == currentGroupId }) {
            return .expense(currentGroup)
        }
        switch groups.count {
        case 0:
            return .createGroup
        case 1:
            return .expense(groups[0])
        default:
            return .chooseGroup(groups)
        }
    }

    static func == (lhs: AddExpenseDestination, rhs: AddExpenseDestination) -> Bool {
        switch (lhs, rhs) {
        case (.createGroup, .createGroup):
            true
        case (.expense(let lhsGroup), .expense(let rhsGroup)):
            lhsGroup.id == rhsGroup.id
        case (.chooseGroup(let lhsGroups), .chooseGroup(let rhsGroups)):
            lhsGroups.map(\.id) == rhsGroups.map(\.id)
        default:
            false
        }
    }
}

/// Shared navigation state: which tab is showing and which group the
/// "Group" tab is currently pointing at.
@MainActor
final class AppState: ObservableObject {
    private static let currentGroupKey = "currentGroupId"

    @Published var selectedTab: AppTab = .groups
    @Published var groupNotice: String?
    @Published private(set) var exitedGroupId: Int?
    @Published private(set) var savedExpense: SavedExpenseEvent?

    @Published var currentGroupId: Int? {
        didSet {
            if let id = currentGroupId {
                UserDefaults.standard.set(id, forKey: Self.currentGroupKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.currentGroupKey)
            }
        }
    }

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.currentGroupKey) as? Int
        currentGroupId = stored
    }

    func openGroup(_ id: Int) {
        groupNotice = nil
        exitedGroupId = nil
        currentGroupId = id
        selectedTab = .group
    }

    func leaveUnavailableGroup(message: String) {
        groupNotice = message
        currentGroupId = nil
        selectedTab = .groups
    }

    func exitGroup(_ id: Int, message: String? = nil) {
        groupNotice = message
        exitedGroupId = id
        currentGroupId = nil
        selectedTab = .groups
    }

    func recordSavedExpense(_ expense: Expense, groupId: Int) {
        savedExpense = SavedExpenseEvent(groupId: groupId, expense: expense)
    }
}

struct SavedExpenseEvent: Identifiable {
    let id = UUID()
    let groupId: Int
    let expense: Expense
}
