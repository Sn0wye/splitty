//
//  Membership.swift
//  Splitty
//

import Foundation

/// What a membership action should say, and whether the group screen can still be used.
struct MembershipError: Equatable {
    /// What the API says when it refuses a leave or a removal because the group's balances
    /// are still being recomputed. The response carries no code, so the message is the
    /// only thing telling this 409 from the outstanding-balance one.
    static let balancesPendingMessage = "Balances are being recalculated. Try again in a moment."

    let message: String
    let shouldLeaveScreen: Bool

    init(_ error: Error) {
        switch error as? APIError {
        case .httpError(403, _), .httpError(404, _):
            message = L10n.Errors.groupUnavailable
            shouldLeaveScreen = true
        case .httpError(409, .some(Self.balancesPendingMessage)):
            message = L10n.Errors.balancesUpdating
            shouldLeaveScreen = false
        default:
            message = error.displayMessage
            shouldLeaveScreen = false
        }
    }
}

/// Stable presentation data for users retained on historical expense rows.
struct MemberDisplay: Equatable {
    /// The exact name every projection gives a tombstone.
    static let tombstoneName = "[removed]"
    static let removed = MemberDisplay(name: tombstoneName, avatarURL: nil)

    let userID: Int?
    let name: String
    let avatarURL: URL?
    let isRemoved: Bool

    init(name: String, avatarURL: URL?, userID: Int? = nil) {
        self.userID = userID
        isRemoved = name == Self.tombstoneName
        self.name = isRemoved ? L10n.Errors.removedMember : name
        self.avatarURL = isRemoved ? nil : avatarURL
    }

    init(_ user: User) {
        self.init(name: user.name, avatarURL: user.avatarURL, userID: user.id)
    }

    init(_ user: User, currentUserId: Int, currentUserLabel: String) {
        self.init(
            name: user.id == currentUserId ? currentUserLabel : user.name,
            avatarURL: user.avatarURL,
            userID: user.id
        )
    }

    init(_ member: GroupMember) {
        self.init(
            name: member.name,
            avatarURL: member.avatarUrl.isEmpty ? nil : URL(string: member.avatarUrl),
            userID: member.userId
        )
    }

    func resolved(currentUser: User?) -> MemberDisplay {
        guard let currentUser, userID == currentUser.id else { return self }
        return MemberDisplay(currentUser)
    }
}

extension GroupMember {
    /// A tombstone, kept in the group only to carry an unsettled balance. It can be paid,
    /// but it can't be billed: the server refuses an expense that includes it.
    var isRemoved: Bool { name == MemberDisplay.tombstoneName }
}
