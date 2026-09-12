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

    var body: some View {
        NavigationStack {
            List {
                Section("Preferences") {
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "paintbrush")
                                .foregroundStyle(Color("muted-foreground"))
                                .frame(width: 24)

                            Text("Appearance")

                            Spacer()

                            Text(themeManager.theme.title)
                                .foregroundStyle(Color("muted-foreground"))
                        }
                        .frame(minHeight: 44)
                    }
                }

                Section("Account") {
                    Button(action: {
                        showingLogoutAlert = true
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                            Text("Log Out")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("background"))
            .navigationTitle("Settings")
            .alert("Log Out", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    authManager.logout()
                }
            } message: {
                Text("Are you sure you want to log out?")
            }
        }
    }
}

#Preview {
    SettingsView()
}
