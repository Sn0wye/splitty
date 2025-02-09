//
//  GroupsView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct GroupsView: View {
    @StateObject private var viewModel = GroupsViewModel()
    
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
                    VStack(spacing: 10) {
                        ForEach(viewModel.groups) { group in
                            GroupCard(group: group)
                        }
                    }
                }
                .onAppear {
                    viewModel.loadGroups()
                }
                
                Spacer()
            }
        }
    }
}

#Preview {
    GroupsView()
}
