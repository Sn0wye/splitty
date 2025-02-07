//
//  GroupsView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct GroupsView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Groups")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Overall, you are owed $320.43")
                    }
                    
                    Spacer()
                    
                    Avatar()
                }
                .padding([.top, .horizontal])
                
                ScrollView {
                    VStack {
                        GroupCard()
                        GroupCard()
                        GroupCard()
                    }
                }
                
                Spacer()
            }
            .navigationTitle("")
        }
    }
}

#Preview {
    GroupsView()
}
