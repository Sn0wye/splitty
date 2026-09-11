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
        let namedGroup = trimmedName.isEmpty ? "this group" : "\"\(trimmedName)\""

        if memberCount == 1 {
            title = "Leave and delete \(namedGroup)?"
            message = "The group and all of its expenses are deleted permanently."
            confirmationLabel = "Leave and delete"
        } else {
            title = "Leave \(namedGroup)?"
            message = "You will lose access to this group's expenses. You can re-join with a new invite code."
            confirmationLabel = "Leave"
        }
    }
}
