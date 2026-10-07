//
//  AuthService.swift
//  Splitty
//
//  Created by Snowye on 21/09/25.
//

import Foundation

final class AuthService: AuthenticationSource {
    static let shared = AuthService(client: .shared)
    
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }
    
    // MARK: - Sign in with Google
    /// Throws `GoogleSignInError.cancelled` when the user dismisses the account picker.
    func signInWithGoogle() async throws -> User {
        let authCode = try await GoogleSignInService.shared.signIn()
        let response = try await client.oauthGoogle(authCode: authCode)
        
        print("✅ User signed in with Google: \(response.user.name)")
        return response.user
    }
    
    #if DEBUG
    // MARK: - Dev sign in
    func devSignIn(email: String) async throws -> User {
        let response = try await client.devLogin(email: email)
        
        print("✅ Dev sign-in as: \(response.user.name)")
        return response.user
    }
    #endif
    
    // MARK: - AuthenticationSource
    func logout() {
        client.logout()
        print("✅ User logged out successfully")
    }
    
    func isAuthenticated() -> Bool {
        client.hasCredentials
    }
    
    func currentUser() async throws -> User {
        let profile: ProfileResponse = try await client.request(endpoint: "/profile")
        return profile.user
    }
}
