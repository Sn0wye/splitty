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
    @DecodedCents var netBalanceCents: Int
    let createdAt: String
    let members: [GroupMember]

    private enum CodingKeys: String, CodingKey {
        case id, name, description, createdAt, members
        case netBalanceCents = "netBalance"
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
