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
    
    /// Balances plus the pending flag. Recomputation is asynchronous, so right after a
    /// money write the numbers are stale and `balancesPending` says so.
    func getBalanceSummary(groupId: Int) async throws -> GroupBalanceSummary {
        try await APIClient.shared.request(endpoint: "/group/\(groupId)/expenses/summary")
    }

    /// Group spend and the caller's share over `query`'s local dates, which the server
    /// resolves in `query.timeZone`. Omitted dates leave that end open.
    func getStats(groupId: Int, query: StatsQuery) async throws -> GroupStats {
        var components = URLComponents()
        components.queryItems = [
            query.from.map { URLQueryItem(name: "from", value: $0) },
            query.to.map { URLQueryItem(name: "to", value: $0) },
            URLQueryItem(name: "tz", value: query.timeZone)
        ].compactMap { $0 }
        // `URLComponents` leaves `+` alone, which a server reads as a space: `Etc/GMT+3`.
        let queryString = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B") ?? ""
        return try await APIClient.shared.request(endpoint: "/group/\(groupId)/stats?\(queryString)")
    }

    func getPeople() async throws -> PeopleResponse {
        try await APIClient.shared.request(endpoint: "/people")
    }

    func requestBalanceRecomputation(groupId: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/expenses/summary",
            method: .POST
        )
    }

    /// Creates a fresh invite with the API's default expiry and unlimited uses.
    func createInvite(groupId: Int) async throws -> CreatedInvite {
        try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/invites",
            method: .POST,
            body: [:]
        )
    }

    /// Describes an invite before the user decides whether to join.
    func describeInvite(code: String) async throws -> InviteMetadata {
        try await APIClient.shared.request(endpoint: "/invite/\(code)")
    }

    /// Redeems an invite code. The response identifies the group — the caller never
    /// supplies a group id. Redeeming a code for a group you already belong to
    /// succeeds and returns that group.
    func redeemInvite(code: String) async throws -> GroupDetail {
        return try await APIClient.shared.redeemInvite(code: code)
    }

    func removeMember(groupId: Int, userId: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/members/\(userId)",
            method: .DELETE
        )
    }

    func leave(groupId: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/leave",
            method: .POST
        )
    }
}
