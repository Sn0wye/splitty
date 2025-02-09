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
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                }
            
        }
    }
}

struct SettingsView: View {
    var body: some View {
        Text("Settings")
    }
}

#Preview {
    ContentView()
}
