//
//  JoinGroupViewModel.swift
//  Splitty
//

import SwiftUI

@MainActor
struct JoinGroupDataSource {
    var describe: (String) async throws -> InviteMetadata
    var redeem: (String) async throws -> GroupDetail

    static let live = JoinGroupDataSource(
        describe: { code in try await GroupService.shared.describeInvite(code: code) },
        redeem: { code in try await GroupService.shared.redeemInvite(code: code) }
    )
}

@MainActor
final class JoinGroupViewModel: ObservableObject {
    static let codeLength = InviteCode.length

    @Published var errorMessage: String?
    @Published private(set) var isLookingUp = false
    @Published private(set) var isJoining = false
    /// The group behind the entered code, shown for confirmation before joining.
    @Published private(set) var preview: InviteMetadata?
    @Published private(set) var code = ""
    @Published private(set) var submissionFailureRevision = 0

    private let dataSource: JoinGroupDataSource
    private var entry = InviteCodeEntry()

    init(dataSource: JoinGroupDataSource = .live) {
        self.dataSource = dataSource
    }
    
    var canLookUp: Bool { code.count == Self.codeLength && !isLookingUp }

    var joinTitle: String {
        preview?.alreadyMember == true ? L10n.Invite.openGroup : L10n.Invite.join
    }

    /// Uppercases as typed and drops anything outside A-Z0-9, capped at the code length.
    static func normalize(_ input: String) -> String {
        InviteCode.normalizeTyping(input)
    }

    /// Applies one text-field edit. A multi-character edit is paste/autofill and only
    /// replaces the boxes when it is a clean six-character code.
    func updateCode(
        _ proposedText: String,
        source: InviteCodeEditSource = .typing
    ) -> Bool {
        let shouldSubmit = entry.replaceText(with: proposedText, source: source)
        code = entry.code
        if !code.isEmpty { errorMessage = nil }
        return shouldSubmit
    }
    
    /// Fetches the group behind the code so the user can confirm before joining.
    /// A rejected code clears the entry so the next attempt starts fresh.
    func lookUp() async {
        guard canLookUp else { return }

        isLookingUp = true
        errorMessage = nil
        defer { isLookingUp = false }

        do {
            preview = try await dataSource.describe(code)
        } catch {
            errorMessage = Self.message(for: error)
            resetEntry()
            submissionFailureRevision += 1
        }
    }

    /// Returns the joined group on success, nil on failure. Redeeming a code for a
    /// group you are already in also succeeds — the API returns that group.
    func join() async -> GroupDetail? {
        guard preview != nil, !isJoining else { return nil }

        isJoining = true
        errorMessage = nil
        defer { isJoining = false }

        do {
            return try await dataSource.redeem(code)
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    /// Backing out of the preview returns to an empty entry for another code.
    func dismissPreview() {
        preview = nil
        errorMessage = nil
        resetEntry()
    }

    private func resetEntry() {
        entry.clear()
        code = entry.code
    }

    static func message(for error: Error) -> String {
        guard case APIError.httpError(let status, _) = error else {
            return error.localizedDescription
        }
        switch status {
        case 404: return L10n.Invite.invalidCode
        case 410: return L10n.Invite.expired
        case 409: return L10n.Invite.exhausted
        case 429: return L10n.Invite.tooMany
        default: return L10n.Errors.status(status)
        }
    }
}
