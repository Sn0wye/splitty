import Foundation

enum AvatarKeyUpdate: Equatable {
    case unchanged
    case set(String)
    case remove
}

struct ProfileUpdate {
    var name: String?
    var avatarKey: AvatarKeyUpdate = .unchanged

    var body: [String: Any] {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        switch avatarKey {
        case .unchanged:
            break
        case .set(let key):
            body["avatarKey"] = key
        case .remove:
            body["avatarKey"] = NSNull()
        }
        return body
    }
}

struct AvatarUpload: Codable, Equatable {
    let key: String
    let uploadURL: URL
    let contentType: String
    let maxBytes: Int

    private enum CodingKeys: String, CodingKey {
        case key, contentType, maxBytes
        case uploadURL = "uploadUrl"
    }
}

final class ProfileService {
    static let shared = ProfileService()

    private let uploadSession: URLSession

    init(uploadSession: URLSession = .shared) {
        self.uploadSession = uploadSession
    }

    func update(_ update: ProfileUpdate) async throws -> User {
        let profile: ProfileResponse = try await APIClient.shared.request(
            endpoint: "/profile",
            method: .PATCH,
            body: update.body
        )
        return profile.user
    }

    func createAvatarUpload() async throws -> AvatarUpload {
        try await APIClient.shared.request(
            endpoint: "/profile/avatar/upload-url",
            method: .POST
        )
    }

    /// Upload URLs belong to storage, not the Splitty API. This request deliberately has
    /// no authorization header.
    func uploadAvatar(_ data: Data, to slot: AvatarUpload) async throws {
        guard data.count <= slot.maxBytes else { throw AvatarUploadError.tooLarge }

        var request = URLRequest(url: slot.uploadURL)
        request.httpMethod = HTTPMethod.PUT.rawValue
        request.setValue(slot.contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await uploadSession.upload(for: request, from: data)

        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200...299 ~= response.statusCode else {
            throw APIError.httpError(response.statusCode, message: nil)
        }
    }
}

enum AvatarUploadError: LocalizedError {
    case invalidImage
    case encodingFailed
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage: L10n.Profile.invalidImage
        case .encodingFailed: L10n.Profile.preparationFailed
        case .tooLarge: L10n.Profile.tooLarge
        }
    }
}
