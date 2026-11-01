//
//  Groups.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import Foundation

// MARK: - Group Model
struct Group: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    /// The currency of every amount in the group (ADR 0007).
    var currency: Currency = .usd
    @DecodedCents var netBalanceCents: Int
    let createdAt: String
    let members: [GroupMember]
    /// The newest row's `date ?? createdAt`, as the API serialized it. Nil without rows.
    var lastActivityAt: String? = nil

    private enum CodingKeys: String, CodingKey {
        case id, name, description, currency, createdAt, members, lastActivityAt
        case netBalanceCents = "netBalance"
    }
}

extension Group {
    /// In an extension so the memberwise initializer survives.
    ///
    /// An unknown currency reads as dollars rather than failing the decode: a server that
    /// lists a currency this build does not would otherwise empty the whole groups list.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        currency = (try? container.decodeIfPresent(Currency.self, forKey: .currency)) ?? .usd
        _netBalanceCents = try container.decode(DecodedCents.self, forKey: .netBalanceCents)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        members = try container.decode([GroupMember].self, forKey: .members)
        lastActivityAt = try container.decodeIfPresent(String.self, forKey: .lastActivityAt)
    }
}

extension Group {
    /// Most recently active first: the newest expense, then the groups opened this session,
    /// newest first, then the newest group. Groups alike on all three keep the order given.
    static func recentFirst(_ groups: [Group], recentlyOpened: [Int]) -> [Group] {
        var openRank: [Int: Int] = [:]
        for (rank, id) in recentlyOpened.enumerated() where openRank[id] == nil {
            openRank[id] = rank
        }
        let keyed = groups.enumerated().map { offset, group in
            (
                group: group,
                offset: offset,
                activity: group.lastActivityAt.flatMap(Expense.parseTimestamp),
                opened: openRank[group.id],
                created: Expense.parseTimestamp(group.createdAt)
            )
        }
        return keyed.sorted { lhs, rhs in
            if let order = present(lhs.activity, before: rhs.activity, by: >) { return order }
            if let order = present(lhs.opened, before: rhs.opened, by: <) { return order }
            if let order = present(lhs.created, before: rhs.created, by: >) { return order }
            return lhs.offset < rhs.offset
        }.map(\.group)
    }

    /// Whether `lhs` sorts first, or nil when the key cannot tell them apart. A missing
    /// value sorts after any present one.
    private static func present<T: Comparable>(
        _ lhs: T?, before rhs: T?, by isBefore: (T, T) -> Bool
    ) -> Bool? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs: isBefore(lhs, rhs)
        case (.some, nil): true
        case (nil, .some): false
        default: nil
        }
    }
}

// MARK: - Group Member Model
struct GroupMember: Codable, Identifiable {
    let id: Int
    let userId: Int
    let name: String
    let email: String
    let avatarUrl: String
}
