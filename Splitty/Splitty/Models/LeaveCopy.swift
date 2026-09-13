//
//  LeaveCopy.swift
//  Splitty
//

import Foundation

struct LeaveCopy: Equatable {
    let title: String
    let message: String
    let confirmationLabel: String

    init(memberCount: Int, groupName: String) {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let namedGroup = trimmedName.isEmpty ? L10n.Leave.thisGroup : "\"\(trimmedName)\""

        if memberCount == 1 {
            title = L10n.Leave.deleteTitle(namedGroup)
            message = L10n.Leave.deleteMessage
            confirmationLabel = L10n.Leave.deleteConfirm
        } else {
            title = L10n.Leave.title(namedGroup)
            message = L10n.Leave.message
            confirmationLabel = L10n.Leave.confirm
        }
    }
}
