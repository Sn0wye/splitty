import Foundation

enum InviteCode {
    static let length = 6
    private static let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    static func isValid(_ code: String) -> Bool {
        code.count == length && code.unicodeScalars.allSatisfy(allowedCharacters.contains)
    }

    static func normalizeTyping(_ input: String) -> String {
        let filtered = input.uppercased().unicodeScalars.filter(allowedCharacters.contains)
        return String(String.UnicodeScalarView(filtered.prefix(length)))
    }
}
