import Foundation

struct PeopleResponse: Codable {
    static let empty = PeopleResponse(peers: [], balancesPending: false)

    let peers: [Peer]
    let balancesPending: Bool
}

struct Peer: Codable, Identifiable {
    let userId: Int
    let name: String
    let avatarURL: URL?
    @DecodedCents var netAmountCents: Int
    let groups: [PeerGroup]

    var id: Int { userId }
    var magnitudeCents: Int { abs(netAmountCents) }

    init(userId: Int, name: String, avatarURL: URL?, netAmountCents: Int, groups: [PeerGroup]) {
        self.userId = userId
        self.name = name
        self.avatarURL = avatarURL
        self.netAmountCents = netAmountCents
        self.groups = groups
    }

    private enum CodingKeys: String, CodingKey {
        case userId, name, avatarUrl, groups
        case netAmountCents = "netAmount"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userId = try values.decode(Int.self, forKey: .userId)
        name = try values.decode(String.self, forKey: .name)
        let avatarString = try values.decodeIfPresent(String.self, forKey: .avatarUrl)
        avatarURL = avatarString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        _netAmountCents = try values.decode(DecodedCents.self, forKey: .netAmountCents)
        groups = try values.decode([PeerGroup].self, forKey: .groups)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(userId, forKey: .userId)
        try values.encode(name, forKey: .name)
        try values.encodeIfPresent(avatarURL?.absoluteString, forKey: .avatarUrl)
        try values.encode(_netAmountCents, forKey: .netAmountCents)
        try values.encode(groups, forKey: .groups)
    }
}

struct PeerGroup: Codable, Identifiable {
    let groupId: Int
    let groupName: String
    @DecodedCents var amountCents: Int

    var id: Int { groupId }

    private enum CodingKeys: String, CodingKey {
        case groupId, groupName
        case amountCents = "amount"
    }
}
