//
//  GroupFormViewModel.swift
//  Splitty
//

import SwiftUI

/// Backs the sheet used for both creating and editing a group. `existingGroup`
/// decides which of the two it is; everything else is identical.
@MainActor
class GroupFormViewModel: ObservableObject {
    @Published var name: String
    @Published var description: String
    @Published var errorMessage: String?
    @Published var isSaving = false
    
    private let existingGroupId: Int?
    
    init(existingGroupId: Int? = nil, name: String = "", description: String = "") {
        self.existingGroupId = existingGroupId
        self.name = name
        self.description = description
    }
    
    var isEditing: Bool { existingGroupId != nil }
    
    var title: String { isEditing ? "Edit group" : "New group" }
    
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }
    
    /// Returns the saved group id on success, nil on failure.
    func save() async -> Int? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            if let groupId = existingGroupId {
                let group = try await GroupService.shared.updateGroup(
                    id: groupId,
                    name: trimmedName,
                    description: trimmedDescription
                )
                return group.id
            } else {
                let group = try await GroupService.shared.createGroup(
                    name: trimmedName,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription
                )
                return group.id
            }
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }
    
    private static func message(for error: Error) -> String {
        guard case APIError.httpError(let status, _) = error else {
            return error.localizedDescription
        }
        switch status {
        case 400: return "Check the name and try again."
        case 403: return "You are not a member of this group."
        case 404: return "This group no longer exists."
        default: return "Something went wrong (\(status)). Try again."
        }
    }
}
