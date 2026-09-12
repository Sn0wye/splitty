import Testing
@testable import Splitty

@MainActor
struct JoinGroupViewModelTests {
    @Test func aFailedAutomaticSubmissionClearsAndRefocusesTheEntryState() async {
        let viewModel = JoinGroupViewModel(dataSource: JoinGroupDataSource { _ in
            throw APIError.httpError(404, message: nil)
        })
        _ = viewModel.updateCode("ABC123")

        let group = await viewModel.redeem()

        #expect(group == nil)
        #expect(viewModel.code.isEmpty)
        #expect(viewModel.submissionFailureRevision == 1)
        #expect(viewModel.errorMessage == "That invite code isn't valid.")
    }
}
