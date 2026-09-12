import Foundation

enum InviteCodeEditSource: Equatable {
    case typing
    case paste
}

struct InviteCodeEntry {
    private(set) var code = ""
    private var submittedCode: String?

    /// Returns true only for the first update that completes the current code.
    mutating func replaceText(
        with proposedText: String,
        source: InviteCodeEditSource = .typing
    ) -> Bool {
        let nextCode: String

        if source == .paste {
            let pastedCode = proposedText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard InviteCode.isValid(pastedCode) else { return false }
            nextCode = pastedCode
        } else {
            nextCode = InviteCode.normalizeTyping(proposedText)
        }

        code = nextCode
        guard InviteCode.isValid(code) else {
            submittedCode = nil
            return false
        }
        guard submittedCode != code else { return false }
        submittedCode = code
        return true
    }

    mutating func clear() {
        code = ""
        submittedCode = nil
    }

    static func accessibilityValue(for code: String) -> String {
        let characters = code.isEmpty
            ? "Empty"
            : code.map(String.init).joined(separator: " ")
        return "\(characters), \(code.count) of \(InviteCode.length) characters entered"
    }
}
