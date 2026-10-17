//
//  Website.swift
//  Splitty
//

import Foundation

/// The Splitty website, which hosts the pages the App Store requires the app to link to.
///
/// The site (`web/` at the repository root) publishes every page in each `AppLanguage`, with
/// English at the root and the others under a path prefix, so a link opens in the language
/// the app is showing.
nonisolated enum Website {
    // TODO: the production domain, once it exists. The web project's `src/config.ts`
    // contact addresses use the same placeholder.
    static let base = URL(string: "https://splitty.app")!

    enum Page: String {
        case privacy, terms, support
    }

    static func url(_ page: Page, in language: AppLanguage = .current) -> URL {
        var url = base
        if let prefix = language.websitePrefix {
            url.append(path: prefix)
        }
        return url.appending(path: page.rawValue)
    }
}

extension AppLanguage {
    /// The website's path segment for this language. English lives at the root.
    nonisolated var websitePrefix: String? {
        switch self {
        case .english: nil
        case .brazilianPortuguese: "pt-br"
        case .spanish: "es"
        case .french: "fr"
        }
    }
}
