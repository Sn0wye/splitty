//
//  GroupFormSheet.swift
//  Splitty
//

import SwiftUI

struct GroupFormSheet: View {
    @StateObject private var viewModel: GroupFormViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    
    private let onSaved: (Int) -> Void
    
    init(group: GroupDetail? = nil, onSaved: @escaping (Int) -> Void) {
        _viewModel = StateObject(wrappedValue: GroupFormViewModel(
            existingGroupId: group?.id,
            name: group?.name ?? "",
            description: group?.description ?? ""
        ))
        self.onSaved = onSaved
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $viewModel.name)
                        .focused($nameFocused)
                    TextField("Description (optional)", text: $viewModel.description, axis: .vertical)
                        .lineLimit(1...3)
                }
                
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button(viewModel.isEditing ? "Save" : "Create") {
                            Task {
                                if let groupId = await viewModel.save() {
                                    onSaved(groupId)
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!viewModel.canSave)
                    }
                }
            }
            .onAppear { nameFocused = true }
        }
    }
}

#Preview {
    GroupFormSheet { _ in }
}
