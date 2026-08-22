//
//  AuthenticationManager.swift
//  Splitty
//
//  Created by Snowye on 19/11/25.
//

import Foundation
import SwiftUI

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false

    /// Who is signed in. Everything that says "you" — the default payer, the checkbox
    /// defaults, whether a row reads *lent* or *borrowed* — reads this. Not cached in
    /// UserDefaults: the token already lives in the Keychain, and one request on launch
    /// cannot go stale the way a second copy of the profile can.
    @Published var currentUser: User?

    static let shared = AuthenticationManager()
    
    private init() {
        checkAuthenticationStatus()
        setupUnauthorizedObserver()
    }
    
    private func setupUnauthorizedObserver() {
        NotificationCenter.default.addObserver(
            forName: .unauthorizedError,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("🔴 Received 401 unauthorized - forcing logout")
            Task { @MainActor in self?.logout() }
        }
    }
    
    func checkAuthenticationStatus() {
        isAuthenticated = AuthService.shared.isAuthenticated()
    }
    
    func login(user: User) {
        currentUser = user
        isAuthenticated = true
    }

    /// Fills in `currentUser` on a cold launch that skipped the sign-in screen. A failure
    /// leaves the session alone: a 401 already forces a logout through the notification,
    /// and anything else is a network blip that a later screen can retry.
    func hydrateCurrentUser() async {
        guard isAuthenticated, currentUser == nil else { return }

        do {
            currentUser = try await AuthService.shared.getCurrentUser()
        } catch {
            print("⚠️ Could not load the signed-in profile: \(error.localizedDescription)")
        }
    }

    func logout() {
        AuthService.shared.logout()
        currentUser = nil
        isAuthenticated = false
    }
}