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
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var inviteCoordinator = InviteLinkCoordinator()
    @StateObject private var appState = AppState()
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ZStack {
            if authManager.isAuthenticated {
                ContentView()
                    .environmentObject(appState)
            } else {
                LoginView()
            }
        }
        // Set on the root so sheets and the login screen follow the choice too.
        .preferredColorScheme(themeManager.theme.colorScheme)
        .environment(\.locale, languageManager.locale)
        .task {
            PerformanceSignpost.endLaunch()
            await authManager.restoreSession()
        }
        .onOpenURL(perform: handle)
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            handle(url)
        }
        .sheet(item: inviteToPresent) { invite in
            InviteConfirmationSheet(code: invite.code) { group in
                inviteCoordinator.clearPendingInvite()
                appState.openGroup(group.id)
            }
        }
        .alert(Text(L10n.Invite.linkAlert), isPresented: invalidLinkAlert) {
            Button(role: .cancel) {} label: { Text(L10n.Common.ok) }
        } message: {
            Text(inviteCoordinator.invalidLinkMessage ?? "")
        }
    }

    private var inviteToPresent: Binding<PendingInvite?> {
        Binding(
            get: { inviteCoordinator.inviteToPresent(isAuthenticated: authManager.isAuthenticated) },
            set: { invite in
                if invite == nil { inviteCoordinator.clearPendingInvite() }
            }
        )
    }

    private var invalidLinkAlert: Binding<Bool> {
        Binding(
            get: { inviteCoordinator.invalidLinkMessage != nil },
            set: { isPresented in
                if !isPresented { inviteCoordinator.invalidLinkMessage = nil }
            }
        )
    }

    private func handle(_ url: URL) {
        if inviteCoordinator.receive(url) == .googleSignIn {
            GoogleSignInService.handle(url)
        }
    }
}
