//
//  GroupsViewModel.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

@MainActor
class GroupsViewModel: ObservableObject {
    @Published var groups: [Group] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    
    func loadGroups() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let fetchedGroups = try await GroupService.shared.getGroups()
            print("✅ Loaded \(fetchedGroups.count) groups from /groups endpoint")
            for (index, group) in fetchedGroups.enumerated() {
                print("📋 Group \(index + 1): id=\(group.id), name='\(group.name)', netBalance=\(group.netBalance), members=\(group.members.count)")
            }
            groups = fetchedGroups
        } catch {
            print("❌ Failed to load groups: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}
