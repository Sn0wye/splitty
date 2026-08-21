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
    
    // MARK: - Sign in with Google
    /// Throws `GoogleSignInError.cancelled` when the user dismisses the account picker.
    func signInWithGoogle() async throws -> User {
        let authCode = try await GoogleSignInService.shared.signIn()
        let response = try await APIClient.shared.oauthGoogle(authCode: authCode)
        
        // Save token to keychain
        TokenManager.shared.saveToken(response.token)
        
        print("✅ User signed in with Google: \(response.user.name)")
        return response.user
    }
    
    #if DEBUG
    // MARK: - Dev sign in
    func devSignIn(email: String) async throws -> User {
        let response = try await APIClient.shared.devLogin(email: email)
        
        // Save token to keychain
        TokenManager.shared.saveToken(response.token)
        
        print("✅ Dev sign-in as: \(response.user.name)")
        return response.user
    }
    #endif
    
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
