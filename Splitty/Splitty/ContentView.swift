//
//  ContentView.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        // A VStack, not a safeAreaInset: an inset is something content draws under,
        // and a list does exactly that, taking anything anchored to its bottom edge
        // (the add button) behind the bar with it. Stacked, the bar owns its space.
        VStack(spacing: 0) {
            ZStack {
                switch appState.selectedTab {
                case .groups:
                    GroupsView()
                case .group:
                    CurrentGroupView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomBar(selection: $appState.selectedTab)
        }
        .background(Color("background").ignoresSafeArea())
        .environmentObject(appState)
    }
}

/// The "Group" tab: renders whichever group was last opened.
private struct CurrentGroupView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if let groupId = appState.currentGroupId {
            GroupView(groupId: groupId)
                .id(groupId)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.system(size: 32, weight: .light))
                Text("No group selected")
                    .font(.headline)
                Text("Pick a group from the Groups tab.")
                    .font(.subheadline)
                    .foregroundColor(Color("muted-foreground"))
            }
            .foregroundColor(Color("foreground"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("background"))
        }
    }
}

#Preview {
    ContentView()
}
