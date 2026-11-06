import Foundation
import Testing
@testable import Splitty

/// `L10n.text` resolves through each language's `.lproj` instead of a
/// `LocalizedStringResource` naming a locale, which reads the table from disk per call.
/// The copy must not change, so every plain catalog entry is compared with the old route
/// in every shipped language.
struct L10nLookupTests {
    private static let catalog: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Splitty/Localization/Localizable.xcstrings")
        let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return json["strings"] as! [String: Any]
    }()

    /// Keys whose English value takes no argument, so the key alone resolves them.
    private static let plainKeys: [String] = catalog.compactMap { key, entry in
        guard let entry = entry as? [String: Any],
              let english = (entry["localizations"] as? [String: Any])?["en"] as? [String: Any],
              let unit = english["stringUnit"] as? [String: Any],
              let value = unit["value"] as? String,
              !value.contains("%")
        else { return nil }
        return key
    }.sorted()

    private static func viaResource(_ key: String, _ language: AppLanguage) -> String {
        var resource = LocalizedStringResource(String.LocalizationValue(key))
        resource.locale = language.locale
        return String(localized: resource)
    }

    private static func viaTable(_ key: String, _ language: AppLanguage) -> String {
        let bundle = Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:))!
        return String(localized: String.LocalizationValue(key), bundle: bundle, locale: language.locale)
    }

    @Test func everyPlainEntryReadsTheSameThroughTheLanguageTable() {
        #expect(Self.plainKeys.count > 100)
        for language in AppLanguage.allCases {
            for key in Self.plainKeys {
                #expect(Self.viaTable(key, language) == Self.viaResource(key, language), "\(key) in \(language.rawValue)")
            }
        }
    }

    @Test func tokensReadTheirLanguage() {
        for language in AppLanguage.allCases {
            AppLanguage.$pinned.withValue(language) {
                #expect(L10n.Common.today == Self.viaResource("common.today", language))
                #expect(L10n.Group.youLent == Self.viaResource("group.you_lent", language))
            }
        }
    }

    /// Evidence rather than a gate: the old route against the new one, per call.
    @Test func theLanguageTableIsCheaperPerCall() {
        let iterations = 2_000
        let clock = ContinuousClock()
        let keys = Array(Self.plainKeys.prefix(20))
        let old = clock.measure {
            for index in 0..<iterations { _ = Self.viaResource(keys[index % keys.count], .brazilianPortuguese) }
        }
        let new = AppLanguage.$pinned.withValue(.brazilianPortuguese) {
            clock.measure {
                for _ in 0..<(iterations / 2) {
                    _ = L10n.Common.today
                    _ = L10n.Group.youLent
                }
            }
        }
        print("L10n lookup, \(iterations) calls: LocalizedStringResource \(old), language table \(new)")
        #expect(new < old)
    }
}
