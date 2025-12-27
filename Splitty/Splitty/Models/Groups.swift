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
    let description: String
    let netBalance: Double
    let createdAt: String
    let members: [GroupMember]
}

// MARK: - Group Member Model
struct GroupMember: Codable, Identifiable {
    let id: Int
    let userId: Int
    let name: String
    let email: String
    let avatarUrl: String
}
