import Foundation

/// Deterministic large-data sets for later Instruments runs. Counts and identities
/// are fixed so a baseline and a post-change trace are looking at the same work.
enum PerformanceScenarios {
    static let largeAvatarURLs: [URL] = (1...8).compactMap { index in
        URL(string: "https://picsum.photos/id/\(index)/1024/1024")
    }

    static let profileUser = user(1)

    static let splitMembers: [GroupMember] = (1...50).map { index in
        GroupMember(
            id: index,
            userId: index,
            name: "Member \(index)",
            email: "member\(index)@example.com",
            avatarUrl: largeAvatarURLs[(index - 1) % largeAvatarURLs.count].absoluteString
        )
    }

    static let groups: [Group] = (1...100).map { index in
        let avatar = largeAvatarURLs[(index - 1) % largeAvatarURLs.count].absoluteString
        return Group(
            id: index,
            name: "Group \(index)",
            description: nil,
            netBalanceCents: index.isMultiple(of: 2) ? 1_250 : -980,
            createdAt: "2026-01-01T12:00:00Z",
            members: index == 1 ? splitMembers : [
                GroupMember(
                    id: index * 2 - 1,
                    userId: 1,
                    name: "Ada",
                    email: "ada@example.com",
                    avatarUrl: avatar
                ),
                GroupMember(
                    id: index * 2,
                    userId: 2,
                    name: "Ben",
                    email: "ben@example.com",
                    avatarUrl: avatar
                ),
            ]
        )
    }

    static let timeline: [Expense] = (1...500).map { index in
        let day = ((index - 1) % 28) + 1
        let paidBy = (index % 2) + 1
        let other = paidBy == 1 ? 2 : 1
        let timestamp = String(format: "2026-01-%02dT12:00:00Z", day)
        return Expense(
            id: index,
            groupId: 1,
            paidBy: paidBy,
            amount: 10,
            description: "Expense \(index)",
            type: .expense,
            category: .general,
            splitMode: .equal,
            date: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp,
            paidByUser: user(paidBy),
            splits: [
                ExpenseSplit(
                    id: index * 2 - 1,
                    expenseId: index,
                    userId: paidBy,
                    amount: 5,
                    percentage: nil,
                    user: user(paidBy)
                ),
                ExpenseSplit(
                    id: index * 2,
                    expenseId: index,
                    userId: other,
                    amount: 5,
                    percentage: nil,
                    user: user(other)
                ),
            ]
        )
    }

    static func user(_ id: Int) -> User {
        User(
            id: id,
            name: "User \(id)",
            email: "user\(id)@example.com",
            createdAt: "2026-01-01T12:00:00Z",
            updatedAt: "2026-01-01T12:00:00Z"
        )
    }
}
