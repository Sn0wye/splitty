//
//  APIConfiguration.swift
//  Splitty
//
//  Created by Snowye on 20/08/26.
//

import Foundation

/// Where the API lives, resolved from the build configuration rather than a literal.
///
/// The `SPLITTY_API_BASE_URL` build setting is substituted into the `SplittyAPIBaseURL`
/// key of `Info.plist` at build time. Debug points at the local API; Release has no
/// value yet, which surfaces as a thrown error on the first request instead of a silent
/// fallback to a developer's machine.
enum APIConfiguration {
    static let baseURLInfoKey = "SplittyAPIBaseURL"

    static func baseURL(from bundle: Bundle = .main) throws -> String {
        try baseURL(fromInfoValue: bundle.object(forInfoDictionaryKey: baseURLInfoKey))
    }

    /// Validates a raw `Info.plist` value into a base URL with no trailing slash.
    ///
    /// Endpoints are written with a leading slash and concatenated, so the base must not
    /// end in one.
    static func baseURL(fromInfoValue value: Any?) throws -> String {
        guard let raw = value as? String else {
            throw APIError.missingBaseURL
        }

        // An unset build setting substitutes to the empty string, not to a missing key.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.missingBaseURL
        }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty
        else {
            throw APIError.invalidBaseURL(trimmed)
        }

        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }
}
