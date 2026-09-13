import Foundation

@MainActor
struct InviteConfirmationDataSource {
    var describe: (String) async throws -> InviteMetadata
    var redeem: (String) async throws -> GroupDetail

    static let live = InviteConfirmationDataSource(
        describe: { code in try await GroupService.shared.describeInvite(code: code) },
        redeem: { code in try await GroupService.shared.redeemInvite(code: code) }
    )
}

@MainActor
final class InviteConfirmationViewModel: ObservableObject {
    @Published private(set) var metadata: InviteMetadata?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false

    let code: String
    private let dataSource: InviteConfirmationDataSource

    init(code: String, dataSource: InviteConfirmationDataSource = .live) {
        self.code = code
        self.dataSource = dataSource
    }

    var actionTitle: String {
        metadata?.alreadyMember == true ? L10n.Invite.openGroup : L10n.Invite.join
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        metadata = nil
        errorMessage = nil
        defer { isLoading = false }

        do {
            metadata = try await dataSource.describe(code)
        } catch {
            errorMessage = JoinGroupViewModel.message(for: error)
        }
    }

    func proceed() async -> GroupDetail? {
        guard metadata != nil, !isSubmitting else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            return try await dataSource.redeem(code)
        } catch {
            errorMessage = JoinGroupViewModel.message(for: error)
            return nil
        }
    }
}
