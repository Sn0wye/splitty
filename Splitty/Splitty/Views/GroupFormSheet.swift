//
//  GroupFormSheet.swift
//  Splitty
//

import SwiftUI

struct GroupFormSheet: View {
    @StateObject private var viewModel: GroupFormViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var confirmingCurrencyChange = false
    private let isReview: Bool
    
    private let onSaved: (Int) -> Void
    
    init(group: GroupDetail? = nil, isReview: Bool = false, onSaved: @escaping (Int) -> Void) {
        _viewModel = StateObject(wrappedValue: GroupFormViewModel(
            existingGroupId: group?.id,
            name: group?.name ?? "",
            description: group?.description ?? "",
            currency: group?.currency ?? .usd
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

                Section {
                    HStack(spacing: 14) {
                        fieldIcon("banknote")
                        Picker(L10n.GroupSettings.currency, selection: $viewModel.currency) {
                            ForEach(Currency.allCases) { currency in
                                Text(L10n.GroupSettings.currencyOption(currency.localizedName, currency.symbol))
                                    .tag(currency)
                            }
                        }
                        .accessibilityIdentifier("groupForm.currency")
                    }
                } footer: {
                    Text(L10n.GroupSettings.currencyFooter)
                }
                
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("background"))
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(L10n.Common.cancel) }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button {
                            if viewModel.changesCurrency {
                                confirmingCurrencyChange = true
                            } else {
                                save()
                            }
                        } label: {
                            Text(viewModel.isEditing ? L10n.Common.save : L10n.Common.create)
                        }
                        .disabled(isReview || !viewModel.canSave)
                    }
                }
            }
            .onAppear { nameFocused = !isReview }
            .alert(
                L10n.GroupSettings.changeCurrencyTitle(viewModel.currency.code),
                isPresented: $confirmingCurrencyChange
            ) {
                Button(L10n.GroupSettings.changeCurrencyConfirm, action: save)
                Button(role: .cancel) {} label: { Text(L10n.Common.cancel) }
            } message: {
                Text(L10n.GroupSettings.changeCurrencyMessage)
            }
        }
    }

    private func save() {
        Task {
            if let groupId = await viewModel.save() {
                onSaved(groupId)
                dismiss()
            }
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
