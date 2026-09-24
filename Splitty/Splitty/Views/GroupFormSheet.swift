//
//  GroupFormSheet.swift
//  Splitty
//

import SwiftUI

struct GroupFormSheet: View {
    @StateObject private var viewModel: GroupFormViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    private let isReview: Bool
    
    private let onSaved: (Int) -> Void
    
    init(group: GroupDetail? = nil, isReview: Bool = false, onSaved: @escaping (Int) -> Void) {
        _viewModel = StateObject(wrappedValue: GroupFormViewModel(
            existingGroupId: group?.id,
            name: group?.name ?? "",
            description: group?.description ?? ""
        ))
        self.onSaved = onSaved
        self.isReview = isReview
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        fieldIcon("person.2")
                        TextField(L10n.GroupSettings.name, text: $viewModel.name)
                            .focused($nameFocused)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        fieldIcon("text.alignleft")
                        TextField(L10n.GroupSettings.descriptionOptional, text: $viewModel.description, axis: .vertical)
                            .lineLimit(1...3)
                    }
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
                    Button { dismiss() } label: { Text(L10n.Common.cancel) }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button {
                            Task {
                                if let groupId = await viewModel.save() {
                                    onSaved(groupId)
                                    dismiss()
                                }
                            }
                        } label: {
                            Text(viewModel.isEditing ? L10n.Common.save : L10n.Common.create)
                        }
                        .disabled(isReview || !viewModel.canSave)
                    }
                }
            }
            .onAppear { nameFocused = !isReview }
        }
    }

    private func fieldIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
            .frame(width: 24)
    }
}

#Preview {
    GroupFormSheet { _ in }
}
