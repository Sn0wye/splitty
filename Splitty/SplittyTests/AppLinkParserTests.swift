import Foundation
import Testing
@testable import Splitty

struct AppLinkParserTests {
    private let parser = AppLinkParser(
        universalLinkHost: "invite.example.com",
        googleCallbackScheme: "com.googleusercontent.apps.client-id"
    )

    @Test(arguments: [
        "splitty://join/ABC123",
        "https://invite.example.com/join/ABC123"
    ])
    func joinLinksYieldTheirCode(rawURL: String) throws {
        let url = try #require(URL(string: rawURL))

        #expect(parser.parse(url) == .join(code: "ABC123"))
    }

    @Test func googleCallbackKeepsItsOwnRoute() throws {
        let url = try #require(URL(string: "com.googleusercontent.apps.client-id:/oauth/callback?code=one-time"))

        #expect(parser.parse(url) == .googleSignIn)
    }

    @Test(arguments: [
        "splitty://join/ABC12",
        "splitty://join/ABC1234",
        "splitty://join/abc123",
        "splitty://join/ABC-12",
        "splitty://open/ABC123",
        "https://other.example.com/join/ABC123",
        "https://invite.example.com/groups/ABC123"
    ])
    func malformedAndUnrelatedLinksAreUnknown(rawURL: String) throws {
        let url = try #require(URL(string: rawURL))

        #expect(parser.parse(url) == .unknown)
    }
}
