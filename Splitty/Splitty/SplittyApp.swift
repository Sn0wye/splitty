import SwiftUI

@main
struct SplittyApp: App {
    init() {
        PerformanceSignpost.beginLaunch()
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

    var body: some View {
        ZStack {
            if authManager.isAuthenticated {
                ContentView()
            } else {
                LoginView()
            }
        }
        .task {
            PerformanceSignpost.endLaunch()
            await authManager.restoreSession()
        }
    }
}
