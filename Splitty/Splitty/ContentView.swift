//
//  ContentView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            GroupsView()
                .tabItem {
                    Image(systemName: "person.2.fill")
                    Text("Groups")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
    }
}

#Preview {
    ContentView()
}
