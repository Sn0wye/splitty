import Foundation
import Testing
@testable import Splitty

/// `L10n` hand-mirrors `Localizable.xcstrings`, and a key that drifts apart from
/// the catalog fails silently — `LocalizedStringResource` just returns the Swift
/// default. These tests read both files and make that drift loud instead. They
/// are the check that pays off per language added: every shipped `AppLanguage`
/// has to carry a translated unit for every key.
struct LocalizationCatalogTests {
    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SplittyTests
        .deletingLastPathComponent()   // Splitty (project dir)
        .appendingPathComponent("Splitty/Localization")

    private static let keysUsedInCode: Set<String> = {
        let source = try! String(contentsOf: sourceRoot.appendingPathComponent("L10n.swift"), encoding: .utf8)
        let pattern = try! NSRegularExpression(pattern: #"\b(?:text|format)\(\s*"([a-z0-9_.]+)""#)
        let range = NSRange(source.startIndex..., in: source)
        return Set(pattern.matches(in: source, range: range).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        })
    }()

    private static let catalog: [String: Any] = {
        let data = try! Data(contentsOf: sourceRoot.appendingPathComponent("Localizable.xcstrings"))
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json["strings"] as! [String: Any]
    }()

    /// Every `stringUnit` reachable under a node — a key may hold one directly, or
    /// hold several nested under plural variations and substitutions.
    private func stringUnits(in node: Any) -> [[String: Any]] {
        guard let dictionary = node as? [String: Any] else { return [] }
        if let unit = dictionary["stringUnit"] as? [String: Any] {
            return [unit] + dictionary.values.flatMap { stringUnits(in: $0) }
        }
        return dictionary.values.flatMap { stringUnits(in: $0) }
    }

    @Test func everyKeyTheCodeUsesExistsInTheCatalog() {
        let missing = Self.keysUsedInCode.subtracting(Self.catalog.keys).sorted()
        #expect(missing.isEmpty, "Keys used by L10n but absent from the catalog: \(missing)")
    }

    @Test func theCatalogCarriesNoKeyTheCodeHasStoppedUsing() {
        let unused = Set(Self.catalog.keys).subtracting(Self.keysUsedInCode).sorted()
        #expect(unused.isEmpty, "Catalog keys no longer referenced by L10n: \(unused)")
    }

    @Test func everyShippedLanguageTranslatesEveryKey() {
        for language in AppLanguage.allCases {
            for (key, entry) in Self.catalog {
                guard
                    let entry = entry as? [String: Any],
                    let localizations = entry["localizations"] as? [String: Any],
                    let localization = localizations[language.rawValue]
                else {
                    Issue.record("\(key) has no \(language.rawValue) localization")
                    continue
                }

                let units = stringUnits(in: localization)
                #expect(!units.isEmpty, "\(key) has an empty \(language.rawValue) localization")
                for unit in units {
                    #expect(
                        unit["state"] as? String == "translated",
                        "\(key) is \(unit["state"] as? String ?? "missing") in \(language.rawValue)"
                    )
                }
            }
        }
    }

    @Test func theCatalogSourceLanguageIsShipped() throws {
        let data = try Data(contentsOf: Self.sourceRoot.appendingPathComponent("Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let source = json["sourceLanguage"] as? String

        #expect(AppLanguage(rawValue: source ?? "") != nil, "sourceLanguage \(source ?? "nil") is not an AppLanguage")
    }
}
