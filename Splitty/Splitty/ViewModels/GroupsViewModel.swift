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
            groups = try await GroupService.shared.getGroups()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
