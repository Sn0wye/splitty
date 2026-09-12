//
//  JoinGroupSheet.swift
//  Splitty
//

import SwiftUI

struct JoinGroupSheet: View {
    @StateObject private var viewModel = JoinGroupViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var codeFocused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakePhase = CGFloat.zero
    
    /// Called with the joined group so the caller can refresh and navigate.
    let onJoined: (GroupDetail) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    inviteCodeField
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
                        Button("Join") {}
                            .disabled(true)
                    }
                }
            }
            .onAppear { codeFocused = true }
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
        ZStack {
            InviteCodeInputField(
                text: viewModel.code,
                isFocused: $codeFocused,
                isEnabled: !viewModel.isRedeeming
            ) { proposedText, source in
                    guard viewModel.updateCode(proposedText, source: source) else { return }
                    Task { await submit() }
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)

            HStack(spacing: 8) {
                ForEach(0..<JoinGroupViewModel.codeLength, id: \.self) { index in
                    Text(character(at: index))
                        .font(.system(.title2, design: .monospaced, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color("background"), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(boxColor(at: index), lineWidth: 1.5)
                        }
                }
            }
            .accessibilityHidden(true)
            .contentShape(Rectangle())
            .onTapGesture { codeFocused = true }
            .modifier(ShakeEffect(progress: shakePhase))
        }
    }

    private func character(at index: Int) -> String {
        let characters = Array(viewModel.code)
        return index < characters.count ? String(characters[index]) : ""
    }

    private func boxColor(at index: Int) -> Color {
        index == viewModel.code.count && codeFocused ? .accentColor : Color("border")
    }

    private func submit() async {
        if let group = await viewModel.redeem() {
            onJoined(group)
            dismiss()
        }
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
