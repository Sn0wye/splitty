//
//  NotificationService.swift
//  Splitty
//

import Foundation

final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    /// Registers this device against the current sign-in. Sent again when the token or the
    /// app language changes: the server writes each notification in that language.
    func registerDevice(token: String, language: AppLanguage) async throws {
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif

        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/profile/push-device",
            method: .PUT,
            body: ["token": token, "environment": environment, "language": language.rawValue]
        )
    }

    func settings() async throws -> NotificationSettings {
        try await APIClient.shared.request(endpoint: "/profile/notifications")
    }

    func save(_ settings: NotificationSettings) async throws -> NotificationSettings {
        try await APIClient.shared.request(
            endpoint: "/profile/notifications",
            method: .PUT,
            body: settings.body
        )
    }

    /// Asks a member who owes the caller to pay. The server allows one a day per member.
    func remind(groupId: Int, userId: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            endpoint: "/group/\(groupId)/reminders",
            method: .POST,
            body: ["userId": userId]
        )
    }
}
