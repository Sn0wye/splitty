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
    
    // MARK: - Modern async/await methods
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
    
    func deleteGroup(id: Int) async throws {
        return try await APIClient.shared.deleteGroup(id: id)
    }
    
    // MARK: - Legacy callback methods for existing code
    static func fetchGroups(completion: @escaping (Result<[Group], Error>) -> Void) {
        Task {
            do {
                let groups = try await shared.getGroups()
                completion(.success(groups))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    static func fetchGroupDetails(groupId: Int, completion: @escaping (Result<GroupDetail, Error>) -> Void) {
        Task {
            do {
                let group = try await shared.getGroup(id: groupId)
                completion(.success(group))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
