import Foundation
import SwiftUI

@MainActor
protocol AuthenticationSource {
    func isAuthenticated() -> Bool
    func currentUser() async throws -> User
    func logout()
    /// Who the stored credentials name, read without a network. Nil when unknown.
    func storedUser() -> User?
}

extension AuthenticationSource {
    func storedUser() -> User? { nil }
}

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false

    /// Who is signed in. Everything that says "you" — the default payer, the checkbox
    /// defaults, whether a row reads *lent* or *borrowed* — reads this. Not cached in
    /// UserDefaults: the credentials already live in the Keychain, and one request on launch
    /// cannot go stale the way a second copy of the profile can.
    @Published var currentUser: User?

    static let shared = AuthenticationManager()

    private let source: any AuthenticationSource

    private convenience init() {
        self.init(source: AuthService.shared)
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
            print("🔴 Refresh token rejected - forcing logout")
            Task { @MainActor in self?.logout() }
        }
    }

    func checkAuthenticationStatus() {
        if PerformanceScenarioLaunch.isEnabled {
            isAuthenticated = true
            currentUser = PerformanceScenarios.profileUser
            return
        }
        isAuthenticated = source.isAuthenticated()
    }

    /// A stored refresh token decides the first screen, however old the access token is;
    /// the profile fetch fills `currentUser` when one exists. There is no cosmetic delay.
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

    func updateCurrentUser(_ user: User) {
        guard currentUser?.id == user.id else { return }
        currentUser = user
    }

    /// Fills in `currentUser` on a cold launch that skipped the sign-in screen. The request
    /// refreshes an expired access token first, so a 401 here means the server rejected
    /// the refresh token too. A network blip leaves the session alone for a later screen
    /// to retry, but a server that answers and does not recognize the user means there is
    /// no session to keep: log out so the login screen shows instead of a
    /// half-authenticated app.
    func hydrateCurrentUser() async {
        guard isAuthenticated, currentUser == nil else { return }

        do {
            currentUser = try await source.currentUser()
        } catch let error as APIError {
            switch error {
            case .httpError(400..<500, _), .noAuthToken:
                print("🔴 Server rejected the stored session (\(error)) - forcing logout")
                logout()
            default:
                print("⚠️ Could not load the signed-in profile: \(error.localizedDescription)")
                useStoredUser()
            }
        } catch {
            print("⚠️ Could not load the signed-in profile: \(error.localizedDescription)")
            useStoredUser()
        }
    }

    /// With no network the profile cannot load, but the groups and writes this device kept
    /// are keyed by user: the stored token says whose they are, so the app opens on them
    /// (ADR 0008). The next successful profile read replaces this.
    private func useStoredUser() {
        guard currentUser == nil, let stored = source.storedUser() else { return }
        currentUser = stored
        Task { [weak self] in
            // Fill in the real profile once the network is back.
            for delay in [5, 15, 30, 60, 120] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, self.isAuthenticated, self.currentUser?.id == stored.id else { return }
                if let user = try? await self.source.currentUser() {
                    self.updateCurrentUser(user)
                    return
                }
            }
        }
    }

    func logout() {
        source.logout()
        currentUser = nil
        isAuthenticated = false
    }
}
