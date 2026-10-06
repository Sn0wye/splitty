//
//  APIClient.swift
//  Splitty
//
//  Created by Snowye on 27/11/25.
//

import Foundation

extension Notification.Name {
    static let unauthorizedError = Notification.Name("unauthorizedError")
}

// MARK: - API Client
final class APIClient: Sendable {
    static let shared = APIClient(
        session: .shared,
        credentials: KeychainCredentialStore(),
        baseURL: Result { try APIConfiguration.baseURL() },
        notificationCenter: .default
    )

    /// Resolved once at startup; a misconfigured build fails on every request rather
    /// than falling back to a hardcoded host.
    private let baseURL: Result<String, Error>
    private let session: URLSession
    private let credentials: any CredentialStore
    private let notificationCenter: NotificationCenter
    private let refreshGate = RefreshGate()
    /// Every write to `credentials` and the read it depends on happen under this lock, so a
    /// sign-out cannot land between a refresh's check and its save.
    private let credentialLock = NSLock()

    /// An access token this close to `exp` is refreshed before it is sent rather than
    /// after the server rejects it.
    private static let refreshLeeway: TimeInterval = 60

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
        self.session = session
        self.credentials = credentials
        self.baseURL = baseURL
        self.notificationCenter = notificationCenter
    }

    /// Signed in means a refresh token is stored. Whether it still works is the server's
    /// call, made on the next refresh.
    var hasCredentials: Bool {
        credentials.load() != nil
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
        var request = try makeRequest(endpoint: endpoint, method: method, body: body)

        guard requiresAuth else {
            let (data, response) = try await send(request)
            return try decode(T.self, endpoint: endpoint, data: data, response: response)
        }

        let token = try await validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await send(request)

        // A 401 means the server refused the bearer before any handler ran, so sending
        // the request again cannot apply it twice. One retry only: a second 401 is final.
        if response.statusCode == 401 {
            let refreshed = try await refreshedAccessToken(replacing: token)
            request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
            (data, response) = try await send(request)
        }

        return try decode(T.self, endpoint: endpoint, data: data, response: response)
    }

    private func makeRequest(endpoint: String, method: HTTPMethod, body: [String: Any]?) throws -> URLRequest {
        guard let url = URL(string: try baseURL.get() + endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw APIError.invalidRequestBody
            }
        }

        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            return (data, httpResponse)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            // SwiftUI owns tasks such as pull-to-refresh and may cancel them when their
            // view disappears. Cancellation is control flow, not a failed connection.
            throw CancellationError()
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        endpoint: String,
        data: Data,
        response: HTTPURLResponse
    ) throws -> T {
        guard 200...299 ~= response.statusCode else {
            throw APIError.httpError(response.statusCode, message: Self.serverMessage(from: data))
        }

        // A 204 carries no body; decoding one is a failure that has nothing to report.
        if data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Log the JSON response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("❌ Decoding error for endpoint \(endpoint)")
                print("📄 JSON Response: \(jsonString)")
            }
            throw APIError.decodingError(error)
        }
    }

    /// The server's explanation for a rejection, from either error shape the API produces:
    /// its own `ErrorResponse`, or the validation dictionary `ModelState` returns.
    private static func serverMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }

        if let errors = json["errors"] as? [String: Any] {
            let messages = errors.values.compactMap { $0 as? [String] }.flatMap { $0 }
            if !messages.isEmpty { return messages.joined(separator: " ") }
        }

        return nil
    }

    // MARK: - Refresh

    /// The stored access token, refreshed first when it has expired or is about to.
    /// Reading `exp` only schedules a refresh; it never decides that the user is signed out.
    private func validAccessToken() async throws -> String {
        guard let stored = credentials.load() else {
            throw APIError.noAuthToken
        }

        if let expiry = stored.accessTokenExpiry,
           expiry.timeIntervalSinceNow <= Self.refreshLeeway {
            return try await refreshedAccessToken(replacing: stored.accessToken)
        }

        return stored.accessToken
    }

    /// Trades the refresh token for a new pair, unless another request already traded the
    /// one `stale` came from. Callers that arrive mid-refresh wait for that refresh instead
    /// of starting their own: two refreshes with the same token look like reuse to the
    /// server, which then revokes the whole sign-in.
    private func refreshedAccessToken(replacing stale: String) async throws -> String {
        try await refreshGate.run { [self] in
            guard let stored = credentials.load() else {
                throw APIError.noAuthToken
            }

            if stored.accessToken != stale {
                return stored.accessToken
            }

            return try await exchange(stored.refreshToken)
        }
    }

    /// A 401 is the only answer that ends the sign-in. A network failure or a 5xx keeps
    /// the stored pair so the next request can try again.
    private func exchange(_ refreshToken: String) async throws -> String {
        let request = try makeRequest(
            endpoint: "/auth/refresh",
            method: .POST,
            body: ["refreshToken": refreshToken]
        )
        let (data, response) = try await send(request)

        // A sign-out (or a new sign-in) while the refresh was in flight already decided
        // what the store holds. Acting on this answer would bring the old sign-in back, or
        // sign the new one out.
        if response.statusCode == 401 {
            if replaceCredentials(holding: refreshToken, with: nil) {
                print("🚨 Refresh token rejected - signing out")
                notificationCenter.post(name: .unauthorizedError, object: nil)
            }
        }

        let pair = try decode(RefreshResponse.self, endpoint: "/auth/refresh", data: data, response: response)

        guard replaceCredentials(holding: refreshToken, with: pair.credentials) else {
            throw APIError.noAuthToken
        }

        return pair.token
    }

    /// Writes `replacement` (or clears the store for nil) only while the store still holds
    /// `refreshToken`. Returns whether it did.
    private func replaceCredentials(holding refreshToken: String, with replacement: Credentials?) -> Bool {
        credentialLock.withLock {
            guard credentials.load()?.refreshToken == refreshToken else { return false }

            if let replacement {
                credentials.save(replacement)
            } else {
                credentials.clear()
            }
            return true
        }
    }

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
        credentialLock.withLock { credentials.save(response.credentials) }
        return response
    }

    /// Clears the stored pair at once, then asks the server to revoke the refresh token so
    /// a copy left behind stops working. The returned task is the revocation, which is
    /// best effort: no connection still signs out locally.
    @discardableResult
    func logout() -> Task<Void, Never> {
        let refreshToken = credentialLock.withLock {
            let refreshToken = credentials.load()?.refreshToken
            credentials.clear()
            return refreshToken
        }

        return Task { [self] in
            guard let refreshToken,
                  var request = try? makeRequest(
                      endpoint: "/auth/logout",
                      method: .POST,
                      body: ["refreshToken": refreshToken]
                  )
            else { return }

            request.timeoutInterval = 5
            _ = try? await send(request)
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
    case networkError(Error)
    case decodingError(Error)
    
    /// What to put on screen. The server's own `400` is the only thing that knows why a
    /// request the client believed in was refused, so it gets its own line rather than a
    /// raw `localizedDescription`.
    var displayMessage: String {
        switch self {
        case .httpError(_, .some(let message)): return message
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
        case .httpError(let code, _):
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
struct ExpenseSplitRequest {
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

/// Holds the one refresh in flight. Callers that arrive while it runs await the same task.
private actor RefreshGate {
    private var inFlight: Task<String, Error>?

    func run(_ refresh: @escaping @Sendable () async throws -> String) async throws -> String {
        if let inFlight {
            return try await inFlight.value
        }

        // Unstructured, so a caller whose task is cancelled cannot abandon a pair the server
        // has already rotated. The task clears itself before it finishes: a caller arriving
        // after that starts its own refresh rather than reusing a finished failure.
        let task = Task {
            do {
                let token = try await refresh()
                await finish()
                return token
            } catch {
                await finish()
                throw error
            }
        }
        inFlight = task
        return try await task.value
    }

    private func finish() {
        inFlight = nil
    }
}
