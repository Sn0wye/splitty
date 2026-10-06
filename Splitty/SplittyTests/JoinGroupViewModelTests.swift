import Testing
@testable import Splitty

@MainActor
struct JoinGroupViewModelTests {
    @Test func aFailedAutomaticSubmissionClearsAndRefocusesTheEntryState() async {
        let viewModel = JoinGroupViewModel(dataSource: .failing(with: .httpError(404, message: nil)))
        _ = viewModel.updateCode("ABC123")

        await viewModel.lookUp()

        #expect(viewModel.preview == nil)
        #expect(viewModel.code.isEmpty)
        #expect(viewModel.submissionFailureRevision == 1)
        #expect(viewModel.errorMessage == L10n.Invite.invalidCode)
    }

    @Test(arguments: [410, 409, 429])
    func lookUpErrorsExplainWhyTheCodeFailed(status: Int) async {
        let viewModel = JoinGroupViewModel(dataSource: .failing(with: .httpError(status, message: nil)))
        _ = viewModel.updateCode("ABC123")

        await viewModel.lookUp()

        #expect(viewModel.errorMessage == JoinGroupViewModel.message(for: APIError.httpError(status, message: nil)))
    }

    @Test func aValidCodeShowsThePreviewWithoutJoining() async {
        let recorder = RedeemRecorder()
        let viewModel = JoinGroupViewModel(dataSource: .stub(metadata: .beachTrip(), recorder: recorder))
        _ = viewModel.updateCode("ABC123")

        await viewModel.lookUp()

        #expect(viewModel.preview?.groupName == "Beach Trip")
        #expect(viewModel.joinTitle == L10n.Invite.join)
        #expect(recorder.codes.isEmpty)
    }

    @Test func anExistingMemberIsOfferedTheGroupInstead() async {
        let viewModel = JoinGroupViewModel(dataSource: .stub(metadata: .beachTrip(alreadyMember: true)))
        _ = viewModel.updateCode("ABC123")

        await viewModel.lookUp()

        #expect(viewModel.joinTitle == L10n.Invite.openGroup)
    }

    @Test func joiningRedeemsThePreviewedCode() async {
        let recorder = RedeemRecorder()
        let viewModel = JoinGroupViewModel(dataSource: .stub(metadata: .beachTrip(), recorder: recorder))
        _ = viewModel.updateCode("ABC123")
        await viewModel.lookUp()

        let group = await viewModel.join()

        #expect(group?.id == 12)
        #expect(recorder.codes == ["ABC123"])
    }

    @Test func aFailedJoinStaysOnThePreview() async {
        let viewModel = JoinGroupViewModel(dataSource: JoinGroupDataSource(
            describe: { _ in .beachTrip() },
            redeem: { _ in throw APIError.httpError(410, message: nil) }
        ))
        _ = viewModel.updateCode("ABC123")
        await viewModel.lookUp()

        let group = await viewModel.join()

        #expect(group == nil)
        #expect(viewModel.preview != nil)
        #expect(viewModel.errorMessage == L10n.Invite.expired)
    }

    @Test func backingOutOfThePreviewStartsAFreshEntry() async {
        let viewModel = JoinGroupViewModel(dataSource: .stub(metadata: .beachTrip()))
        _ = viewModel.updateCode("ABC123")
        await viewModel.lookUp()

        viewModel.dismissPreview()

        #expect(viewModel.preview == nil)
        #expect(viewModel.code.isEmpty)
        #expect(viewModel.updateCode("ABC123"))
    }
}

@MainActor
private final class RedeemRecorder {
    var codes: [String] = []
}

private extension InviteMetadata {
    static func beachTrip(alreadyMember: Bool = false) -> Self {
        InviteMetadata(
            groupName: "Beach Trip",
            memberCount: 4,
            createdByName: "Grace",
            alreadyMember: alreadyMember
        )
    }
}

@MainActor
private extension JoinGroupDataSource {
    static func stub(metadata: InviteMetadata, recorder: RedeemRecorder? = nil) -> Self {
        Self(
            describe: { _ in metadata },
            redeem: { code in
                recorder?.codes.append(code)
                return GroupDetail(
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
