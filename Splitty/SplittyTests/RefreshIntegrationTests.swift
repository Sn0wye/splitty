import Foundation
import Testing
@testable import Splitty

/// Runs the real `APIClient` against a real local API, so the server's rotation and reuse
/// detection are the real thing. Opt in with `TEST_RUNNER_SPLITTY_INTEGRATION_API`, e.g.
/// `http://localhost:5199`, pointing at a Development host seeded with `john@example.com`.
@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SPLITTY_INTEGRATION_API"] != nil)
)
struct RefreshIntegrationTests {
    private let baseURL = ProcessInfo.processInfo.environment["SPLITTY_INTEGRATION_API"] ?? ""

    private func signedInClient() async throws -> (APIClient, InMemoryCredentialStore, SignOutCounter) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LossyForwardingProtocol.self]
        let store = InMemoryCredentialStore()
        let center = NotificationCenter()
        let signOuts = SignOutCounter(.unauthorizedError, on: center)
        let client = APIClient(
            session: URLSession(configuration: configuration),
            credentials: store,
            baseURL: baseURL,
            notificationCenter: center
        )
        LossyForwardingProtocol.reset()
        _ = try await client.devLogin(email: "john@example.com")
        return (client, store, signOuts)
    }

    /// Fifteen minutes on, as far as the client can tell.
    private func expireAccessToken(in store: InMemoryCredentialStore) throws {
        let stored = try #require(store.load())
        store.save(Credentials(accessToken: jwt(expiresIn: -60), refreshToken: stored.refreshToken))
    }

    @Test func anExpiredAccessTokenRefreshesAgainstTheRealServer() async throws {
        let (client, store, signOuts) = try await signedInClient()
        let before = try #require(store.load())
        try expireAccessToken(in: store)

        let profile: ProfileResponse = try await client.request(endpoint: "/profile")

        #expect(profile.email == "john@example.com")
        let after = try #require(store.load())
        #expect(after.refreshToken != before.refreshToken)
        #expect(LossyForwardingProtocol.refreshCount == 1)
        #expect(signOuts.count == 0)
    }

    @Test func concurrentRequestsShareOneRefreshAndTheSignInSurvives() async throws {
        let (client, store, signOuts) = try await signedInClient()
        try expireAccessToken(in: store)

        async let first: ProfileResponse = client.request(endpoint: "/profile")
        async let second: [Group] = client.request(endpoint: "/group")
        async let third: ProfileResponse = client.request(endpoint: "/profile")
        _ = try await (first, second, third)

        #expect(LossyForwardingProtocol.refreshCount == 1)
        #expect(signOuts.count == 0)

        // The rotated token still works, so the server never saw reuse.
        try expireAccessToken(in: store)
        let _: ProfileResponse = try await client.request(endpoint: "/profile")
        #expect(signOuts.count == 0)
    }

    /// The server rotates the refresh token, then the connection drops before the client
    /// reads the answer. Pins a known limitation, not a goal: the client still holds the
    /// token the server already used, so its next refresh reads as reuse and the server
    /// revokes the whole family. Fixing it needs a reuse grace period on the server.
    @Test func aLostRefreshResponseEndsTheSignIn() async throws {
        let (client, store, signOuts) = try await signedInClient()
        let original = try #require(store.load())
        try expireAccessToken(in: store)
        LossyForwardingProtocol.dropNextRefreshResponse = true

        await #expect(throws: APIError.self) {
            let _: ProfileResponse = try await client.request(endpoint: "/profile")
        }
        let rotatedByServer = try #require(LossyForwardingProtocol.droppedRefreshToken)
        print("🧪 after the lost response: store holds the original refresh token =",
              store.load()?.refreshToken == original.refreshToken,
              "signOuts =", signOuts.count)
        #expect(store.load()?.refreshToken == original.refreshToken)
        #expect(signOuts.count == 0)

        // Connection back. The client still holds the token the server already used.
        var nextRequestSucceeded = false
        do {
            let _: ProfileResponse = try await client.request(endpoint: "/profile")
            nextRequestSucceeded = true
        } catch {
            print("🧪 next request after reconnecting failed:", error)
        }
        print("🧪 next request succeeded =", nextRequestSucceeded,
              "store empty =", store.load() == nil,
              "signOuts =", signOuts.count)

        // What the server now thinks of the token it rotated to, which the client never saw.
        var probe = URLRequest(url: URL(string: baseURL + "/auth/refresh")!)
        probe.httpMethod = "POST"
        probe.setValue("application/json", forHTTPHeaderField: "Content-Type")
        probe.httpBody = json(["refreshToken": rotatedByServer])
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: probe)
        let rotatedStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("🧪 server's answer for the token it rotated to:", rotatedStatus)

        // The risk, as predicted: the stale token reads as reuse, so the whole family dies.
        #expect(!nextRequestSucceeded)
        #expect(store.load() == nil)
        #expect(signOuts.count == 1)
        #expect(rotatedStatus == 401)
    }
}

private final class SignOutCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var received = 0
    private var observer: NSObjectProtocol?

    init(_ name: Notification.Name, on center: NotificationCenter) {
        observer = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            self?.increment()
        }
    }

    private func increment() {
        lock.withLock { received += 1 }
    }

    var count: Int { lock.withLock { received } }
}

/// Forwards every request to the real server. When armed, it forwards one `/auth/refresh`,
/// lets the server rotate the token, records what the server sent back, and reports a lost
/// connection to the client instead.
private final class LossyForwardingProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _drop = false
    nonisolated(unsafe) private static var _dropped: String?
    nonisolated(unsafe) private static var _refreshCount = 0

    static var dropNextRefreshResponse: Bool {
        get { lock.withLock { _drop } }
        set { lock.withLock { _drop = newValue } }
    }
    static var droppedRefreshToken: String? { lock.withLock { _dropped } }
    static var refreshCount: Int { lock.withLock { _refreshCount } }

    static func reset() {
        lock.withLock { _drop = false; _dropped = nil; _refreshCount = 0 }
    }

    private static let upstream = URLSession(configuration: .ephemeral)
    private var upstreamTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var forwarded = request
        if forwarded.httpBody == nil, let stream = forwarded.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            stream.close()
            forwarded.httpBody = data
        }

        let isRefresh = forwarded.url?.path == "/auth/refresh"
        let drop = isRefresh && Self.lock.withLock {
            Self._refreshCount += 1
            defer { Self._drop = false }
            return Self._drop
        }

        upstreamTask = Self.upstream.dataTask(with: forwarded) { [weak self] data, response, error in
            guard let self else { return }
            if drop {
                let token = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["refreshToken"] as? String
                Self.lock.withLock { Self._dropped = token }
                self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                return
            }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            self.client?.urlProtocol(self, didReceive: response!, cacheStoragePolicy: .notAllowed)
            if let data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        upstreamTask?.resume()
    }

    override func stopLoading() {
        upstreamTask?.cancel()
    }
}
