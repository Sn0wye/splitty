import Foundation
import Testing
@testable import Splitty

/// Each test gets its own suite so nothing depends on — or leaks into — the
/// preference the app and the simulator share.
private func makeDefaults() -> UserDefaults {
    let name = "LanguageManagerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

struct AppLanguageTests {
    @Test func anUnsetPreferenceResolvesToEnglish() {
        let defaults = makeDefaults()

        #expect(defaults.string(forKey: AppLanguage.storageKey) == nil)
        #expect(AppLanguage.current(in: defaults) == .english)
    }

    @Test func anUnrecognizedPreferenceResolvesToEnglish() {
        let defaults = makeDefaults()
        defaults.set("kl", forKey: AppLanguage.storageKey)

        #expect(AppLanguage.current(in: defaults) == .english)
    }

    @Test func aStoredPreferenceResolvesToItsLanguage() {
        let defaults = makeDefaults()
        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)

        #expect(AppLanguage.current(in: defaults) == .english)
    }

    @Test func everyLanguageCarriesALocaleAndAnAutonym() {
        for language in AppLanguage.allCases {
            #expect(language.locale.identifier == language.rawValue)
            #expect(!language.displayName.isEmpty)
            #expect(!language.flag.isEmpty)
        }
    }
}

@MainActor
struct LanguageManagerTests {
    @Test func itOpensOnTheStoredLanguage() {
        let defaults = makeDefaults()
        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)

        #expect(LanguageManager(defaults: defaults).language == .english)
    }

    @Test func choosingALanguageWritesItThroughToTheStore() {
        let defaults = makeDefaults()
        let manager = LanguageManager(defaults: defaults)

        manager.language = .english

        #expect(defaults.string(forKey: AppLanguage.storageKey) == AppLanguage.english.rawValue)
        #expect(AppLanguage.current(in: defaults) == .english)
        #expect(manager.locale == AppLanguage.english.locale)
    }
}

/// Only the tokens that take arguments: a token that just returns its own default
/// is worth nothing as a test, but an argument mismatch is a crash.
///
/// `L10n` resolves through `UserDefaults.standard`, so these pin the language for
/// the duration rather than inheriting whatever the device was last left in — a
/// simulator someone switched to Portuguese used to fail the whole suite. Serialized
/// because that store is process-wide.
@Suite(.serialized)
struct L10nFormattingTests {
    private func withAppLanguage<T>(_ language: AppLanguage, _ body: () -> T) -> T {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppLanguage.storageKey)
        defaults.set(language.rawValue, forKey: AppLanguage.storageKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: AppLanguage.storageKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.storageKey)
            }
        }
        return body()
    }

    @Test func singleArgumentTokensSubstitute() { withAppLanguage(.english) {
        #expect(L10n.Errors.status(500) == "Something went wrong (500). Try again.")
        #expect(L10n.Expense.percentLeft("20") == "20% left to assign")
        #expect(L10n.Group.deleteExpense("Tacos") == #"Delete "Tacos"?"#)
    } }

    @Test func multipleArgumentTokensKeepTheirOrder() { withAppLanguage(.english) {
        #expect(L10n.Balances.youOwePeer("Ana", "$4.00") == "You owe Ana $4.00")
        #expect(L10n.Balances.peerOwesYou("Ana", "$4.00") == "Ana owes you $4.00")
        #expect(L10n.Settlement.onlyOwe("Ana", "$4.00") == "You only owe Ana $4.00.")
        #expect(
            L10n.Settlement.deleteTitle("$4.00", "Ana", "Bo")
                == "Delete the $4.00 payment from Ana to Bo?"
        )
        #expect(
            L10n.Invite.shareText("Weekend away", "A1B2C3")
                == #"Join "Weekend away" on Splitty with invite code A1B2C3"#
        )
        #expect(
            L10n.Invite.a11yValue("A1B", 3, 6) == "A1B, 3 of 6 characters entered"
        )
        #expect(
            L10n.Split.summaryPercentLeft("Ana", "20") == "Paid by Ana, 20% left to assign"
        )
    } }

    @Test func countsPickTheirPluralFromTheCatalog() { withAppLanguage(.english) {
        #expect(L10n.Invite.members(1) == "1 member")
        #expect(L10n.Invite.members(0) == "0 members")
        #expect(L10n.Invite.members(3) == "3 members")
        #expect(L10n.Split.summaryEquallyBetween("Ana", 1) == "Paid by Ana and split equally between 1 person")
        #expect(L10n.Split.summaryEquallyBetween("Ana", 4) == "Paid by Ana and split equally between 4 people")
    } }

    /// Each language brings its own plural rules. French counts 0 as singular,
    /// which is the point of keeping categories in the catalog.
    @Test func eachLanguagePluralizesByItsOwnRules() {
        withAppLanguage(.brazilianPortuguese) {
            #expect(L10n.Invite.members(1) == "1 membro")
            #expect(L10n.Invite.members(3) == "3 membros")
            #expect(L10n.Split.summaryEquallyBetween("Ana", 1) == "Pago por Ana e dividido igualmente entre 1 pessoa")
        }
        withAppLanguage(.spanish) {
            #expect(L10n.Invite.members(1) == "1 miembro")
            #expect(L10n.Invite.members(3) == "3 miembros")
        }
        withAppLanguage(.french) {
            #expect(L10n.Invite.members(0) == "0 membre")
            #expect(L10n.Invite.members(1) == "1 membre")
            #expect(L10n.Invite.members(3) == "3 membres")
        }
    }

    /// The argument swaps the translators made have to survive at runtime, not just
    /// in the catalog.
    @Test func translationsKeepTheirReorderedArguments() {
        withAppLanguage(.french) {
            #expect(L10n.Balances.youOwePeer("Ana", "4,00 €") == "Vous devez 4,00 € à Ana")
        }
        withAppLanguage(.spanish) {
            #expect(L10n.Settlement.onlyOwe("Ana", "4,00 €") == "Solo debes 4,00 € a Ana.")
        }
        withAppLanguage(.brazilianPortuguese) {
            #expect(L10n.Balances.youOwePeer("Ana", "R$ 4,00") == "Você deve R$ 4,00 a Ana")
        }
    }
}
