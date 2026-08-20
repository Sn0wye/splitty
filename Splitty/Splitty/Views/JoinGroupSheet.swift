//
//  JoinGroupSheet.swift
//  Splitty
//

import SwiftUI

struct JoinGroupSheet: View {
    @StateObject private var viewModel = JoinGroupViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var codeFocused: Bool
    
    /// Called with the joined group so the caller can refresh and navigate.
    let onJoined: (GroupDetail) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $viewModel.code)
                        .focused($codeFocused)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title2, design: .monospaced))
                } footer: {
                    Text("Ask a group member for their \(JoinGroupViewModel.codeLength)-character invite code.")
                }
                
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Join with code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isRedeeming {
                        ProgressView()
                    } else {
                        Button("Join") {
                            Task {
                                if let group = await viewModel.redeem() {
                                    onJoined(group)
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!viewModel.canRedeem)
                    }
                }
            }
            .onAppear { codeFocused = true }
        }
    }
}

#Preview {
    JoinGroupSheet { _ in }
}
