//
//  GroupService.swift
//  Splitty
//
//  Created by Snowye on 07/02/25.
//

import Foundation

class GroupService {
    static let shared = GroupService()
    
    private init() {}
    
    func getGroups() async throws -> [Group] {
        return try await APIClient.shared.getGroups()
    }
    
    func getGroup(id: Int) async throws -> GroupDetail {
        return try await APIClient.shared.getGroup(id: id)
    }
    
    func createGroup(name: String, description: String) async throws -> Group {
        return try await APIClient.shared.createGroup(name: name, description: description)
    }
    
    func updateGroup(id: Int, name: String?, description: String?) async throws -> Group {
        return try await APIClient.shared.updateGroup(id: id, name: name, description: description)
    }
}
