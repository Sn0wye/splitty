//
//  APIClient.swift
//  Splitty
//
//  Created by Snowye on 27/11/25.
//

import Foundation

extension Notification.Name {
    static let unauthorizedError = Notification.Name("unauthorizedError")
}

// MARK: - API Client
class APIClient {
    static let shared = APIClient()
    
    /// Resolved once at startup; a misconfigured build fails on every request rather
    /// than falling back to a hardcoded host.
    private let baseURL: Result<String, Error>
    private let session = URLSession.shared
    
    private init() {
        baseURL = Result { try APIConfiguration.baseURL() }
    }
    
    // MARK: - Generic Request Method
    /// Not private: a service owns its own endpoints and calls this directly rather than
    /// adding another pass-through method here.
    func request<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: [String: Any]? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        
        guard let url = URL(string: try baseURL.get() + endpoint) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication if required
        if requiresAuth {
            guard let token = TokenManager.shared.getToken() else {
                throw APIError.noAuthToken
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Add body if present
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw APIError.invalidRequestBody
            }
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                // Handle 401 Unauthorized - post notification to trigger logout
                if httpResponse.statusCode == 401 {
                    print("🚨 401 Unauthorized - Logging out user")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .unauthorizedError, object: nil)
                    }
                }
                throw APIError.httpError(httpResponse.statusCode, message: Self.serverMessage(from: data))
            }
            
            // A 204 carries no body; decoding one is a failure that has nothing to report.
            if data.isEmpty, let empty = EmptyResponse() as? T {
                return empty
            }

            let decoder = JSONDecoder()
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                // Log the JSON response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("❌ Decoding error for endpoint \(endpoint)")
                    print("📄 JSON Response: \(jsonString)")
                }
                throw APIError.decodingError(error)
            }
            
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    /// The server's explanation for a rejection, from either error shape the API produces:
    /// its own `ErrorResponse`, or the validation dictionary `ModelState` returns.
    private static func serverMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }

        if let errors = json["errors"] as? [String: Any] {
            let messages = errors.values.compactMap { $0 as? [String] }.flatMap { $0 }
            if !messages.isEmpty { return messages.joined(separator: " ") }
        }

        return nil
    }

    // MARK: - Authentication
    /// Redeems a one-time Google auth code for a Splitty token. The exchange with Google
    /// happens server-side, so no client secret is needed here.
    func oauthGoogle(authCode: String) async throws -> LoginResponse {
        let body = ["authCode": authCode]
        return try await request(endpoint: "/oauth/google", method: .POST, body: body, requiresAuth: false)
    }
    
    #if DEBUG
    /// Signs in as a seeded user with no credential. The route only exists on a
    /// Development host, so this cannot reach a deployed API.
    func devLogin(email: String) async throws -> LoginResponse {
        let body = ["email": email]
        return try await request(endpoint: "/auth/dev-login", method: .POST, body: body, requiresAuth: false)
    }
    #endif
    
    // MARK: - Groups
    func getGroups() async throws -> [Group] {
        print("🌐 API Request: GET /group")
        let groups: [Group] = try await request(endpoint: "/group")
        print("🌐 API Response: Received \(groups.count) groups")
        return groups
    }
    
    func getGroup(id: Int) async throws -> GroupDetail {
        return try await request(endpoint: "/group/\(id)")
    }
    
    func createGroup(name: String, description: String?) async throws -> GroupMutationResponse {
        var body: [String: Any] = ["name": name]
        if let description = description { body["description"] = description }
        return try await request(endpoint: "/group", method: .POST, body: body)
    }
    
    func updateGroup(id: Int, name: String?, description: String?) async throws -> GroupMutationResponse {
        var body: [String: Any] = [:]
        if let name = name { body["name"] = name }
        if let description = description { body["description"] = description }
        return try await request(endpoint: "/group/\(id)", method: .PUT, body: body)
    }
    
    // MARK: - Invites
    func redeemInvite(code: String) async throws -> GroupDetail {
        return try await request(endpoint: "/invite/\(code)/accept", method: .POST)
    }
    
    // MARK: - Users/Profile
    /// The profile route is `GET /auth`, not `/profile` — there has never been a
    /// `/profile` route to call.
    func getProfile() async throws -> User {
        return try await request(endpoint: "/auth")
    }
}

enum APIError: Error, LocalizedError {
    case missingBaseURL
    case invalidBaseURL(String)
    case invalidURL
    case noAuthToken
    case invalidRequestBody
    case invalidResponse
    /// `message` is the server's own explanation, when it sent one. A rejected split is the
    /// case that needs it: only the server knows why a request the client believed in was
    /// refused.
    case httpError(Int, message: String?)
    case networkError(Error)
    case decodingError(Error)
    
    /// What to put on screen. The server's own `400` is the only thing that knows why a
    /// request the client believed in was refused, so it gets its own line rather than a
    /// raw `localizedDescription`.
    var displayMessage: String {
        switch self {
        case .httpError(_, .some(let message)): return message
        case .httpError(400, _): return "The server rejected this. Check the amounts and try again."
        case .httpError(403, _): return "You are not a member of this group."
        case .httpError(404, _): return "This no longer exists."
        case .httpError(let status, _): return "Something went wrong (\(status)). Try again."
        case .networkError: return "Couldn't reach Splitty. Check your connection and try again."
        default: return errorDescription ?? "Something went wrong. Try again."
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "No API base URL is configured for this build"
        case .invalidBaseURL(let value):
            return "Invalid API base URL: \(value)"
        case .invalidURL:
            return "Invalid URL"
        case .noAuthToken:
            return "No authentication token"
        case .invalidRequestBody:
            return "Invalid request body"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let code, _):
            return "HTTP error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}

extension Error {
    /// Non-`APIError` failures have no copy of their own to offer.
    var displayMessage: String {
        (self as? APIError)?.displayMessage ?? localizedDescription
    }
}

// MARK: - Request Types
struct ExpenseSplitRequest {
    let userId: Int
    let amountCents: Int
    /// Percent units (`70`). Non-nil on every row of a percentage expense, nil elsewhere:
    /// the API requires it under that mode and nulls it under any other.
    let percentage: Decimal?
}

// MARK: - Response Types
struct LoginResponse: Codable {
    let token: String
    let user: User
}

// POST /group and PUT /group/{id} return the Group entity, which carries neither
// netBalance nor MemberDTO rows. Only these fields are safe to decode.
struct GroupMutationResponse: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
}

typealias GroupDetail = Group

struct GroupMembership: Codable, Identifiable {
    let id: Int
    let userId: Int
    let groupId: Int
    let joinedAt: String
    let user: User
}

struct GroupBalanceSummary: Codable {
    let balances: [Balance]
    /// A display hint only: true while a recomputation is queued or in flight.
    let balancesPending: Bool
}

struct Balance: Codable {
    let userId: Int
    let peerId: Int
    @DecodedCents var amountCents: Int
    let user: User
    let peer: User

    private enum CodingKeys: String, CodingKey {
        case userId, peerId, user, peer
        case amountCents = "amount"
    }
}

// MARK: - Empty Response for DELETE operations
struct EmptyResponse: Codable {}
