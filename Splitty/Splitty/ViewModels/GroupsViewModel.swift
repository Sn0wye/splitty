//
//  GroupsViewModel.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

class GroupsViewModel: ObservableObject {
    @Published var groups: [Group] = []
    @Published var errorMessage: String?
    
    func loadGroups() {
        GroupService.fetchGroups { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let fetchedGroups):
                    self?.groups = fetchedGroups
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
