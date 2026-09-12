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
                // The Google SDK completes sign-in through the reversed-client-id scheme.
                .onOpenURL { url in
                    GoogleSignInService.handle(url)
                }
        }
    }
}

struct RootView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        ZStack {
            if authManager.isAuthenticated {
                ContentView()
            } else {
                LoginView()
            }
        }
        // Set on the root so sheets and the login screen follow the choice too.
        .preferredColorScheme(themeManager.theme.colorScheme)
        .task {
            PerformanceSignpost.endLaunch()
            await authManager.restoreSession()
        }
    }
}
