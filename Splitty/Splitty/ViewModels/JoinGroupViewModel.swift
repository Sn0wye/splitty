//
//  JoinGroupViewModel.swift
//  Splitty
//

import SwiftUI

@MainActor
class JoinGroupViewModel: ObservableObject {
    static let codeLength = 6
    private static let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    
    @Published var errorMessage: String?
    @Published var isRedeeming = false
    @Published var code: String = "" {
        didSet {
            let normalized = Self.normalize(code)
            if normalized != code { code = normalized }
        }
    }
    
    var canRedeem: Bool { code.count == Self.codeLength && !isRedeeming }
    
    /// Uppercases as typed and drops anything outside A-Z0-9, capped at the code length.
    static func normalize(_ input: String) -> String {
        let filtered = input.uppercased().unicodeScalars.filter { allowedCharacters.contains($0) }
        return String(String.UnicodeScalarView(filtered.prefix(codeLength)))
    }
    
    /// Returns the joined group on success, nil on failure. Redeeming a code for a
    /// group you are already in also succeeds — the API returns that group.
    func redeem() async -> GroupDetail? {
        guard canRedeem else { return nil }
        
        isRedeeming = true
        errorMessage = nil
        defer { isRedeeming = false }
        
        do {
            return try await GroupService.shared.redeemInvite(code: code)
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }
    
    private static func message(for error: Error) -> String {
        guard case APIError.httpError(let status) = error else {
            return error.localizedDescription
        }
        switch status {
        case 404: return "That invite code isn't valid."
        case 410: return "That invite has expired. Ask for a new one."
        case 409: return "That invite has no uses left. Ask for a new one."
        case 429: return "Too many attempts. Wait a minute and try again."
        default: return "Something went wrong (\(status)). Try again."
        }
    }
}
