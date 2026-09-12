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
                shareLink(code: code, text: text)

                Button {
                    guard !isCopied else { return }
                    UIPasteboard.general.string = InviteShareText.copyText(code: code)
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

    @ViewBuilder
    private func shareLink(code: String, text: String) -> some View {
        if let link = InviteShareText.link(code: code) {
            ShareLink(
                item: link,
                subject: Text("Join \(groupName) on Splitty"),
                message: Text(text)
            ) {
                shareLabel
            }
            .buttonStyle(.borderedProminent)
        } else {
            ShareLink(item: text) {
                shareLabel
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var shareLabel: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .frame(maxWidth: .infinity, minHeight: 44)
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

    static func copyText(code: String) -> String { code }

    static func link(code: String, bundle: Bundle = .main) -> URL? {
        guard let host = bundle.object(forInfoDictionaryKey: "SplittyInviteHost") as? String else {
            return nil
        }
        return link(code: code, host: host)
    }

    static func link(code: String, host: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/join/\(code)"
        return components.url
    }
}

#Preview {
    NavigationStack {
        InviteView(groupId: 1, groupName: "Weekend away")
    }
}
