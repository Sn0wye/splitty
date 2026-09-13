import SwiftUI

struct PeopleView: View {
    @StateObject private var viewModel = PeopleViewModel()
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color("background"))
                .navigationTitle(Text(L10n.People.title))
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView { Text(L10n.Common.loading) }
        case .empty:
            refreshableScroll {
                emptyState
            }
        case .error(let message):
            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 32, weight: .light))
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color("muted-foreground"))
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Text(L10n.Common.retry)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("foreground"))
            }
            .padding(24)
        case .loaded:
            refreshableScroll {
                LazyVStack(spacing: 0) {
                    peerRows(viewModel.activePeers)

                    if !viewModel.settledPeers.isEmpty {
                        Text(L10n.People.settled)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 28)
                            .padding(.bottom, 6)

                        peerRows(viewModel.settledPeers, dimmed: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func refreshableScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity)
        }
        .refreshable { await viewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 34, weight: .light))
            Text(L10n.People.emptyTitle)
                .font(.headline)
            Text(L10n.People.emptyMessage)
                .font(.subheadline)
                .foregroundStyle(Color("muted-foreground"))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color("foreground"))
        .padding(32)
    }

    @ViewBuilder
    private func peerRows(_ peers: [Peer], dimmed: Bool = false) -> some View {
        ForEach(peers) { peer in
            peerRow(peer)
                .opacity(dimmed ? 0.65 : 1)

            if peer.id != peers.last?.id {
                Divider()
                    .padding(.leading, 56)
            }
        }
    }

    private func peerRow(_ peer: Peer) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(peer.groups) { group in
                    Button {
                        appState.openGroup(group.groupId)
                    } label: {
                        HStack {
                            Text(group.groupName)
                            Spacer()
                            Text(Money.formatted(cents: group.amountCents))
                                .foregroundStyle(Color("muted-foreground"))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color("muted-foreground"))
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L10n.People.opensGroup)
                }
            }
            .padding(.leading, 54)
        } label: {
            HStack(spacing: 14) {
                MemberAvatar(display: MemberDisplay(name: peer.name, avatarURL: peer.avatarURL), size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(peer.name)
                        .font(.headline)
                    Text(peerStatement(peer))
                        .font(.subheadline)
                        .foregroundStyle(Color("muted-foreground"))
                        .opacity(viewModel.balancesPending ? 0.5 : 1)
                }
                Spacer()
                if viewModel.balancesPending {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .foregroundStyle(Color("foreground"))
        }
        .padding(.vertical, 14)
    }

    private func peerStatement(_ peer: Peer) -> String {
        if peer.netAmountCents < 0 {
            return L10n.People.youOwe(Money.formatted(cents: peer.magnitudeCents))
        }
        if peer.netAmountCents > 0 {
            return L10n.People.owesYou(Money.formatted(cents: peer.magnitudeCents))
        }
        return L10n.People.settledUp
    }
}

#Preview {
    PeopleView()
        .environmentObject(AppState())
}
