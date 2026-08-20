//
//  APIConfigurationTests.swift
//  SplittyTests
//
//  Created by Snowye on 20/08/26.
//

import Foundation
import Testing
@testable import Splitty

struct APIConfigurationTests {

    @Test func acceptsAConfiguredHTTPURL() throws {
        #expect(try APIConfiguration.baseURL(fromInfoValue: "http://localhost:8080") == "http://localhost:8080")
    }

    @Test func acceptsHTTPS() throws {
        #expect(try APIConfiguration.baseURL(fromInfoValue: "https://api.splitty.app") == "https://api.splitty.app")
    }

    @Test func stripsTheTrailingSlashSoEndpointsConcatenateCleanly() throws {
        #expect(try APIConfiguration.baseURL(fromInfoValue: "http://localhost:8080/") == "http://localhost:8080")
    }

    @Test func trimsSurroundingWhitespace() throws {
        #expect(try APIConfiguration.baseURL(fromInfoValue: "  http://localhost:8080\n") == "http://localhost:8080")
    }

    @Test func rejectsAMissingKey() {
        #expect(throws: APIError.self) {
            try APIConfiguration.baseURL(fromInfoValue: nil)
        }
    }

    // An unset build setting substitutes to an empty string rather than dropping the key.
    @Test func rejectsAnUnsubstitutedBuildSetting() {
        #expect(throws: APIError.self) {
            try APIConfiguration.baseURL(fromInfoValue: "")
        }
    }

    @Test func rejectsAValueWithNoScheme() {
        #expect(throws: APIError.self) {
            try APIConfiguration.baseURL(fromInfoValue: "localhost:8080")
        }
    }

    @Test func rejectsANonHTTPScheme() {
        #expect(throws: APIError.self) {
            try APIConfiguration.baseURL(fromInfoValue: "ftp://localhost:8080")
        }
    }

    @Test func rejectsANonStringValue() {
        #expect(throws: APIError.self) {
            try APIConfiguration.baseURL(fromInfoValue: 8080)
        }
    }

    // The app itself must resolve a base URL from its own bundle, or every request fails.
    @Test func theAppBundleCarriesABaseURL() throws {
        // The test target is hosted by the app, so `.main` is the app bundle.
        let resolved = try APIConfiguration.baseURL()
        #expect(!resolved.isEmpty)
    }
}
