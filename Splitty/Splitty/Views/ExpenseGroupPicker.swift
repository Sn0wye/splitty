import SwiftUI

/// "Choose a group", from the Groups tab's add button. Groups arrive most recently active
/// first (`Group.recentFirst`); the sheet keeps that order.
struct ExpenseGroupPicker: View {
    let groups: [Group]
    let onSelect: (Group) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authManager = AuthenticationManager.shared

    /// A handful of groups reads as a list on its own. Past that, say what the order is.
    private var showsRecentHeader: Bool { groups.count > 5 }

    /// The widest stack in the sheet sets the avatar column, so every name starts on the
    /// same line without leaving room for faces no row shows.
    private var avatarColumns: Int {
        groups.map { ExpenseGroupRow.stack(for: $0, currentUser: authManager.currentUser).circles }
            .max() ?? 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if showsRecentHeader {
                        Text(L10n.Groups.recent)
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .kerning(0.4)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, 20)
                    }

                    let columns = avatarColumns
                    LazyVStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color("border"))
                                    .frame(height: 0.5)
                                    .padding(.leading, ExpenseGroupRow.textInset(columns: columns))
                            }
                            Button { onSelect(group) } label: {
                                ExpenseGroupRow(group: group, avatarColumns: columns)
                            }
                            .buttonStyle(.pressable(scale: 0.98))
                            .accessibilityIdentifier("chooseGroup.row")
                        }
                    }
                    .background(Color("card"))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color("background").ignoresSafeArea())
            .navigationTitle(Text(L10n.Groups.choose))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(L10n.Common.cancel) }
                }
            }
        }
    }
}

/// A `GroupCard` at list density: the faces, the name, who is in it, and where the
/// signed-in user stands.
private struct ExpenseGroupRow: View {
    let group: Group
    let avatarColumns: Int
    @ObservedObject private var authManager = AuthenticationManager.shared

    static let faceSize: CGFloat = 32
    /// Two circles: a face and a second face or a count. More pushes the names too far in.
    static let maxFaces = 2
    static let horizontalPadding: CGFloat = 16
    static let spacing: CGFloat = 12

    /// `columns` circles overlapped by 30%, as `MultipleAvatar` draws them.
    static func avatarWidth(columns: Int) -> CGFloat {
        faceSize + CGFloat(max(columns, 1) - 1) * faceSize * 0.7
    }

    /// Dividers start past the avatars, under the text.
    static func textInset(columns: Int) -> CGFloat {
        horizontalPadding + avatarWidth(columns: columns) + spacing
    }

    static func stack(for group: Group, currentUser: User?) -> AvatarStack {
        .from(
            group.members.compactMap { MemberDisplay($0).resolved(currentUser: currentUser).avatarURL },
            total: group.members.count,
            maxFaces: maxFaces
        )
    }

    private var cents: Int { group.netBalanceCents }

    var body: some View {
        HStack(spacing: Self.spacing) {
            MultipleAvatar(
                urls: group.members.compactMap(avatarURL),
                total: group.members.count,
                faceSize: Self.faceSize,
                maxFaces: Self.maxFaces
            )
            .frame(width: Self.avatarWidth(columns: avatarColumns), alignment: .leading)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(Color("card-foreground"))
                    .lineLimit(1)
                Text(L10n.Groups.chooseRowDetail(L10n.Invite.members(group.members.count), group.currency.code))
                    .font(.subheadline)
                    .foregroundStyle(Color("muted-foreground"))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            balance
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var balance: some View {
        if cents == 0 {
            Text(L10n.People.settledUp)
                .font(.subheadline)
                .foregroundStyle(Color("muted-foreground"))
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text(cents > 0 ? L10n.Groups.youAreOwed : L10n.Groups.youOwe)
                    .font(.caption)
                    .foregroundStyle(Color("muted-foreground"))
                Text(Money.formatted(cents: abs(cents), currency: group.currency))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color(cents > 0 ? "positive" : "negative"))
            }
        }
    }

    private func avatarURL(for member: GroupMember) -> URL? {
        MemberDisplay(member).resolved(currentUser: authManager.currentUser).avatarURL
    }
}
