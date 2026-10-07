import Foundation
import Testing
@testable import Splitty

@MainActor
struct SessionRestorationTests {

    @Test func aStoredTokenSelectsTheSignedInScreenAndHydratesTheProfile() async {
        let user = TestExpense.user(7)
        let session = StubAuthenticationSource(hasValidToken: true, user: user)
        let manager = AuthenticationManager(source: session)

        await manager.restoreSession()

        #expect(manager.isAuthenticated)
        #expect(manager.currentUser?.id == 7)
    }

    @Test func launchingWithoutATokenStaysSignedOutAndDoesNotFetchAProfile() async {
        let session = StubAuthenticationSource(hasValidToken: false, user: TestExpense.user(7))
        let manager = AuthenticationManager(source: session)

        await manager.restoreSession()

        #expect(!manager.isAuthenticated)
        #expect(manager.currentUser == nil)
    }

    @Test func restoringASessionDoesNotInsertAFixedDelay() async {
        let session = StubAuthenticationSource(hasValidToken: true, user: TestExpense.user(1))
        let manager = AuthenticationManager(source: session)

        let elapsed = await ContinuousClock().measure {
            await manager.restoreSession()
        }

        #expect(elapsed < .milliseconds(100))
    }

    @Test func aStoredRefreshTokenOutlivesAnExpiredAccessToken() async {
        let fresh = jwt(expiresIn: 900)
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: -3600), refreshToken: "refresh-1")
        )
        let server = StubServer { request in
            switch request.url?.path {
            case "/auth/refresh":
                return (200, json(["token": fresh, "refreshToken": "refresh-2"]))
            case "/profile" where request.bearer == fresh:
                return (200, json(["id": 7, "name": "User 7", "email": "user7@example.com"]))
            default:
                return (401, Data())
            }
        }
        let manager = AuthenticationManager(source: AuthService(client: server.client(credentials: store)))

        await manager.restoreSession()

        #expect(manager.isAuthenticated)
        #expect(manager.currentUser?.id == 7)
        #expect(server.requests.map(\.url?.path) == ["/auth/refresh", "/profile"])
    }

    @Test func noStoredRefreshTokenRestoresSignedOut() async {
        let server = StubServer { _ in (500, Data()) }
        let manager = AuthenticationManager(
            source: AuthService(client: server.client(credentials: InMemoryCredentialStore()))
        )

        await manager.restoreSession()

        #expect(!manager.isAuthenticated)
        #expect(server.requests.isEmpty)
    }

    @Test func aRejectedRefreshOnLaunchSignsOut() async {
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: -3600), refreshToken: "refresh-1")
        )
        let server = StubServer { _ in (401, Data()) }
        let manager = AuthenticationManager(source: AuthService(client: server.client(credentials: store)))

        await manager.restoreSession()

        #expect(!manager.isAuthenticated)
        #expect(manager.currentUser == nil)
        #expect(store.load() == nil)
    }

    @Test func aRefreshThatCannotReachTheServerOnLaunchStaysSignedIn() async {
        let store = InMemoryCredentialStore(
            Credentials(accessToken: jwt(expiresIn: -3600), refreshToken: "refresh-1")
        )
        let server = StubServer { _ in throw URLError(.notConnectedToInternet) }
        let manager = AuthenticationManager(source: AuthService(client: server.client(credentials: store)))

        await manager.restoreSession()

        #expect(manager.isAuthenticated)
        #expect(store.load() != nil)
    }
}

@MainActor
private final class StubAuthenticationSource: AuthenticationSource {
    var hasValidToken: Bool
    var user: User

    init(hasValidToken: Bool, user: User) {
        self.hasValidToken = hasValidToken
        self.user = user
    }

    func isAuthenticated() -> Bool { hasValidToken }

    func currentUser() async throws -> User { user }

    func logout() {}
}
