//
//  GroupSettingsView.swift
//  Splitty
//

import SwiftUI

struct GroupSettingsView: View {
    let group: GroupDetail
    let onGroupSaved: () -> Void

    @State private var showingEditSheet = false

    var body: some View {
        List {
            Section {
                groupInformationRow
            }

            // #62 adds the member list and its actions here.
            Section("Members") {
                EmptyView()
            }

            // #64 adds the leave control here, after membership.
            Section {
                EmptyView()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("background"))
        .navigationTitle("Group settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color("background"), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showingEditSheet) {
            GroupFormSheet(group: group) { _ in
                onGroupSaved()
            }
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

            Button("Edit") {
                showingEditSheet = true
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var groupDescription: String {
        guard let description = group.description,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "No description" }

        return description
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
                members: []
            ),
            onGroupSaved: {}
        )
    }
}
