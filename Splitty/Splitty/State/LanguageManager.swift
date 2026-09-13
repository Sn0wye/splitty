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

    var icon: String { "globe" }

    /// Readable from any isolation so copy can resolve without hopping to the main actor.
    nonisolated static var current: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        return stored.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    nonisolated static var currentLocale: Locale { current.locale }
}

/// Holds the language preference and writes it through to UserDefaults so the
/// app opens in the same language it was closed in.
@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
        }
    }

    var locale: Locale { language.locale }

    private init() {
        language = AppLanguage.current
    }
}
