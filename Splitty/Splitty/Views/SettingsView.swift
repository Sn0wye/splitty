//
//  SettingsView.swift
//  Splitty
//
//  Created by Snowye on 19/11/25.
//

import SwiftUI

struct SettingsView: View {
    @State private var showingLogoutAlert = false
    @StateObject private var authManager = AuthenticationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        NavigationStack {
            List {
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

                Section {
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
            }
            .scrollContentBackground(.hidden)
            .background(Color("background"))
            .navigationTitle(Text(L10n.Settings.title))
            .alert(Text(L10n.Settings.logOut), isPresented: $showingLogoutAlert) {
                Button(role: .cancel) { } label: { Text(L10n.Common.cancel) }
                Button(role: .destructive) {
                    authManager.logout()
                } label: { Text(L10n.Settings.logOut) }
            } message: {
                Text(L10n.Settings.logOutConfirm)
            }
        }
    }
}

#Preview {
    SettingsView()
}
