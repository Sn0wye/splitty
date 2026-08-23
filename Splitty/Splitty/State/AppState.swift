//
//  AppState.swift
//  Splitty
//

import SwiftUI

enum AppTab: Int, CaseIterable {
    case groups
    case group
    case settings

    var title: String {
        switch self {
        case .groups: return "Groups"
        case .group: return "Group"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .groups: return "square.grid.2x2"
        case .group: return "person.2"
        case .settings: return "gearshape"
        }
    }
}

/// Shared navigation state: which tab is showing and which group the
/// "Group" tab is currently pointing at.
@MainActor
final class AppState: ObservableObject {
    private static let currentGroupKey = "currentGroupId"

    @Published var selectedTab: AppTab = .groups

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
        currentGroupId = id
        selectedTab = .group
    }
}
