//
//  GroupCard.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct GroupCard: View {
    let group: Group
    
    var positiveBalance: Bool {
        return group.netBalance > 0;
    }
    
    var body: some View {
        NavigationLink(destination: DetailView()) {
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        MultipleAvatar(urls: [
                            URL(string: "https://github.com/Sn0wye.png")!,
                            URL(string: "https://github.com/vinirossado.png")!,
                            URL(string: "https://github.com/diego3g.png")!
                        ])
                        
                        Text("\(group.name)")
                            .fontWeight(.semibold)
                            .padding(.bottom, 2)
                        
                        Text(group.netBalance > 0 ? "You are owed" : "You owe")
                            .font(.system(size: 12))
                        
                        Text("$\(String(format: "%.2f", abs(group.netBalance)))")
                            .font(.system(size: 18))
                            .fontWeight(.bold)
                            .foregroundColor(positiveBalance ? .green : .red)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "ellipsis")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
            .padding(.horizontal, 20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DetailView: View {
    var body: some View {
        Text("DetailView")
    }
}

#Preview {
    GroupCard(group: Group(
        id: 1,
        name: "Test Group",
        description: "Test Description",
        netBalance: 430.28,
        createdAt: "2025-02-02T13:53:41.950093Z",
        members: [
            GroupMember(
                id: 1,
                userId: 1,
                name: "John Doe",
                email: "johndoe@example.com"
            )
        ]
    ))
    
    GroupCard(group: Group(
        id: 1,
        name: "Test Group",
        description: "Test Description",
        netBalance: -340.12,
        createdAt: "2025-02-02T13:53:41.950093Z",
        members: [
            GroupMember(
                id: 1,
                userId: 1,
                name: "John Doe",
                email: "johndoe@example.com"
            )
        ]
    ))

}
