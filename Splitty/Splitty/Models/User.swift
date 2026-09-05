//
//  User.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import Foundation

struct User: Codable, Identifiable {
    var id: Int;
    var name: String;
    var email: String;
    var avatarURL: URL? = nil;
    var createdAt: String;
    var updatedAt: String;

    private enum CodingKeys: String, CodingKey {
        case id, name, email, createdAt, updatedAt
        case avatarURL = "avatarUrl"
    }

    init(
        id: Int,
        name: String,
        email: String,
        avatarURL: URL? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        email = try values.decode(String.self, forKey: .email)
        let avatarString = try values.decodeIfPresent(String.self, forKey: .avatarURL)
        avatarURL = avatarString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        createdAt = try values.decode(String.self, forKey: .createdAt)
        updatedAt = try values.decode(String.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(email, forKey: .email)
        try values.encodeIfPresent(avatarURL?.absoluteString, forKey: .avatarURL)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}
