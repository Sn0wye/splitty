//
//  APIClient.swift
//  Splitty
//
//  Created by Snowye on 27/11/25.
//

import Foundation

// MARK: - API Client
final class APIClient: Sendable {
    static let shared = APIClient(
        session: .shared,
        credentials: KeychainCredentialStore(),
        baseURL: Result { try APIConfiguration.baseURL() },
        notificationCenter: .default
    )

    private let transport: APITransport
    private let tokens: TokenRefresher

    convenience init(
        session: URLSession,
        credentials: any CredentialStore,
        baseURL: String,
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            session: session,
            credentials: credentials,
            baseURL: .success(baseURL),
            notificationCenter: notificationCenter
        )
    }

    private init(
        session: URLSession,
        credentials: any CredentialStore,
        baseURL: Result<String, Error>,
        notificationCenter: NotificationCenter
    ) {
        transport = APITransport(baseURL: baseURL, session: session)
        tokens = TokenRefresher(
            transport: transport,
            credentials: credentials,
            notificationCenter: notificationCenter
        )
    }

    var hasCredentials: Bool {
        tokens.hasCredentials
    }

    // MARK: - Generic Request Method
    /// Not private: a service owns its own endpoints and calls this directly rather than
    /// adding another pass-through method here.
    func request<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: [String: Any]? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        var request = try transport.makeRequest(endpoint: endpoint, method: method, body: body)

        guard requiresAuth else {
            let (data, response) = try await transport.send(request)
            return try transport.decode(T.self, endpoint: endpoint, data: data, response: response)
        }

        let token = try await tokens.validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await transport.send(request)

        // A 401 means the server refused the bearer before any handler ran, so sending
        // the request again cannot apply it twice. One retry only: a second 401 is final.
        if response.statusCode == 401 {
            let refreshed = try await tokens.refreshedAccessToken(replacing: token)
            request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
            (data, response) = try await transport.send(request)
        }

        return try transport.decode(T.self, endpoint: endpoint, data: data, response: response)
    }


    // MARK: - Refresh

    // MARK: - Authentication
    /// Redeems a one-time Google auth code for a Splitty token pair. The exchange with
    /// Google happens server-side, so no client secret is needed here.
    func oauthGoogle(authCode: String) async throws -> LoginResponse {
        try await signIn(endpoint: "/oauth/google", body: ["authCode": authCode])
    }
    
    #if DEBUG
    /// Signs in as a seeded user with no credential. The route only exists on a
    /// Development host, so this cannot reach a deployed API.
    func devLogin(email: String) async throws -> LoginResponse {
        try await signIn(endpoint: "/auth/dev-login", body: ["email": email])
    }
    #endif

    private func signIn(endpoint: String, body: [String: Any]) async throws -> LoginResponse {
        let response: LoginResponse = try await request(
            endpoint: endpoint,
            method: .POST,
            body: body,
            requiresAuth: false
        )
        tokens.save(response.credentials)
        return response
    }

    /// Clears the stored pair at once, then asks the server to revoke the refresh token so
    /// a copy left behind stops working. The returned task is the revocation, which is
    /// best effort: no connection still signs out locally.
    @discardableResult
    func logout() -> Task<Void, Never> {
        let refreshToken = tokens.clear()

        return Task { [transport] in
            guard let refreshToken,
                  var request = try? transport.makeRequest(
                      endpoint: "/auth/logout",
                      method: .POST,
                      body: ["refreshToken": refreshToken]
                  )
            else { return }

            request.timeoutInterval = 5
            _ = try? await transport.send(request)
        }
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
    
    func createGroup(name: String, description: String?) async throws -> GroupMutationResponse {
        var body: [String: Any] = ["name": name]
        if let description = description { body["description"] = description }
        return try await request(endpoint: "/group", method: .POST, body: body)
    }
    
    func updateGroup(id: Int, name: String?, description: String?) async throws -> GroupMutationResponse {
        var body: [String: Any] = [:]
        if let name = name { body["name"] = name }
        if let description = description { body["description"] = description }
        return try await request(endpoint: "/group/\(id)", method: .PUT, body: body)
    }
    
    // MARK: - Invites
    func redeemInvite(code: String) async throws -> GroupDetail {
        return try await request(endpoint: "/invite/\(code)/accept", method: .POST)
    }
    
}

/// `ErrorResponse.code` on the wire: the refusals a client handles differently from others
/// with the same status.
enum APIErrorCode: String {
    case outstandingBalance = "outstanding_balance"
    case balancesPending = "balances_pending"
}

