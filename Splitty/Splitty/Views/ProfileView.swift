import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cropCandidate: CropCandidate?
    @State private var showingRemoveConfirmation = false
    @State private var showingDiscardConfirmation = false
    @FocusState private var isNameFocused: Bool

    init(user: User) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(user: user))
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        ZStack(alignment: .bottomLeading) {
                            MemberAvatar(display: MemberDisplay(viewModel.user), size: 112)

                            if !viewModel.isChangingAvatar {
                                Circle()
                                    .fill(Color("primary"))
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(Color("primary-foreground"))
                                    }
                                    .overlay {
                                        Circle()
                                            .stroke(Color("background"), lineWidth: 3)
                                    }
                                    .offset(x: -6, y: 6)
                            }

                            if viewModel.isChangingAvatar {
                                Circle()
                                    .fill(.black.opacity(0.45))
                                    .frame(width: 112, height: 112)
                                ProgressView()
                                    .tint(.white)
                                    .frame(width: 112, height: 112)
                            }
                        }
                        .padding(.leading, 6)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canChangeAvatar)
                    .accessibilityLabel(L10n.Profile.choosePhoto)
                    Spacer()
                }
                .padding(.vertical, 12)

                Button(role: .destructive) {
                    showingRemoveConfirmation = true
                } label: {
                    Label(L10n.Profile.removePhoto, systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(!viewModel.canChangeAvatar)

                if let status = uploadStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(Color("muted-foreground"))
                }

                if viewModel.canRetryUpload {
                    Button {
                        Task { await viewModel.retryUpload() }
                    } label: {
                        Label(L10n.Profile.retryUpload, systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            }

            Section(L10n.Profile.title) {
                TextField(L10n.Profile.name, text: $viewModel.name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .focused($isNameFocused)

                if !viewModel.name.isEmpty && viewModel.trimmedName.isEmpty {
                    Text(L10n.Profile.emptyName)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if isNameFocused {
                    Text("\(viewModel.nameLength)/\(ProfileViewModel.nameLimit)")
                        .foregroundStyle(Color("muted-foreground"))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .font(.footnote)
                }

                LabeledContent(L10n.Profile.email, value: viewModel.user.email)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("background"))
        .navigationTitle(L10n.Profile.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    leave()
                } label: {
                    Label(L10n.Settings.title, systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.Common.save) {
                    Task { await viewModel.save() }
                }
                .disabled(!viewModel.canSave)
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .sheet(item: $cropCandidate) { candidate in
            AvatarCropView(image: candidate.image) {
                cropCandidate = nil
                selectedPhoto = nil
            } onCrop: { crop in
                cropCandidate = nil
                selectedPhoto = nil
                Task { await viewModel.uploadAvatar(candidate.data, crop: crop) }
            }
        }
        .alert(L10n.Profile.removeConfirmation, isPresented: $showingRemoveConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Profile.remove, role: .destructive) {
                Task { await viewModel.removeAvatar() }
            }
        } message: {
            Text(L10n.Profile.removeFallback)
        }
        .alert(L10n.Profile.discardConfirmation, isPresented: $showingDiscardConfirmation) {
            Button(L10n.Profile.keepEditing, role: .cancel) {}
            Button(L10n.Profile.discard, role: .destructive) { dismiss() }
        } message: {
            Text(L10n.Profile.discardWarning)
        }
        .alert(L10n.Profile.errorTitle, isPresented: errorAlert) {
            Button(L10n.Common.ok, role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var uploadStatus: String? {
        switch viewModel.uploadState {
        case .idle: nil
        case .inProgress(.preparing): L10n.Profile.preparing
        case .inProgress(.uploading): L10n.Profile.uploading
        case .inProgress(.confirming): L10n.Profile.confirming
        case .done: L10n.Profile.updated
        case .failed(_, let message): message
        }
    }

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { throw AvatarUploadError.invalidImage }
            cropCandidate = CropCandidate(data: data, image: image)
        } catch where error.isCancellation {
            return
        } catch {
            viewModel.errorMessage = error.displayMessage
            selectedPhoto = nil
        }
    }

    private func leave() {
        if viewModel.hasUnsavedChanges {
            showingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}

private struct CropCandidate: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage
}
