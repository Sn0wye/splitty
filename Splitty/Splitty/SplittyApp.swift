import SwiftUI

@main
struct SplittyApp: App {
    init() {
        PerformanceSignpost.beginLaunch()
        PerformanceScenarioLaunch.logDeviceConditions()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    private enum OnboardingState: Equatable {
        case checking
        case needed
        case complete
    }

    @State private var showingSplash = true
    @State private var onboardingState = OnboardingState.checking
    @State private var resolvedOnboardingUserId: Int?
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var appState = AppState()
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ZStack {
            SwiftUI.Group {
                if authManager.isAuthenticated,
                   let user = authManager.currentUser,
                   resolvedOnboardingUserId == user.id,
                   onboardingState == .needed {
                    OnboardingView {
                        finishOnboarding(for: user.id, opening: $0)
                    }
                } else if authManager.isAuthenticated,
                          let user = authManager.currentUser,
                          (resolvedOnboardingUserId != user.id || onboardingState == .checking
                           || appState.signedInUserId != user.id) {
                    SplittyLoader()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color("background"))
                } else if authManager.isAuthenticated {
                    ContentView()
                        .environmentObject(appState)
                } else {
                    LoginView()
                }
            }
            // L10n reads the stored preference rather than the environment, so
            // changing it has to rebuild the tree for already-rendered copy to
            // follow. Scoped to the content: the modifiers below keep their
            // identity so `task` and `onOpenURL` don't re-fire on a switch.
            .id(languageManager.language)
            .allowsHitTesting(!showingSplash)
            .accessibilityHidden(showingSplash)

            if showingSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showingSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        // Set on the root so sheets and the login screen follow the choice too.
        .preferredColorScheme(themeManager.theme.colorScheme)
        .environment(\.locale, languageManager.locale)
        .task {
            PerformanceSignpost.endLaunch()
            await authManager.restoreSession()
        }
        .task(id: authManager.currentUser?.id) {
            await resolveOnboarding()
        }
        .onChange(of: authManager.currentUser?.id, initial: true) { _, userId in
            appState.setSignedInUser(userId)
        }
        .onOpenURL { url in
            GoogleSignInService.handle(url)
        }
    }

    private func resolveOnboarding() async {
        guard let userId = authManager.currentUser?.id else {
            resolvedOnboardingUserId = nil
            onboardingState = .checking
            return
        }
        guard !PerformanceScenarioLaunch.isEnabled,
              !UserDefaults.standard.bool(forKey: onboardingKey(for: userId)) else {
            resolvedOnboardingUserId = userId
            onboardingState = .complete
            return
        }

        onboardingState = .checking
        do {
            let groups = try await GroupService.shared.getGroups()
            guard !Task.isCancelled, authManager.currentUser?.id == userId else { return }
            resolvedOnboardingUserId = userId
            onboardingState = groups.isEmpty ? .needed : .complete
            if !groups.isEmpty {
                UserDefaults.standard.set(true, forKey: onboardingKey(for: userId))
            }
        } catch {
            // A network error must not trap someone behind setup.
            guard !Task.isCancelled, authManager.currentUser?.id == userId else { return }
            resolvedOnboardingUserId = userId
            onboardingState = .complete
        }
    }

    private func finishOnboarding(for userId: Int, opening groupId: Int?) {
        UserDefaults.standard.set(true, forKey: onboardingKey(for: userId))
        resolvedOnboardingUserId = userId
        onboardingState = .complete
        if let groupId { appState.openGroup(groupId) }
    }

    private func onboardingKey(for userId: Int) -> String {
        "onboarding.completed.\(userId)"
    }
}
