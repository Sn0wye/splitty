//
//  JoinGroupSheet.swift
//  Splitty
//

import SwiftUI

struct JoinGroupSheet: View {
    var isReview = false
    @StateObject private var viewModel = JoinGroupViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var codeFocused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakePhase = CGFloat.zero
    
    /// Called with the joined group so the caller can refresh and navigate.
    let onJoined: (GroupDetail) -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(L10n.Invite.enterCode)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)

                    inviteCodeField

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 48)
            }
            .background(Color("background"))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text(L10n.Invite.joinTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(L10n.Common.cancel) }
                }
                
                // No Join button: the code looks itself up on its last character, and a
                // failed code clears, so a button here could only ever be disabled.
                if viewModel.isLookingUp {
                    ToolbarItem(placement: .confirmationAction) {
                        ProgressView()
                    }
                }
            }
            .navigationDestination(isPresented: showingPreview) {
                if let preview = viewModel.preview {
                    InviteGroupPreview(metadata: preview, viewModel: viewModel) { group in
                        onJoined(group)
                        dismiss()
                    }
                }
            }
            .onAppear { codeFocused = !isReview }
            .onChange(of: viewModel.submissionFailureRevision) { _, _ in
                codeFocused = true
                guard !reduceMotion else { return }
                withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.2)) {
                    shakePhase += 1
                }
            }
        }
    }

    private var inviteCodeField: some View {
        codeGroup(0..<JoinGroupViewModel.codeLength)
            .accessibilityHidden(true)
            .overlay {
                InviteCodeInputField(
                    text: viewModel.code,
                    isFocused: $codeFocused,
                    isEnabled: !viewModel.isLookingUp && !isReview
                ) { proposedText, source in
                    guard viewModel.updateCode(proposedText, source: source) else { return }
                    Task { await submit() }
                }
            }
            .modifier(ShakeEffect(progress: shakePhase))
    }

    private func codeGroup(_ indices: Range<Int>) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(indices), id: \.self) { index in
                let shape = cellShape(index, in: indices)

                ZStack {
                    if isActive(index) {
                        shape.fill(Color.accentColor.opacity(0.08))
                    }

                    Text(character(at: index))
                        .font(.system(.title2, design: .monospaced, weight: .semibold))

                    if isActive(index), character(at: index).isEmpty {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: 24)
                    }
                }
                .frame(width: 48, height: 56)
                .overlay {
                    shape.strokeBorder(isActive(index) ? Color.accentColor : .clear, lineWidth: 2)
                }

                if index != indices.last {
                    Rectangle()
                        .fill(Color("border"))
                        .frame(width: 1, height: 56)
                }
            }
        }
        .background(Color("card"), in: containerShape)
        .clipShape(containerShape)
        .overlay {
            containerShape.strokeBorder(Color("border"), lineWidth: 1)
        }
    }

    private var containerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    /// End cells follow the container's corners so the focus ring never gets
    /// sheared off by the outer clip - a square ring on a rounded box is what
    /// made the first and last slots look chipped.
    private func cellShape(_ index: Int, in indices: Range<Int>) -> UnevenRoundedRectangle {
        let leading = index == indices.first ? Self.cornerRadius : 0
        let trailing = index == indices.last ? Self.cornerRadius : 0

        return UnevenRoundedRectangle(
            topLeadingRadius: leading,
            bottomLeadingRadius: leading,
            bottomTrailingRadius: trailing,
            topTrailingRadius: trailing,
            style: .continuous
        )
    }

    private static let cornerRadius: CGFloat = 12

    private func character(at index: Int) -> String {
        let characters = Array(viewModel.code)
        return index < characters.count ? String(characters[index]) : ""
    }

    private func isActive(_ index: Int) -> Bool {
        codeFocused && !viewModel.isLookingUp && index == viewModel.code.count
    }

    private var showingPreview: Binding<Bool> {
        Binding(
            get: { viewModel.preview != nil },
            set: { isPresented in
                guard !isPresented else { return }
                viewModel.dismissPreview()
                codeFocused = true
            }
        )
    }

    private func submit() async {
        guard !isReview else { return }
        await viewModel.lookUp()
        if viewModel.preview != nil { codeFocused = false }
    }
}

/// Confirms the group behind a code before anyone joins it, so a mistyped code
/// that happens to be valid can't drop the user into a stranger's group.
private struct InviteGroupPreview: View {
    let metadata: InviteMetadata
    @ObservedObject var viewModel: JoinGroupViewModel
    let onJoined: (GroupDetail) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.3.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(metadata.groupName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(L10n.Invite.members(metadata.memberCount))
                    .foregroundStyle(.secondary)

                Text(L10n.Invite.invitedBy(metadata.createdByName))
                    .foregroundStyle(.secondary)
            }

            if metadata.alreadyMember {
                Text(L10n.Invite.alreadyMember)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    if let group = await viewModel.join() { onJoined(group) }
                }
            } label: {
                if viewModel.isJoining {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(viewModel.joinTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isJoining)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("background"))
        .navigationTitle(Text(L10n.Invite.groupInvite))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isJoining)
    }
}

private struct ShakeEffect: GeometryEffect {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(progress * .pi * 6) * 8
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

#Preview {
    JoinGroupSheet { _ in }
}
