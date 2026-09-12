import Foundation

struct PendingInvite: Identifiable, Equatable {
    let code: String
    var id: String { code }
}

@MainActor
final class InviteLinkCoordinator: ObservableObject {
    @Published private(set) var pendingInvite: PendingInvite?
    @Published var invalidLinkMessage: String?

    private let parser: AppLinkParser

    init(parser: AppLinkParser) {
        self.parser = parser
    }

    convenience init(bundle: Bundle = .main) {
        let inviteHost = bundle.object(forInfoDictionaryKey: "SplittyInviteHost") as? String ?? ""
        let clientID = bundle.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        let callbackScheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        self.init(parser: AppLinkParser(
            universalLinkHost: inviteHost,
            googleCallbackScheme: callbackScheme
        ))
    }

    @discardableResult
    func receive(_ url: URL) -> AppLink {
        let link = parser.parse(url)
        switch link {
        case .join(let code):
            pendingInvite = PendingInvite(code: code)
            invalidLinkMessage = nil
        case .unknown:
            invalidLinkMessage = "This invite link isn't valid. Ask for a new one."
        case .googleSignIn:
            break
        }
        return link
    }

    func inviteToPresent(isAuthenticated: Bool) -> PendingInvite? {
        isAuthenticated ? pendingInvite : nil
    }

    func clearPendingInvite() {
        pendingInvite = nil
    }
}
