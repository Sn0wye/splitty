import Foundation

extension Notification.Name {
    static let unauthorizedError = Notification.Name("unauthorizedError")
}

/// Owns the stored credentials: hands out an access token, refreshes it one exchange at
/// a time, and ends the sign-in only when the server rejects the refresh token.
final class TokenRefresher: Sendable {
    private let transport: APITransport
    private let credentials: any CredentialStore
    private let notificationCenter: NotificationCenter
    private let refreshGate = RefreshGate()
    /// Every write to `credentials` and the read it depends on happen under this lock, so a
    /// sign-out cannot land between a refresh's check and its save.
    private let credentialLock = NSLock()

    /// An access token this close to `exp` is refreshed before it is sent rather than
    /// after the server rejects it.
    private static let refreshLeeway: TimeInterval = 60

    init(transport: APITransport, credentials: any CredentialStore, notificationCenter: NotificationCenter) {
        self.transport = transport
        self.credentials = credentials
        self.notificationCenter = notificationCenter
    }

    /// Signed in means a refresh token is stored. Whether it still works is the server's
    /// call, made on the next refresh.
    var hasCredentials: Bool {
        credentials.load() != nil
    }

    func save(_ pair: Credentials) {
        credentialLock.withLock { credentials.save(pair) }
    }

    /// Clears the store and returns the refresh token it held, for the server to revoke.
    func clear() -> String? {
        credentialLock.withLock {
            let refreshToken = credentials.load()?.refreshToken
            credentials.clear()
            return refreshToken
        }
    }

    /// The stored access token, refreshed first when it has expired or is about to.
    /// Reading `exp` only schedules a refresh; it never decides that the user is signed out.
    func validAccessToken() async throws -> String {
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
    func refreshedAccessToken(replacing stale: String) async throws -> String {
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
        let request = try transport.makeRequest(
            endpoint: "/auth/refresh",
            method: .POST,
            body: ["refreshToken": refreshToken]
        )
        let (data, response) = try await transport.send(request)

        // A sign-out (or a new sign-in) while the refresh was in flight already decided
        // what the store holds. Acting on this answer would bring the old sign-in back, or
        // sign the new one out.
        if response.statusCode == 401 {
            if replaceCredentials(holding: refreshToken, with: nil) {
                print("🚨 Refresh token rejected - signing out")
                notificationCenter.post(name: .unauthorizedError, object: nil)
            }
        }

        let pair = try transport.decode(RefreshResponse.self, endpoint: "/auth/refresh", data: data, response: response)

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
}

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
