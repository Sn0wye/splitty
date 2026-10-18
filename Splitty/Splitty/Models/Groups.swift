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

    private enum CodingKeys: String, CodingKey {
        case id, name, description, currency, createdAt, members
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
