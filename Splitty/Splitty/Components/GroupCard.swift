//
//  GroupCard.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct GroupCard: View {
    let group: Group
    let onTap: () -> Void
    
    var positiveBalance: Bool {
        return group.netBalanceCents > 0;
    }

    private var balanceLabel: String {
        if group.netBalanceCents > 0 { return L10n.Groups.youAreOwed }
        if group.netBalanceCents < 0 { return L10n.Groups.youOwe }
        return L10n.Balances.allSettled
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        MultipleAvatar(
                            urls: group.members.compactMap { URL(string: $0.avatarUrl) },
                            total: group.members.count
                        )
                        
                        Text(group.name)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .padding(.bottom, 2)
                        
                        Text(balanceLabel)
                            .font(.system(size: 12))
                        
                        if group.netBalanceCents != 0 {
                            Text(Money.formatted(cents: abs(group.netBalanceCents)))
                                .font(.system(size: 18))
                                .fontWeight(.bold)
                                .foregroundColor(positiveBalance ? .green : .red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Image(systemName: "ellipsis")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color("card"))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)
        }
        // Shallow: the card is the width of the screen, so a small percentage is a lot of
        // travel at its edges.
        .buttonStyle(.pressable(scale: 0.98))
        // Shared across every card on purpose: a test wants "a group", not a particular
        // one, and naming them individually would tie it to whatever the data happens to be.
        .accessibilityIdentifier("groups.card")
    }
}

#Preview {
    GroupCard(group: Group(
        id: 1,
        name: "Test Group",
        description: "Test Description",
        netBalanceCents: 43_028,
        createdAt: "2025-02-02T13:53:41.950093Z",
        members: [
            GroupMember(
                id: 1,
                userId: 1,
                name: "John Doe",
                email: "johndoe@example.com",
                avatarUrl: "https://github.com/Sn0wye.png"
            )
        ]
    ), onTap: {})
    
    GroupCard(group: Group(
        id: 1,
        name: "Test Group",
        description: "Test Description",
        netBalanceCents: -34_012,
        createdAt: "2025-02-02T13:53:41.950093Z",
        members: [
            GroupMember(
                id: 1,
                userId: 1,
                name: "John Doe",
                email: "johndoe@example.com",
                avatarUrl: "https://github.com/ruymon.png"
            )
        ]
    ), onTap: {})

    GroupCard(group: Group(
        id: 3,
        name: "A very crowded dinner with a long name",
        description: nil,
        netBalanceCents: 1_250,
        createdAt: "2025-02-02T13:53:41.950093Z",
        members: (1...20).map { index in
            GroupMember(
                id: index,
                userId: index,
                name: "Member \(index)",
                email: "member\(index)@example.com",
                avatarUrl: "https://api.dicebear.com/11.x/lorelei/png?seed=\(index)"
            )
        }
    ), onTap: {})
}
