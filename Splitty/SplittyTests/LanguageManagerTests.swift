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
struct L10nFormattingTests {
    @Test func singleArgumentTokensSubstitute() {
        #expect(L10n.Errors.status(500) == "Something went wrong (500). Try again.")
        #expect(L10n.Expense.percentLeft("20") == "20% left to assign")
        #expect(L10n.Group.deleteExpense("Tacos") == #"Delete "Tacos"?"#)
    }

    @Test func multipleArgumentTokensKeepTheirOrder() {
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
    }

    @Test func countsPickTheirPluralFromTheCatalog() {
        #expect(L10n.Invite.members(1) == "1 member")
        #expect(L10n.Invite.members(0) == "0 members")
        #expect(L10n.Invite.members(3) == "3 members")
        #expect(L10n.Split.summaryEquallyBetween("Ana", 1) == "Paid by Ana and split equally between 1 person")
        #expect(L10n.Split.summaryEquallyBetween("Ana", 4) == "Paid by Ana and split equally between 4 people")
    }
}
