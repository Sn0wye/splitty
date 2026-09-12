import Foundation

enum AppLink: Equatable {
    case googleSignIn
    case join(code: String)
    case unknown
}

struct AppLinkParser {
    let universalLinkHost: String
    let googleCallbackScheme: String

    func parse(_ url: URL) -> AppLink {
        guard let scheme = url.scheme?.lowercased() else { return .unknown }

        if scheme == googleCallbackScheme.lowercased() {
            return .googleSignIn
        }

        let code: String?
        switch scheme {
        case "splitty" where url.host?.lowercased() == "join":
            code = singlePathComponent(in: url)
        case "https" where url.host?.lowercased() == universalLinkHost.lowercased():
            let components = url.pathComponents.filter { $0 != "/" }
            code = components.count == 2 && components.first == "join" ? components.last : nil
        default:
            code = nil
        }

        guard let code, InviteCode.isValid(code) else { return .unknown }
        return .join(code: code)
    }

    private func singlePathComponent(in url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        return components.count == 1 ? components[0] : nil
    }
}

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
