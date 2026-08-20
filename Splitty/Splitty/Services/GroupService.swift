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
    
    func createGroup(name: String, description: String?) async throws -> GroupMutationResponse {
        return try await APIClient.shared.createGroup(name: name, description: description)
    }
    
    func updateGroup(id: Int, name: String?, description: String?) async throws -> GroupMutationResponse {
        return try await APIClient.shared.updateGroup(id: id, name: name, description: description)
    }
    
    /// Redeems an invite code. The response identifies the group — the caller never
    /// supplies a group id. Redeeming a code for a group you already belong to
    /// succeeds and returns that group.
    func redeemInvite(code: String) async throws -> GroupDetail {
        return try await APIClient.shared.redeemInvite(code: code)
    }
}
