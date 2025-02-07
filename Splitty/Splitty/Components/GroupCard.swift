//
//  GroupCard.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct GroupCard: View {
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
                        
                        Text("You and Vini")
                            .fontWeight(.semibold)
                            .padding(.bottom, 2)
                        
                        Text("You are owed")
                            .font(.system(size: 12))
                        
                        Text("503.45$")
                            .font(.system(size: 18))
                            .fontWeight(.bold)
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
        .buttonStyle(PlainButtonStyle()) // Removes default NavigationLink styling
    }
}

struct DetailView: View {
    var body: some View {
        Text("DetailView")
    }
}

#Preview {
    GroupCard()
}
