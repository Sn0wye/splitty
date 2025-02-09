//
//  User.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

struct User: Codable, Identifiable {
    var id: Int;
    var name: String;
    var email: String;
    var createdAt: String;
    var updatedAt: String;
}
