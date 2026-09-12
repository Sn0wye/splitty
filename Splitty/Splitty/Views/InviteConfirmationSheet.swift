import SwiftUI

struct InviteConfirmationSheet: View {
    @StateObject private var viewModel: InviteConfirmationViewModel
    @Environment(\.dismiss) private var dismiss

    let onOpenGroup: (GroupDetail) -> Void

    init(code: String, onOpenGroup: @escaping (GroupDetail) -> Void) {
        _viewModel = StateObject(wrappedValue: InviteConfirmationViewModel(code: code))
        self.onOpenGroup = onOpenGroup
    }

    var body: some View {
        NavigationStack {
            VStack {
                if let metadata = viewModel.metadata {
                    confirmation(metadata)
                } else if let errorMessage = viewModel.errorMessage {
                    failure(message: errorMessage)
                } else {
                    ProgressView("Checking invite…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(Color("background"))
            .navigationTitle("Group invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await viewModel.load() }
    }

    private func confirmation(_ metadata: InviteMetadata) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.3.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text(metadata.groupName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(memberCountText(metadata.memberCount))
                    .foregroundStyle(.secondary)

                Text("Invited by \(metadata.createdByName)")
                    .foregroundStyle(.secondary)
            }

            if metadata.alreadyMember {
                Text("You're already a member of this group.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await proceed() }
            } label: {
                if viewModel.isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(viewModel.actionTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isSubmitting)
        }
    }

    private func failure(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.red)

            Button("Try again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    private func memberCountText(_ count: Int) -> String {
        count == 1 ? "1 member" : "\(count) members"
    }

    private func proceed() async {
        guard let group = await viewModel.proceed() else { return }
        onOpenGroup(group)
        dismiss()
    }
}
