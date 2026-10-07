//
//  SettingsView.swift
//  Splitty
//
//  Created by Snowye on 19/11/25.
//

import SwiftUI

struct SettingsView: View {
    private enum AccountClosure {
        case deactivate, delete

        var rowTitle: String {
            switch self {
            case .deactivate: L10n.Settings.deactivateAccount
            case .delete: L10n.Settings.deleteAccount
            }
        }

        var systemImage: String {
            switch self {
            case .deactivate: "pause.circle"
            case .delete: "trash"
            }
        }

        var alertTitle: String {
            switch self {
            case .deactivate: L10n.Settings.deactivateTitle
            case .delete: L10n.Settings.deleteTitle
            }
        }

        var alertMessage: String {
            switch self {
            case .deactivate: L10n.Settings.deactivateMessage
            case .delete: L10n.Settings.deleteMessage
            }
        }

        var confirmLabel: String {
            switch self {
            case .deactivate: L10n.Settings.deactivate
            case .delete: L10n.Common.delete
            }
        }
    }

    @State private var showingLogoutAlert = false
    /// The closure awaiting confirmation.
    @State private var pendingClosure: AccountClosure?
    @State private var showingAccountDeleted = false
    /// The closure request in flight. Both rows stay disabled while it is set.
    @State private var closingAccount: AccountClosure?
    @State private var closureErrorMessage: String?
    @State private var showingOnboardingReview = false
    @StateObject private var authManager = AuthenticationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let user = authManager.currentUser {
                        NavigationLink {
                            ProfileView(user: user)
                        } label: {
                            HStack(spacing: 12) {
                                MemberAvatar(display: MemberDisplay(user), size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name)
                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundStyle(Color("muted-foreground"))
                                }
                            }
                            .frame(minHeight: 44)
                        }
                    }

                    Button(action: {
                        showingLogoutAlert = true
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                            Text(L10n.Settings.logOut)
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text(L10n.Settings.account)
                }

                Section {
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "paintbrush")
                                .foregroundStyle(Color("muted-foreground"))
                                .frame(width: 24)

                            Text(L10n.Settings.appearance)

                            Spacer()

                            Text(themeManager.theme.title)
                                .foregroundStyle(Color("muted-foreground"))
                        }
                        .frame(minHeight: 44)
                    }

                    NavigationLink {
                        LanguageView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "globe")
                                .foregroundStyle(Color("muted-foreground"))
                                .frame(width: 24)

                            Text(L10n.Settings.language)

                            Spacer()

                            Text(languageManager.language.displayName)
                                .foregroundStyle(Color("muted-foreground"))
                        }
                        .frame(minHeight: 44)
                    }
                } header: {
                    Text(L10n.Settings.preferences)
                }

                closeAccountSection

                #if DEBUG
                Section("Development") {
                    Button {
                        showingOnboardingReview = true
                    } label: {
                        Label("Review onboarding", systemImage: "rectangle.on.rectangle")
                    }
                }
                #endif

                Section {
                    aboutFooter
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color("background"))
            .navigationTitle(Text(L10n.Settings.title))
            .fullScreenCover(isPresented: $showingOnboardingReview) {
                OnboardingReviewView()
            }
            .alert(Text(L10n.Settings.logOut), isPresented: $showingLogoutAlert) {
                Button(role: .cancel) { } label: { Text(L10n.Common.cancel) }
                Button(role: .destructive) {
                    authManager.logout()
                } label: { Text(L10n.Settings.logOut) }
            } message: {
                Text(L10n.Settings.logOutConfirm)
            }
            .alert(
                pendingClosure?.alertTitle ?? "",
                isPresented: Binding(
                    get: { pendingClosure != nil },
                    set: { if !$0 { pendingClosure = nil } }
                ),
                presenting: pendingClosure
            ) { closure in
                Button(role: .cancel) { pendingClosure = nil } label: { Text(L10n.Common.cancel) }
                Button(role: .destructive) {
                    pendingClosure = nil
                    Task { await closeAccount(closure) }
                } label: { Text(closure.confirmLabel) }
            } message: { closure in
                Text(closure.alertMessage)
            }
            .alert(Text(L10n.Settings.accountDeleted), isPresented: $showingAccountDeleted) {
                Button { authManager.logout() } label: { Text(L10n.Common.ok) }
            }
            .alert(
                Text(L10n.Settings.closeAccountFailed),
                isPresented: Binding(
                    get: { closureErrorMessage != nil },
                    set: { if !$0 { closureErrorMessage = nil } }
                )
            ) {
                Button(L10n.Common.ok, role: .cancel) { closureErrorMessage = nil }
            } message: {
                Text(closureErrorMessage ?? "")
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(Color("background"))
    }

    // MARK: - Close account

    private var closeAccountSection: some View {
        Section {
            closureRow(.deactivate)
            closureRow(.delete)
        } header: {
            Text(L10n.Settings.closeAccount)
        }
        .disabled(closingAccount != nil)
    }

    private func closureRow(_ closure: AccountClosure) -> some View {
        Button(role: .destructive) {
            pendingClosure = closure
        } label: {
            HStack {
                Label(closure.rowTitle, systemImage: closure.systemImage)
                    .foregroundStyle(.red)
                Spacer()
                if closingAccount == closure {
                    ProgressView()
                }
            }
            .frame(minHeight: 44)
        }
    }

    /// Failure leaves the user signed in so they can retry. Success never re-enables the
    /// rows: the next step is signing out.
    private func closeAccount(_ closure: AccountClosure) async {
        closingAccount = closure
        do {
            switch closure {
            case .deactivate:
                try await ProfileService.shared.deactivateAccount()
                authManager.logout()
            case .delete:
                try await ProfileService.shared.deleteAccount()
                // Revoked before the confirmation rather than after it: the old tokens are
                // dead now, and any 401 while the alert is up fails its refresh and signs
                // out without waiting.
                await GoogleSignInService.shared.disconnect()
                showingAccountDeleted = true
            }
        } catch {
            closingAccount = nil
            closureErrorMessage = error.displayMessage
        }
    }

    /// The lockup and build, signed off at the foot of the list. One line, not stacked: the
    /// list does not scroll on a tall phone, so a second line ends up under the add button.
    private var aboutFooter: some View {
        HStack(alignment: .center, spacing: 8) {
            Image("Lockup")
                .resizable()
                .scaledToFit()
                .frame(height: 40)
                .accessibilityLabel(Text(verbatim: "Splitty"))

            if let version = Self.version {
                Text(verbatim: version)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color("muted-foreground"))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static var version: String? {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return nil }
        guard let build = info?["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }
}

#Preview {
    SettingsView()
}
