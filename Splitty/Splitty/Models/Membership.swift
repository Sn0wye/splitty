//
//  Membership.swift
//  Splitty
//

import Foundation

/// What a membership action should say, and whether the group screen can still be used.
struct MembershipError: Equatable {
    let message: String
    let shouldLeaveScreen: Bool

    init(_ error: Error) {
        switch error as? APIError {
        case .httpError(403, _), .httpError(404, _):
            message = "This group is no longer available"
            shouldLeaveScreen = true
        default:
            message = error.displayMessage
            shouldLeaveScreen = false
        }
    }
}

/// Stable presentation data for users retained on historical expense rows.
struct MemberDisplay: Equatable {
    static let removed = MemberDisplay(name: "[removed]", avatarURL: nil)

    let name: String
    let avatarURL: URL?
    let isRemoved: Bool

    init(name: String, avatarURL: URL?) {
        isRemoved = name == "[removed]"
        self.name = isRemoved ? "Removed member" : name
        self.avatarURL = isRemoved ? nil : avatarURL
    }

    init(_ user: User) {
        self.init(name: user.name, avatarURL: user.avatarURL)
    }

    init(_ user: User, currentUserId: Int, currentUserLabel: String) {
        self.init(
            name: user.id == currentUserId ? currentUserLabel : user.name,
            avatarURL: user.avatarURL
        )
    }

    init(_ member: GroupMember) {
        self.init(
            name: member.name,
            avatarURL: member.avatarUrl.isEmpty ? nil : URL(string: member.avatarUrl)
        )
    }
}
