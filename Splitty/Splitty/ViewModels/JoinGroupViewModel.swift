//
//  JoinGroupViewModel.swift
//  Splitty
//

import SwiftUI

@MainActor
struct JoinGroupDataSource {
    var redeem: (String) async throws -> GroupDetail

    static let live = JoinGroupDataSource { code in
        try await GroupService.shared.redeemInvite(code: code)
    }
}

@MainActor
final class JoinGroupViewModel: ObservableObject {
    static let codeLength = InviteCode.length

    @Published var errorMessage: String?
    @Published var isRedeeming = false
    @Published private(set) var code = ""
    @Published private(set) var submissionFailureRevision = 0

    private let dataSource: JoinGroupDataSource
    private var entry = InviteCodeEntry()

    init(dataSource: JoinGroupDataSource = .live) {
        self.dataSource = dataSource
    }
    
    var canRedeem: Bool { code.count == Self.codeLength && !isRedeeming }
    
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
    
    /// Returns the joined group on success, nil on failure. Redeeming a code for a
    /// group you are already in also succeeds — the API returns that group.
    func redeem() async -> GroupDetail? {
        guard canRedeem else { return nil }
        
        isRedeeming = true
        errorMessage = nil
        defer { isRedeeming = false }
        
        do {
            return try await dataSource.redeem(code)
        } catch {
            errorMessage = Self.message(for: error)
            entry.clear()
            code = entry.code
            submissionFailureRevision += 1
            return nil
        }
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
