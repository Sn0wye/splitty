//
//  TokenManager.swift
//  Splitty
//
//  Created by Snowye on 21/09/25.
//

import Foundation
import Security

class TokenManager {
    static let shared = TokenManager()
    
    private let service = "com.splitty.app"
    private let tokenKey = "auth_token"
    
    private init() {}
    
    // MARK: - Save Token
    func saveToken(_ token: String) {
        let data = token.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data
        ]
        
        // Delete any existing token first
        SecItemDelete(query as CFDictionary)
        
        // Add the new token
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            print("❌ Error saving token to Keychain: \(status)")
        } else {
            print("✅ Token saved to Keychain successfully")
        }
    }
    
    // MARK: - Retrieve Token
    func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        
        if status != errSecItemNotFound {
            print("❌ Error retrieving token from Keychain: \(status)")
        }
        
        return nil
    }
    
    // MARK: - Delete Token
    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            print("✅ Token deleted from Keychain successfully")
        } else if status != errSecItemNotFound {
            print("❌ Error deleting token from Keychain: \(status)")
        }
    }
    
    // MARK: - Check if token exists
    func hasToken() -> Bool {
        return getToken() != nil
    }
    
    // MARK: - Token Validation (basic check for JWT format)
    func isTokenValid() -> Bool {
        guard let token = getToken() else { return false }
        
        // Basic JWT format validation (3 parts separated by dots)
        let components = token.components(separatedBy: ".")
        if components.count != 3 {
            return false
        }
        
        // Optional: You can add expiration check here by decoding the JWT
        // For now, we'll just check the format
        return true
    }
    
    // MARK: - Get Bearer Token for API calls
    func getBearerToken() -> String? {
        guard let token = getToken(), isTokenValid() else {
            return nil
        }
        return "Bearer \(token)"
    }
}
