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
    
    private let baseURL = "http://127.0.0.1:8080"
    private let session = URLSession.shared
    
    private init() {}
    
    // MARK: - Generic Request Method
    private func request<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: [String: Any]? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        
        guard let url = URL(string: baseURL + endpoint) else {
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
                throw APIError.httpError(httpResponse.statusCode)
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
    
    // MARK: - Authentication
    func login(email: String, password: String) async throws -> LoginResponse {
        let body = ["email": email, "password": password]
        return try await request(endpoint: "/auth/login", method: .POST, body: body, requiresAuth: false)
    }
    
    func register(name: String, email: String, password: String) async throws -> LoginResponse {
        let body = ["name": name, "email": email, "password": password]
        return try await request(endpoint: "/auth/register", method: .POST, body: body, requiresAuth: false)
    }
    
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
    
    func createGroup(name: String, description: String) async throws -> Group {
        let body = ["name": name, "description": description]
        return try await request(endpoint: "/group", method: .POST, body: body)
    }
    
    func updateGroup(id: Int, name: String?, description: String?) async throws -> Group {
        var body: [String: Any] = [:]
        if let name = name { body["name"] = name }
        if let description = description { body["description"] = description }
        return try await request(endpoint: "/group/\(id)", method: .PUT, body: body)
    }
    
    func deleteGroup(id: Int) async throws {
        let _: EmptyResponse = try await request(endpoint: "/group/\(id)", method: .DELETE)
    }
    
    // MARK: - Expenses
    func getExpenses(groupId: Int) async throws -> [Expense] {
        return try await request(endpoint: "/group/\(groupId)/expenses")
    }
    
    func getExpense(groupId: Int, expenseId: Int) async throws -> Expense {
        return try await request(endpoint: "/group/\(groupId)/expenses/\(expenseId)")
    }
    
    func createExpense(
        groupId: Int,
        description: String,
        amount: Double,
        paidBy: Int,
        splits: [ExpenseSplitRequest]
    ) async throws -> Expense {
        let body: [String: Any] = [
            "groupId": groupId,
            "description": description,
            "amount": amount,
            "paidBy": paidBy,
            "splits": splits.map { ["userId": $0.userId, "amount": $0.amount] }
        ]
        return try await request(endpoint: "/group/\(groupId)/expenses", method: .POST, body: body)
    }
    
    func updateExpense(
        groupId: Int,
        expenseId: Int,
        description: String?,
        amount: Double?,
        splits: [ExpenseSplitRequest]?
    ) async throws -> Expense {
        var body: [String: Any] = [:]
        if let description = description { body["description"] = description }
        if let amount = amount { body["amount"] = amount }
        if let splits = splits {
            body["splits"] = splits.map { ["userId": $0.userId, "amount": $0.amount] }
        }
        return try await request(endpoint: "/group/\(groupId)/expenses/\(expenseId)", method: .PUT, body: body)
    }
    
    func deleteExpense(groupId: Int, expenseId: Int) async throws {
        let _: EmptyResponse = try await request(endpoint: "/group/\(groupId)/expenses/\(expenseId)", method: .DELETE)
    }
    
    // MARK: - Users/Profile
    func getProfile() async throws -> User {
        return try await request(endpoint: "/profile")
    }
    
    func updateProfile(name: String?, email: String?) async throws -> User {
        var body: [String: Any] = [:]
        if let name = name { body["name"] = name }
        if let email = email { body["email"] = email }
        return try await request(endpoint: "/profile", method: .PUT, body: body)
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case noAuthToken
    case invalidRequestBody
    case invalidResponse
    case httpError(Int)
    case networkError(Error)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noAuthToken:
            return "No authentication token"
        case .invalidRequestBody:
            return "Invalid request body"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Request Types
struct ExpenseSplitRequest {
    let userId: Int
    let amount: Double
}

// MARK: - Response Types
struct LoginResponse: Codable {
    let token: String
    let user: User
}

struct GroupDetail: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String
    let netBalance: Double
    let createdAt: String
    let members: [GroupMember]
}

struct GroupMembership: Codable, Identifiable {
    let id: Int
    let userId: Int
    let groupId: Int
    let joinedAt: String
    let user: User
}

struct Balance: Codable {
    let userId: Int
    let amount: Double
    let user: User
}

// MARK: - Empty Response for DELETE operations
struct EmptyResponse: Codable {}
