//
//  WebsiteTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

/// The paths here are a contract with the web project's `src/i18n/locales.ts`.
struct WebsiteTests {

    @Test func englishPagesSitAtTheRoot() {
        #expect(Website.url(.privacy, in: .english).path() == "/privacy")
        #expect(Website.url(.terms, in: .english).path() == "/terms")
        #expect(Website.url(.support, in: .english).path() == "/support")
    }

    @Test func otherLanguagesArePrefixed() {
        #expect(Website.url(.privacy, in: .brazilianPortuguese).path() == "/pt-br/privacy")
        #expect(Website.url(.terms, in: .spanish).path() == "/es/terms")
        #expect(Website.url(.support, in: .french).path() == "/fr/support")
    }

    @Test func everyLanguageHasALinkOnTheSiteHost() {
        for language in AppLanguage.allCases {
            let url = Website.url(.privacy, in: language)
            #expect(url.scheme == "https")
            #expect(url.host() == Website.base.host())
        }
    }
}
