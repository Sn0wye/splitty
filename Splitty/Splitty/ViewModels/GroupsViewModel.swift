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
    
    func loadGroups() {
        isLoading = true
        GroupService.fetchGroups { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let fetchedGroups):
                    print("✅ Loaded \(fetchedGroups.count) groups from /groups endpoint")
                    for (index, group) in fetchedGroups.enumerated() {
                        print("📋 Group \(index + 1): id=\(group.id), name='\(group.name)', netBalance=\(group.netBalance), members=\(group.members.count)")
                    }
                    self?.groups = fetchedGroups
                case .failure(let error):
                    print("❌ Failed to load groups: \(error.localizedDescription)")
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func loadGroupsAsync() async {
        isLoading = true
        do {
            let fetchedGroups = try await GroupService.shared.getGroups()
            await MainActor.run {
                print("✅ Loaded \(fetchedGroups.count) groups from /groups endpoint (async)")
                for (index, group) in fetchedGroups.enumerated() {
                    print("📋 Group \(index + 1): id=\(group.id), name='\(group.name)', netBalance=\(group.netBalance), members=\(group.members.count)")
                }
                self.groups = fetchedGroups
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                print("❌ Failed to load groups (async): \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
