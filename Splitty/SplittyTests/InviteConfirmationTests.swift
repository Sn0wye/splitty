import Foundation
import Testing
@testable import Splitty

@MainActor
struct InviteConfirmationTests {
    @Test func anInviteWaitsInMemoryUntilSignInCompletes() throws {
        let parser = AppLinkParser(
            universalLinkHost: "invite.example.com",
            googleCallbackScheme: "google.callback"
        )
        let coordinator = InviteLinkCoordinator(parser: parser)
        let url = try #require(URL(string: "splitty://join/ABC123"))

        coordinator.receive(url)

        #expect(coordinator.inviteToPresent(isAuthenticated: false) == nil)
        #expect(coordinator.inviteToPresent(isAuthenticated: true)?.code == "ABC123")
    }

    @Test func metadataChoosesJoinForAGuest() async {
        let viewModel = InviteConfirmationViewModel(
            code: "ABC123",
            dataSource: .stub(metadata: InviteMetadata(
                groupName: "Beach Trip",
                memberCount: 4,
                createdByName: "Grace",
                alreadyMember: false
            ))
        )

        await viewModel.load()

        #expect(viewModel.metadata?.groupName == "Beach Trip")
        #expect(viewModel.actionTitle == "Join")
    }

    @Test func metadataOffersToOpenAGroupForAnExistingMember() async {
        let viewModel = InviteConfirmationViewModel(
            code: "ABC123",
            dataSource: .stub(metadata: InviteMetadata(
                groupName: "Beach Trip",
                memberCount: 4,
                createdByName: "Grace",
                alreadyMember: true
            ))
        )

        await viewModel.load()

        #expect(viewModel.actionTitle == "Open group")
    }

    @Test(arguments: [
        (404, "That invite code isn't valid."),
        (410, "That invite has expired. Ask for a new one."),
        (409, "That invite has no uses left. Ask for a new one."),
        (429, "Too many attempts. Wait a minute and try again.")
    ])
    func metadataErrorsReuseTheJoinMessage(status: Int, expectedMessage: String) async {
        let viewModel = InviteConfirmationViewModel(
            code: "ABC123",
            dataSource: .failing(with: .httpError(status, message: nil))
        )

        await viewModel.load()

        #expect(viewModel.errorMessage == expectedMessage)
    }
}

@MainActor
private extension InviteConfirmationDataSource {
    static func stub(metadata: InviteMetadata) -> Self {
        Self(
            describe: { _ in metadata },
            redeem: { _ in
                GroupDetail(
                    id: 12,
                    name: metadata.groupName,
                    description: nil,
                    netBalanceCents: 0,
                    createdAt: "2026-01-01T00:00:00Z",
                    members: []
                )
            }
        )
    }

    static func failing(with error: APIError) -> Self {
        Self(
            describe: { _ in throw error },
            redeem: { _ in throw error }
        )
    }
}
