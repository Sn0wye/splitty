import Testing
@testable import Splitty

struct InviteShareTextTests {

    @Test func describesTheGroupAndEndsWithTheCode() {
        let text = InviteShareText.make(groupName: "Weekend away", code: "A1B2C3")

        #expect(text == #"Join "Weekend away" on Splitty with invite code A1B2C3"#)
        #expect(text.hasSuffix("A1B2C3"))
    }

    @Test func preservesQuotesAndPunctuationInTheGroupName() {
        let text = InviteShareText.make(groupName: #"Sam's "Cabin", 2026!"#, code: "Z9Y8X7")

        #expect(text == #"Join "Sam's "Cabin", 2026!" on Splitty with invite code Z9Y8X7"#)
    }

    @Test func copyUsesTheBareCode() {
        #expect(InviteShareText.copyText(code: "A1B2C3") == "A1B2C3")
    }

    @Test func shareIncludesTheUniversalInviteLink() throws {
        let link = InviteShareText.link(code: "A1B2C3", host: "invite.example.com")

        #expect(link?.absoluteString == "https://invite.example.com/join/A1B2C3")
    }
}
