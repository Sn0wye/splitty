//
//  LanguageManager.swift
//  Splitty
//

import SwiftUI

/// Languages the app can render. New cases are added here when a translation ships.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Autonym — shown in the language itself, not translated through L10n.
    var displayName: String {
        switch self {
        case .english: "English"
        }
    }

    /// Readable from any isolation so copy can resolve without hopping to the main actor.
    /// Takes its store so tests can read a preference that isn't the shared one.
    nonisolated static func current(in defaults: UserDefaults = .standard) -> AppLanguage {
        let stored = defaults.string(forKey: storageKey)
        return stored.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    nonisolated static var current: AppLanguage { current(in: .standard) }

    nonisolated static var currentLocale: Locale { current.locale }
}

/// Holds the language preference and writes it through to UserDefaults so the
/// app opens in the same language it was closed in.
@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private let defaults: UserDefaults

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: AppLanguage.storageKey)
        }
    }

    var locale: Locale { language.locale }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage.current(in: defaults)
    }
}
