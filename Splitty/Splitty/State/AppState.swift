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
    private static func currentGroupKey(userId: Int) -> String { "currentGroupId.\(userId)" }

    @Published var selectedTab: AppTab = .groups
    @Published var groupNotice: String?
    @Published private(set) var exitedGroupId: Int?
    let groupSessions: GroupSessionStore
    @Published private(set) var signedInUserId: Int?

    @Published var currentGroupId: Int? {
        didSet {
            guard let signedInUserId else { return }
            let key = Self.currentGroupKey(userId: signedInUserId)
            if let id = currentGroupId { UserDefaults.standard.set(id, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    init(groupSessions: GroupSessionStore? = nil) {
        self.groupSessions = groupSessions ?? GroupSessionStore()
        currentGroupId = nil
    }

    func setSignedInUser(_ userId: Int?) {
        guard signedInUserId != userId else { return }
        groupSessions.discard()
        signedInUserId = userId
        currentGroupId = userId.flatMap {
            UserDefaults.standard.object(forKey: Self.currentGroupKey(userId: $0)) as? Int
        }
        if let currentGroupId { groupSessions.open(currentGroupId).appear() }
        selectedTab = .groups
    }

    func openGroup(_ id: Int, seed: Group? = nil) {
        groupNotice = nil
        exitedGroupId = nil
        groupSessions.open(id, seed: seed)
        currentGroupId = id
        selectedTab = .group
    }

    func leaveUnavailableGroup(message: String) {
        groupNotice = message
        groupSessions.discard()
        currentGroupId = nil
        selectedTab = .groups
    }

    func exitGroup(_ id: Int, message: String? = nil) {
        groupNotice = message
        exitedGroupId = id
        groupSessions.discard()
        currentGroupId = nil
        selectedTab = .groups
    }

    func recordSavedExpense(_ expense: Expense, groupId: Int) {
        guard let current = groupSessions.current, current.groupId == groupId else { return }
        current.snapshot.completedExpenseWrite(expense, groupId: groupId)
    }

    func resolveAddExpenseDestination(
        fetchGroups: () async throws -> [Group]
    ) async throws -> AddExpenseDestination {
        if let current = groupSessions.current,
           current.groupId == currentGroupId,
           let group = current.snapshot.group {
            return .resolve(groups: [group], currentGroupId: currentGroupId)
        }
        return .resolve(groups: try await fetchGroups(), currentGroupId: currentGroupId)
    }
}
