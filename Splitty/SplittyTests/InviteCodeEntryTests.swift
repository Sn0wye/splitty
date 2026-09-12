import Testing
@testable import Splitty

struct InviteCodeEntryTests {
    @Test func typingNormalizesCharactersAndCapsTheCode() {
        var entry = InviteCodeEntry()

        _ = entry.replaceText(with: "a")
        _ = entry.replaceText(with: "A-")
        _ = entry.replaceText(with: "AB")
        _ = entry.replaceText(with: "ABc")
        _ = entry.replaceText(with: "ABC1")
        _ = entry.replaceText(with: "ABC12")
        _ = entry.replaceText(with: "ABC123")
        _ = entry.replaceText(with: "ABC1234")

        #expect(entry.code == "ABC123")
    }

    @Test(arguments: ["ABC123", "abc123", "  ABC123\n"])
    func aCleanPastedCodeFillsAllBoxes(rawCode: String) {
        var entry = InviteCodeEntry()

        let shouldSubmit = entry.replaceText(with: rawCode, source: .paste)

        #expect(entry.code == "ABC123")
        #expect(shouldSubmit)
    }

    @Test func aPastedSentenceFillsNothing() {
        var entry = InviteCodeEntry()

        let shouldSubmit = entry.replaceText(
            with: "Join Beach Trip on Splitty with code ABC123",
            source: .paste
        )

        #expect(entry.code.isEmpty)
        #expect(!shouldSubmit)
    }

    @Test func aOneCharacterPasteFillsNothing() {
        var entry = InviteCodeEntry()

        let shouldSubmit = entry.replaceText(with: "A", source: .paste)

        #expect(entry.code.isEmpty)
        #expect(!shouldSubmit)
    }

    @Test func accessibilityValueReadsBackCharactersAndProgress() {
        #expect(InviteCodeEntry.accessibilityValue(for: "A1B") == "A 1 B, 3 of 6 characters entered")
        #expect(InviteCodeEntry.accessibilityValue(for: "") == "Empty, 0 of 6 characters entered")
    }

    @Test func backspaceCanRemoveCharactersAcrossTheBoxes() {
        var entry = InviteCodeEntry()
        _ = entry.replaceText(with: "ABC123")

        _ = entry.replaceText(with: "ABC12")
        _ = entry.replaceText(with: "ABC1")

        #expect(entry.code == "ABC1")
    }

    @Test func completionSubmitsOnceUntilTheCodeChanges() {
        var entry = InviteCodeEntry()

        var results: [Bool] = []
        results.append(entry.replaceText(with: "ABC123"))
        results.append(entry.replaceText(with: "ABC123"))
        results.append(entry.replaceText(with: "ABC12"))
        results.append(entry.replaceText(with: "ABC123"))

        #expect(results == [true, false, false, true])
    }

    @Test func clearingAfterFailureAllowsAnImmediateRetry() {
        var entry = InviteCodeEntry()
        _ = entry.replaceText(with: "ABC123")

        entry.clear()
        let wasCleared = entry.code.isEmpty
        let shouldSubmit = entry.replaceText(with: "Z9Y8X7")

        #expect(wasCleared)
        #expect(entry.code == "Z9Y8X7")
        #expect(shouldSubmit)
    }
}
