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
}
