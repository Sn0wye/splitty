//
//  GroupSettingsView.swift
//  Splitty
//

import SwiftUI

struct GroupSettingsView: View {
    let group: GroupDetail
    let currentUserId: Int
    let onGroupSaved: () -> Void
    let onGroupUnavailable: (String) -> Void
    let onGroupExited: (String?) -> Void

    @State private var showingEditSheet = false
    @State private var members: [GroupMember]
    @State private var selectedMember: GroupMember?
    @State private var showingLeaveAlert = false
    @State private var isLeaving = false
    @State private var leaveErrorMessage: String?

    init(
        group: GroupDetail,
        currentUserId: Int,
        onGroupSaved: @escaping () -> Void,
        onGroupUnavailable: @escaping (String) -> Void,
        onGroupExited: @escaping (String?) -> Void
    ) {
        self.group = group
        self.currentUserId = currentUserId
        self.onGroupSaved = onGroupSaved
        self.onGroupUnavailable = onGroupUnavailable
        self.onGroupExited = onGroupExited
        _members = State(initialValue: group.members)
    }

    var body: some View {
        List {
            Section {
                groupInformationRow
            }

            Section {
                ForEach(orderedMembers) { member in
                    memberRow(member)
                }

                NavigationLink {
                    InviteView(groupId: group.id, groupName: group.name)
                } label: {
                    Label(L10n.GroupSettings.invitePeople, systemImage: "person.badge.plus")
                        .frame(minHeight: 44)
                }
            } header: {
                Text(L10n.GroupSettings.members)
            }

            Section {
                Button(role: .destructive) {
                    showingLeaveAlert = true
                } label: {
                    Label(L10n.GroupSettings.leaveGroup, systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
                .disabled(isLeaving)
            } footer: {
                if let leaveErrorMessage {
                    Text(leaveErrorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("background"))
        .navigationTitle(Text(L10n.GroupSettings.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color("background"), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showingEditSheet) {
            GroupFormSheet(group: group) { _ in
                onGroupSaved()
            }
        }
        .sheet(item: $selectedMember) { member in
            MemberDetailSheet(
                groupId: group.id,
                member: member,
                onRemoved: {
                    members.removeAll { $0.userId == member.userId }
                    onGroupSaved()
                },
                onGroupUnavailable: onGroupUnavailable
            )
        }
        .alert(leaveCopy.title, isPresented: $showingLeaveAlert) {
            Button(leaveCopy.confirmationLabel, role: .destructive) {
                Task { await leaveGroup() }
            }
            Button(role: .cancel) {} label: { Text(L10n.Common.cancel) }
        } message: {
            Text(leaveCopy.message)
        }
    }

    private var groupInformationRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)

                Text(groupDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                showingEditSheet = true
            } label: {
                Text(L10n.Common.edit)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var groupDescription: String {
        guard let description = group.description,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return L10n.GroupSettings.noDescription }

        return description
    }

    private var orderedMembers: [GroupMember] {
        members.filter { $0.userId == currentUserId }
            + members.filter { $0.userId != currentUserId }
    }

    @ViewBuilder
    private func memberRow(_ member: GroupMember) -> some View {
        let display = MemberDisplay(member)
        let row = HStack(spacing: 12) {
            MemberAvatar(display: display)

            Text(display.name)
                .foregroundStyle(display.isRemoved ? Color("muted-foreground") : Color("foreground"))

            Spacer()

            if member.userId == currentUserId {
                Text(L10n.Common.you)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color("muted-foreground"))
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color("muted-foreground"))
            }
        }
        .padding(.vertical, 2)

        if member.userId == currentUserId {
            row
        } else {
            Button { selectedMember = member } label: { row }
                .buttonStyle(.plain)
        }
    }
}

private struct MemberDetailSheet: View {
    let groupId: Int
    let member: GroupMember
    let onRemoved: () -> Void
    let onGroupUnavailable: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isRemoving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                MemberAvatar(display: MemberDisplay(member), size: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name)
                        .font(.headline)
                    Text(member.email)
                        .font(.subheadline)
                        .foregroundStyle(Color("muted-foreground"))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button(role: .destructive, action: remove) {
                HStack {
                    if isRemoving { ProgressView().controlSize(.small) }
                    Text(L10n.GroupSettings.removeMember)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isRemoving)
        }
        .padding(20)
        .presentationDetents(sheetDetents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color("background"))
    }

    private var sheetDetents: Set<PresentationDetent> {
        [.height(errorMessage == nil ? 230 : 290)]
    }

    private func remove() {
        isRemoving = true
        errorMessage = nil

        Task {
            defer { isRemoving = false }
            do {
                try await GroupService.shared.removeMember(groupId: groupId, userId: member.userId)
                dismiss()
                onRemoved()
            } catch {
                let membershipError = MembershipError(error)
                errorMessage = membershipError.message
                if membershipError.shouldLeaveScreen {
                    dismiss()
                    onGroupUnavailable(membershipError.message)
                }
            }
        }
    }
}

private extension GroupSettingsView {
    private var leaveCopy: LeaveCopy {
        LeaveCopy(memberCount: members.count, groupName: group.name)
    }

    private func leaveGroup() async {
        isLeaving = true
        leaveErrorMessage = nil
        defer { isLeaving = false }

        do {
            try await GroupService.shared.leave(groupId: group.id)
            onGroupExited(nil)
        } catch {
            let membershipError = MembershipError(error)
            if membershipError.shouldLeaveScreen {
                onGroupExited(membershipError.message)
            } else {
                leaveErrorMessage = membershipError.message
            }
        }
    }
}

#Preview {
    NavigationStack {
        GroupSettingsView(
            group: Group(
                id: 1,
                name: "Weekend away",
                description: "Cabin and groceries",
                netBalanceCents: 12_50,
                createdAt: "2026-09-11T12:00:00Z",
                members: [
                    GroupMember(id: 1, userId: 1, name: "Ana", email: "ana@example.com", avatarUrl: ""),
                    GroupMember(id: 2, userId: 2, name: "Bo", email: "bo@example.com", avatarUrl: "")
                ]
            ),
            currentUserId: 1,
            onGroupSaved: {},
            onGroupUnavailable: { _ in },
            onGroupExited: { _ in }
        )
    }
}
