import Foundation
import Testing
@testable import Splitty

struct APIClientRefreshTests {

    @Test func aRejectedAccessTokenIsRefreshedAndTheRequestRetriedWithTheNewBearer() async throws {
        let stale = Credentials(accessToken: jwt(expiresIn: 600), refreshToken: "refresh-1")
        let fresh = jwt(expiresIn: 900)
        let store = InMemoryCredentialStore(stale)
        let server = StubServer { request in
            switch request.url?.path {
            case "/auth/refresh":
                return (200, json(["token": fresh, "refreshToken": "refresh-2"]))
            default:
                return request.bearer == fresh ? (200, json(["value": 42])) : (401, Data())
            }
        }

        let pong: Pong = try await server.client(credentials: store).request(endpoint: "/ping")

        #expect(pong.value == 42)
        #expect(server.requests(to: "/ping").map(\.bearer) == [stale.accessToken, fresh])
        let refresh = try #require(server.requests(to: "/auth/refresh").first)
        #expect(refresh.jsonBody?["refreshToken"] as? String == "refresh-1")
        #expect(refresh.bearer == nil)
        #expect(store.load() == Credentials(accessToken: fresh, refreshToken: "refresh-2"))
    }

    @Test func concurrentRejectionsShareOneRefresh() async throws {
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: 600), refreshToken: "refresh-1")
        )
        let fresh = jwt(expiresIn: 900)
        let server = StubServer { request in
            switch request.url?.path {
            case "/auth/refresh":
                // Slow enough that the other requests arrive while it is still running.
                Thread.sleep(forTimeInterval: 0.1)
                return (200, json(["token": fresh, "refreshToken": "refresh-2"]))
            default:
                return request.bearer == fresh ? (200, json(["value": 1])) : (401, Data())
            }
        }
        let client = server.client(credentials: store)

        async let first: Pong = client.request(endpoint: "/ping")
        async let second: Pong = client.request(endpoint: "/ping")
        async let third: Pong = client.request(endpoint: "/ping")
        let results = try await [first, second, third]

        #expect(results.count == 3)
        #expect(server.requests(to: "/auth/refresh").count == 1)
    }

    @Test func anExpiredAccessTokenIsRefreshedBeforeTheRequestGoesOut() async throws {
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: -60), refreshToken: "refresh-1")
        )
        let fresh = jwt(expiresIn: 900)
        let server = StubServer { request in
            switch request.url?.path {
            case "/auth/refresh":
                return (200, json(["token": fresh, "refreshToken": "refresh-2"]))
            default:
                return request.bearer == fresh ? (200, json(["value": 1])) : (401, Data())
            }
        }

        let _: Pong = try await server.client(credentials: store).request(endpoint: "/ping")

        #expect(server.requests.map(\.url?.path) == ["/auth/refresh", "/ping"])
        #expect(server.requests(to: "/ping").first?.bearer == fresh)
    }

    @Test func anAccessTokenAboutToExpireIsRefreshedFirst() async throws {
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: 30), refreshToken: "refresh-1")
        )
        let server = StubServer { request in
            request.url?.path == "/auth/refresh"
                ? (200, json(["token": jwt(expiresIn: 900), "refreshToken": "refresh-2"]))
                : (200, json(["value": 1]))
        }

        let _: Pong = try await server.client(credentials: store).request(endpoint: "/ping")

        #expect(server.requests.map(\.url?.path) == ["/auth/refresh", "/ping"])
    }

    @Test func aRejectedRefreshClearsTheStoreAndSignsOut() async throws {
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: 600), refreshToken: "refresh-1")
        )
        let server = StubServer { _ in (401, Data()) }
        let center = NotificationCenter()
        let signOuts = NotificationCounter(.unauthorizedError, on: center)

        await #expect(throws: APIError.self) {
            let _: Pong = try await server.client(credentials: store, notificationCenter: center)
                .request(endpoint: "/ping")
        }

        #expect(store.load() == nil)
        #expect(signOuts.count == 1)
        #expect(server.requests(to: "/ping").count == 1)
    }

    @Test func aRejectedRefreshFromAnEarlierSignInLeavesTheNewOneAlone() async throws {
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: 600), refreshToken: "refresh-1")
        )
        let newSignIn = Credentials(accessToken: jwt(expiresIn: 900), refreshToken: "refresh-new")
        let server = StubServer { request in
            if request.url?.path == "/auth/refresh" {
                // The user signs out and back in while this refresh is on the wire.
                store.save(newSignIn)
            }
            return (401, Data())
        }
        let center = NotificationCenter()
        let signOuts = NotificationCounter(.unauthorizedError, on: center)

        await #expect(throws: APIError.self) {
            let _: Pong = try await server.client(credentials: store, notificationCenter: center)
                .request(endpoint: "/ping")
        }

        #expect(store.load() == newSignIn)
        #expect(signOuts.count == 0)
    }

    @Test(arguments: [RefreshFailure.offline, .serverError])
    func aRefreshThatFailsWithoutAnAnswerKeepsTheSignIn(_ failure: RefreshFailure) async throws {
        let credentials = Credentials(accessToken: jwt(expiresIn: 600), refreshToken: "refresh-1")
        let store = InMemoryCredentialStore(credentials)
        let server = StubServer { request in
            guard request.url?.path == "/auth/refresh" else { return (401, Data()) }
            switch failure {
            case .offline: throw URLError(.notConnectedToInternet)
            case .serverError: return (503, Data())
            }
        }
        let center = NotificationCenter()
        let signOuts = NotificationCounter(.unauthorizedError, on: center)

        await #expect(throws: APIError.self) {
            let _: Pong = try await server.client(credentials: store, notificationCenter: center)
                .request(endpoint: "/ping")
        }

        #expect(store.load() == credentials)
        #expect(signOuts.count == 0)
    }

    @Test func aRejectionOfTheRetryIsFinal() async throws {
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: 600), refreshToken: "refresh-1")
        )
        let fresh = Credentials(accessToken: jwt(expiresIn: 900), refreshToken: "refresh-2")
        let server = StubServer { request in
            request.url?.path == "/auth/refresh"
                ? (200, json(["token": fresh.accessToken, "refreshToken": fresh.refreshToken]))
                : (401, Data())
        }
        let center = NotificationCenter()
        let signOuts = NotificationCounter(.unauthorizedError, on: center)

        await #expect {
            let _: Pong = try await server.client(credentials: store, notificationCenter: center)
                .request(endpoint: "/ping")
        } throws: { error in
            if case .httpError(401, _) = error as? APIError { return true }
            return false
        }

        #expect(server.requests(to: "/ping").count == 2)
        #expect(server.requests(to: "/auth/refresh").count == 1)
        #expect(store.load() == fresh)
        #expect(signOuts.count == 0)
    }

    @Test func anUnauthenticatedRequestIsNeverRefreshed() async throws {
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: -60), refreshToken: "refresh-1")
        )
        let server = StubServer { _ in (401, Data()) }

        await #expect(throws: APIError.self) {
            let _: Pong = try await server.client(credentials: store)
                .request(endpoint: "/ping", requiresAuth: false)
        }

        #expect(server.requests.map(\.url?.path) == ["/ping"])
        #expect(store.load() != nil)
    }

    @Test func signingInSavesBothTokens() async throws {
        let store = InMemoryCredentialStore()
        let access = jwt(expiresIn: 900)
        let server = StubServer { _ in
            (200, json([
                "token": access,
                "refreshToken": "refresh-1",
                "user": [
                    "id": 7, "name": "User 7", "email": "user7@example.com",
                    "createdAt": "", "updatedAt": ""
                ]
            ]))
        }

        let response = try await server.client(credentials: store).oauthGoogle(authCode: "code")

        #expect(response.user.id == 7)
        #expect(store.load() == Credentials(accessToken: access, refreshToken: "refresh-1"))
        #expect(server.requests.first?.bearer == nil)
    }

    @Test func loggingOutRevokesTheRefreshToken() async throws {
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: 600), refreshToken: "refresh-1")
        )
        let server = StubServer { _ in (204, Data()) }

        await server.client(credentials: store).logout().value

        let logout = try #require(server.requests(to: "/auth/logout").first)
        #expect(logout.httpMethod == "POST")
        #expect(logout.jsonBody?["refreshToken"] as? String == "refresh-1")
        #expect(store.load() == nil)
    }

    @Test func loggingOutClearsTheStoreEvenWhenTheServerCannotBeReached() async {
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: 600), refreshToken: "refresh-1")
        )
        let server = StubServer { _ in throw URLError(.notConnectedToInternet) }

        let revocation = server.client(credentials: store).logout()

        #expect(store.load() == nil)
        await revocation.value
        #expect(store.load() == nil)
    }
}

enum RefreshFailure: Sendable {
    case offline, serverError
}

private struct Pong: Codable {
    let value: Int
}

private final class NotificationCounter: @unchecked Sendable {
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
