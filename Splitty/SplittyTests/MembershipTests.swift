//
//  MembershipTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

struct MembershipErrorTests {

    @Test func conflictUsesTheServersExplanation() {
        let result = MembershipError(APIError.httpError(
            409,
            message: "This member has an outstanding balance"
        ))

        #expect(result.message == "This member has an outstanding balance")
        #expect(!result.shouldLeaveScreen)
    }

    @Test func conflictWithoutAnExplanationUsesReadableFallbackCopy() {
        let result = MembershipError(APIError.httpError(409, message: nil))

        #expect(result.message == "This member has an outstanding balance.")
        #expect(!result.shouldLeaveScreen)
    }

    @Test(arguments: [403, 404])
    func unavailableGroupLeavesTheScreen(status: Int) {
        let result = MembershipError(APIError.httpError(status, message: "Server detail"))

        #expect(result.message == "This group is no longer available")
        #expect(result.shouldLeaveScreen)
    }

    @Test func networkFailureKeepsTheScreenAndUsesConnectionCopy() {
        let result = MembershipError(APIError.networkError(URLError(.notConnectedToInternet)))

        #expect(result.message == "Couldn't reach Splitty. Check your connection and try again.")
        #expect(!result.shouldLeaveScreen)
    }
}

struct MemberDisplayTests {

    @Test func removedSentinelBecomesMutedCopyWithoutAnAvatar() {
        let display = MemberDisplay(name: "[removed]", avatarURL: URL(string: "https://example.com/old.png"))

        #expect(display.name == "Removed member")
        #expect(display.avatarURL == nil)
        #expect(display.isRemoved)
    }

    @Test func ordinaryMemberPassesThroughUntouched() {
        let avatarURL = URL(string: "https://example.com/ana.png")
        let display = MemberDisplay(name: "Ana", avatarURL: avatarURL)

        #expect(display.name == "Ana")
        #expect(display.avatarURL == avatarURL)
        #expect(!display.isRemoved)
    }

    @Test func bracketedNamesOtherThanTheExactSentinelAreNotRemoved() {
        let display = MemberDisplay(name: "[Removed]", avatarURL: nil)

        #expect(display.name == "[Removed]")
        #expect(!display.isRemoved)
    }
}
