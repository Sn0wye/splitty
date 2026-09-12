//
//  AppearanceView.swift
//  Splitty
//

import SwiftUI

struct AppearanceView: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        List {
            Section {
                ForEach(AppTheme.allCases) { theme in
                    themeRow(theme)
                }
            } footer: {
                Text("System follows your device's light and dark appearance.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("background").ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func themeRow(_ theme: AppTheme) -> some View {
        Button {
            guard themeManager.theme != theme else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                themeManager.theme = theme
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: theme.icon)
                    .font(.body)
                    .foregroundStyle(Color("muted-foreground"))
                    .frame(width: 24)

                Text(theme.title)
                    .foregroundStyle(Color("foreground"))

                Spacer()

                if themeManager.theme == theme {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color("foreground"))
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        AppearanceView()
    }
}
