//
//  AuthenticationManager.swift
//  Splitty
//
//  Created by Snowye on 19/11/25.
//

import Foundation
import SwiftUI

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    
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
            self?.logout()
        }
    }
    
    func checkAuthenticationStatus() {
        isAuthenticated = AuthService.shared.isAuthenticated()
    }
    
    func login() {
        isAuthenticated = true
    }
    
    func logout() {
        AuthService.shared.logout()
        isAuthenticated = false
    }
}