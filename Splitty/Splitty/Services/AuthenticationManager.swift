import Foundation
import SwiftUI

@MainActor
protocol AuthenticationSource {
    func isAuthenticated() -> Bool
    func currentUser() async throws -> User
}

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false

    /// Who is signed in. Everything that says "you" — the default payer, the checkbox
    /// defaults, whether a row reads *lent* or *borrowed* — reads this. Not cached in
    /// UserDefaults: the token already lives in the Keychain, and one request on launch
    /// cannot go stale the way a second copy of the profile can.
    @Published var currentUser: User?

    static let shared = AuthenticationManager()

    private let source: (any AuthenticationSource)?

    private init() {
        source = nil
        checkAuthenticationStatus()
        setupUnauthorizedObserver()
    }

    init(source: any AuthenticationSource) {
        self.source = source
        checkAuthenticationStatus()
        setupUnauthorizedObserver()
    }

    private func setupUnauthorizedObserver() {
        NotificationCenter.default.addObserver(
            forName: .unauthorizedError,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("🔴 Received 401 unauthorized - forcing logout")
            Task { @MainActor in self?.logout() }
        }
    }

    func checkAuthenticationStatus() {
        if PerformanceScenarioLaunch.isEnabled {
            isAuthenticated = true
            currentUser = PerformanceScenarios.profileUser
            return
        }
        isAuthenticated = source?.isAuthenticated() ?? AuthService.shared.isAuthenticated()
    }

    /// Token presence decides the first screen; the profile fetch fills `currentUser`
    /// when a token exists. There is no cosmetic delay.
    func restoreSession() async {
        if PerformanceScenarioLaunch.isEnabled {
            isAuthenticated = true
            currentUser = PerformanceScenarios.profileUser
            return
        }
        checkAuthenticationStatus()
        await hydrateCurrentUser()
    }

    func login(user: User) {
        currentUser = user
        isAuthenticated = true
    }

    /// Fills in `currentUser` on a cold launch that skipped the sign-in screen. A network
    /// blip leaves the session alone for a later screen to retry, but a server that
    /// answers and does not recognize the token's user (a stale Keychain token against a
    /// reset database) means there is no session to keep: log out so the login screen
    /// shows instead of a half-authenticated app.
    func hydrateCurrentUser() async {
        guard isAuthenticated, currentUser == nil else { return }

        do {
            if let source {
                currentUser = try await source.currentUser()
            } else {
                currentUser = try await AuthService.shared.getCurrentUser()
            }
        } catch let error as APIError {
            switch error {
            case .httpError(400..<500, _), .noAuthToken:
                print("🔴 Server rejected the stored session (\(error)) - forcing logout")
                logout()
            default:
                print("⚠️ Could not load the signed-in profile: \(error.localizedDescription)")
            }
        } catch {
            print("⚠️ Could not load the signed-in profile: \(error.localizedDescription)")
        }
    }

    func logout() {
        AuthService.shared.logout()
        currentUser = nil
        isAuthenticated = false
    }
}
