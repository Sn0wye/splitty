import SwiftUI
import UIKit

struct InviteView: View {
    let groupId: Int
    let groupName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state = CreationState.idle
    @State private var hasStartedCreation = false
    @State private var isCopied = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            switch state {
            case .idle, .loading:
                ProgressView("Creating invite…")
                    .frame(maxWidth: .infinity)

            case .created(let code):
                createdContent(code: code)

            case .failed(let message):
                failureContent(message: message)
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("background"))
        .navigationTitle("Invite people")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color("background"), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            guard !hasStartedCreation else { return }
            hasStartedCreation = true
            await createInvite()
        }
    }

    private func createdContent(code: String) -> some View {
        let text = InviteShareText.make(groupName: groupName, code: code)

        return VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Invite code")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(code)
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .tracking(6)
                    .textSelection(.enabled)
                    .accessibilityLabel("Invite code \(code)")
            }

            Text("Share this code with someone you want to add to \"\(groupName)\".")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ShareLink(item: text) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    guard !isCopied else { return }
                    UIPasteboard.general.string = text
                    withAnimation(copyAnimation) {
                        isCopied = true
                    }

                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(copyAnimation) {
                            isCopied = false
                        }
                    }
                } label: {
                    Label("Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(isCopied ? .green : .accentColor)
            }
        }
    }

    private var copyAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }

    private func failureContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.red)

            Button("Try again") {
                Task { await createInvite() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @MainActor
    private func createInvite() async {
        state = .loading

        do {
            let invite = try await GroupService.shared.createInvite(groupId: groupId)
            state = .created(code: invite.code)
        } catch is CancellationError {
            state = .failed(message: "Invite creation was interrupted. Try again.")
        } catch {
            let message = (error as? APIError)?.displayMessage ?? error.localizedDescription
            state = .failed(message: message)
        }
    }
}

private enum CreationState {
    case idle
    case loading
    case created(code: String)
    case failed(message: String)
}

enum InviteShareText {
    static func make(groupName: String, code: String) -> String {
        #"Join "\#(groupName)" on Splitty with invite code \#(code)"#
    }
}

#Preview {
    NavigationStack {
        InviteView(groupId: 1, groupName: "Weekend away")
    }
}
