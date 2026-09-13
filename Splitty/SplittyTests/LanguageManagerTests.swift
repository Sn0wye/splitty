import Foundation
import Testing
@testable import Splitty

struct LanguageManagerTests {
    @Test func theAppShipsEnglishAsItsOnlyLanguage() {
        #expect(AppLanguage.allCases == [.english])
        #expect(AppLanguage.english.locale.identifier == "en")
        #expect(AppLanguage.english.displayName == "English")
    }

    @Test func missingPreferenceResolvesToEnglish() {
        #expect(AppLanguage.current == .english)
        #expect(AppLanguage.currentLocale.identifier == "en")
    }
}

struct L10nTests {
    @Test func tokensResolveToTheCurrentEnglishCopy() {
        #expect(L10n.Settings.title == "Settings")
        #expect(L10n.Settings.language == "Language")
        #expect(L10n.Language.title == "Language")
        #expect(L10n.Common.cancel == "Cancel")
        #expect(L10n.Invite.shareText("Weekend away", "A1B2C3") == #"Join "Weekend away" on Splitty with invite code A1B2C3"#)
        #expect(L10n.Leave.deleteTitle("\"Weekend away\"") == "Leave and delete \"Weekend away\"?")
        #expect(L10n.Errors.status(500) == "Something went wrong (500). Try again.")
        #expect(L10n.Expense.percentLeft("20") == "20% left to assign")
    }
}
