//
//  CredentialStore.swift
//  Splitty
//
//  Created by Snowye on 21/09/25.
//

import Foundation
import Security

/// The pair sign-in returns. Holding a refresh token is what "signed in" means; the access
/// token is short-lived and only the server decides whether either one still works.
struct Credentials: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String

    /// The access token's `exp`, read only to refresh ahead of a certain 401. A token
    /// without a readable `exp` returns nil and is sent as is.
    var accessTokenExpiry: Date? {
        let segments = accessToken.components(separatedBy: ".")
        guard segments.count == 3 else { return nil }

        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }
}

protocol CredentialStore: Sendable {
    func load() -> Credentials?
    func save(_ credentials: Credentials)
    func clear()
}

/// Both tokens live in one Keychain item, so a save never leaves a new access token
/// beside an old refresh token. The item stays on this device and is readable after the
/// first unlock, so a background launch can still refresh but backups and iCloud
/// Keychain never carry it.
struct KeychainCredentialStore: CredentialStore {
    private let service = "com.splitty.app"
    private let account = "auth_credentials"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func load() -> Credentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                print("❌ Error reading credentials from Keychain: \(status)")
            }
            return nil
        }

        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    func save(_ credentials: Credentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
        }

        if status != errSecSuccess {
            print("❌ Error saving credentials to Keychain: \(status)")
        }
    }

    func clear() {
        let status = SecItemDelete(baseQuery as CFDictionary)

        if status != errSecSuccess, status != errSecItemNotFound {
            print("❌ Error deleting credentials from Keychain: \(status)")
        }
    }
}
