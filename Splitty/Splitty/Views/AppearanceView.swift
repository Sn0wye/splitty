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
                Text(L10n.Appearance.footer)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("background").ignoresSafeArea())
        .navigationTitle(Text(L10n.Appearance.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func themeRow(_ theme: AppTheme) -> some View {
        Button {
            select(theme)
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

    /// A colour scheme change ignores `withAnimation` and flips the whole screen
    /// between two frames. A snapshot of the old screen fades out over the new
    /// one instead. Opacity only, so it stays under Reduce Motion.
    private func select(_ theme: AppTheme) {
        guard themeManager.theme != theme else { return }
        guard let window = Self.keyWindow,
              let snapshot = window.snapshotView(afterScreenUpdates: false) else {
            themeManager.theme = theme
            return
        }
        // Taps reach the rows underneath, so a quick second pick still lands.
        snapshot.isUserInteractionEnabled = false
        window.addSubview(snapshot)
        themeManager.theme = theme
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            snapshot.alpha = 0
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

#Preview {
    NavigationStack {
        AppearanceView()
    }
}
