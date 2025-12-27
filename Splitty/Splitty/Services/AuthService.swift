//
//  AuthService.swift
//  Splitty
//
//  Created by Snowye on 21/09/25.
//

import Foundation

class AuthService {
    static let shared = AuthService()
    
    private init() {}
    
    // MARK: - Login
    func login(email: String, password: String) async throws -> User {
        let response = try await APIClient.shared.login(email: email, password: password)
        
        // Save token to keychain
        TokenManager.shared.saveToken(response.token)
        
        print("✅ User logged in successfully: \(response.user.name)")
        return response.user
    }
    
    // MARK: - Register
    func register(name: String, email: String, password: String) async throws -> User {
        let response = try await APIClient.shared.register(name: name, email: email, password: password)
        
        // Save token to keychain
        TokenManager.shared.saveToken(response.token)
        
        print("✅ User registered successfully: \(response.user.name)")
        return response.user
    }
    
    // MARK: - Logout
    func logout() {
        TokenManager.shared.deleteToken()
        print("✅ User logged out successfully")
    }
    
    // MARK: - Check if user is authenticated
    func isAuthenticated() -> Bool {
        return TokenManager.shared.isTokenValid()
    }
    
    // MARK: - Get current user
    func getCurrentUser() async throws -> User {
        guard isAuthenticated() else {
            throw APIError.noAuthToken
        }
        
        return try await APIClient.shared.getProfile()
    }
}

// MARK: - Convenience methods for existing callback-based code
extension AuthService {
    func login(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        Task {
            do {
                let user = try await login(email: email, password: password)
                completion(.success(user))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func register(name: String, email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        Task {
            do {
                let user = try await register(name: name, email: email, password: password)
                completion(.success(user))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
