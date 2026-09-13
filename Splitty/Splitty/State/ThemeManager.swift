//
//  ThemeManager.swift
//  Splitty
//

import SwiftUI

/// The appearance the user picked in Settings. `system` follows iOS.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L10n.Appearance.system
        case .light: L10n.Appearance.light
        case .dark: L10n.Appearance.dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "iphone"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// `nil` hands the choice back to iOS.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Holds the appearance preference and writes it through to UserDefaults so the
/// app opens in the same theme it was closed in.
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let themeKey = "appTheme"

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.themeKey)
        theme = stored.flatMap(AppTheme.init(rawValue:)) ?? .system
    }
}
