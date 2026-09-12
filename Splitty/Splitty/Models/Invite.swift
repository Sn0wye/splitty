import Foundation

struct CreatedInvite: Codable {
    let code: String
}

struct InviteMetadata: Codable, Equatable {
    let groupName: String
    let memberCount: Int
    let createdByName: String
    let alreadyMember: Bool
}