enum APIError: Error, LocalizedError {
    case missingBaseURL
    case invalidBaseURL(String)
    case invalidURL
    case noAuthToken
    case invalidRequestBody
    case invalidResponse
    /// `message` is the server's own explanation, when it sent one. A rejected split is the
    /// case that needs it: only the server knows why a request the client believed in was
    /// refused.
    case httpError(Int, message: String?)
    /// A refusal the server named with a code this build knows. Only refusals a client
    /// must tell apart from others with the same status carry one.
    case refused(Int, code: APIErrorCode, message: String?)
    case networkError(Error)
    case decodingError(Error)
    
    /// What to put on screen. The server's own `400` is the only thing that knows why a
    /// request the client believed in was refused, so it gets its own line rather than a
    /// raw `localizedDescription`.
    var displayMessage: String {
        switch self {
        case .httpError(_, .some(let message)), .refused(_, _, .some(let message)): return message
        case .refused(_, .balancesPending, nil): return L10n.Errors.balancesUpdating
        case .refused(_, .outstandingBalance, nil): return L10n.Errors.outstandingBalance
        case .httpError(400, _): return L10n.Errors.rejected
        case .httpError(403, _): return L10n.Errors.notMember
        case .httpError(404, _): return L10n.Errors.gone
        case .httpError(409, _): return L10n.Errors.outstandingBalance
        case .httpError(let status, _): return L10n.Errors.status(status)
        case .networkError: return L10n.Errors.network
        default: return errorDescription ?? L10n.Errors.generic
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "No API base URL is configured for this build"
        case .invalidBaseURL(let value):
            return "Invalid API base URL: \(value)"
        case .invalidURL:
            return "Invalid URL"
        case .noAuthToken:
            return "No authentication token"
        case .invalidRequestBody:
            return "Invalid request body"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let code, _), .refused(let code, _, _):
            return "HTTP error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}

extension Error {
    /// Non-`APIError` failures have no copy of their own to offer.
    var displayMessage: String {
        (self as? APIError)?.displayMessage ?? localizedDescription
    }

    /// Task cancellation can arrive directly or wrapped by an older networking call.
    /// Either shape means the caller should stop quietly rather than show an error.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let error = self as? URLError { return error.code == .cancelled }
        if case .networkError(let underlying) = self as? APIError {
            return underlying.isCancellation
        }
        return false
    }

    /// A delete can race another member's delete. A 404 means the requested end state
    /// already holds, whether the networking layer returned it directly or wrapped it.
    var isAlreadyGone: Bool {
        if case .httpError(404, _) = self as? APIError { return true }
        if case .networkError(let underlying) = self as? APIError {
            return underlying.isAlreadyGone
        }
        return false
    }
}

// MARK: - Request Types
struct ExpenseSplitRequest: Equatable {
    let userId: Int
    let amountCents: Int
    /// Percent units (`70`). Non-nil on every row of a percentage expense, nil elsewhere:
    /// the API requires it under that mode and nulls it under any other.
    let percentage: Decimal?
}

// MARK: - Response Types
struct LoginResponse: Codable {
    /// The access token; the field kept its name from when it was the only credential.
    let token: String
    let refreshToken: String
    let user: User

    var credentials: Credentials {
        Credentials(accessToken: token, refreshToken: refreshToken)
    }
}

struct RefreshResponse: Codable {
    let token: String
    let refreshToken: String

    var credentials: Credentials {
        Credentials(accessToken: token, refreshToken: refreshToken)
    }
}

// POST /group and PUT /group/{id} return the Group entity, which carries neither
// netBalance nor MemberDTO rows. Only these fields are safe to decode.
struct GroupMutationResponse: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
}

typealias GroupDetail = Group

struct GroupMembership: Codable, Identifiable {
    let id: Int
    let userId: Int
    let groupId: Int
    let joinedAt: String
    let user: User
}

struct GroupBalanceSummary: Codable {
    let simplifiedDebts: [SimplifiedDebt]
    /// A display hint only: true while a recomputation is queued or in flight.
    let balancesPending: Bool
}

struct SimplifiedDebt: Codable {
    let from: DebtMember
    let to: DebtMember
    @DecodedCents var amountCents: Int

    private enum CodingKeys: String, CodingKey {
        case from, to
        case amountCents = "amount"
    }
}

struct DebtMember: Codable, Equatable {
    let id: Int
    let name: String
    let avatarUrl: String

    var avatarURL: URL? {
        guard !avatarUrl.isEmpty else { return nil }
        return URL(string: avatarUrl)
    }
}

// MARK: - Empty Response for DELETE operations
struct EmptyResponse: Codable {}
