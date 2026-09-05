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
}
