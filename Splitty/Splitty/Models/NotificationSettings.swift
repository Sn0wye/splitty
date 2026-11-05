//
//  NotificationSettings.swift
//  Splitty
//

import Foundation

/// A kind of push notification the user can switch off on its own. The raw values are the
/// server's names; see "Push notifications" in CONTEXT.md.
enum NotificationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expenseAdded = "expense_added"
    case recurringExpenseAdded = "recurring_expense_added"
    case expenseChanged = "expense_changed"
    case expenseDeleted = "expense_deleted"
    case paymentReceived = "payment_received"
    case paymentChanged = "payment_changed"
    case paymentDeleted = "payment_deleted"
    case paymentReminder = "payment_reminder"
    case inviteAccepted = "invite_accepted"
    case removedFromGroup = "removed_from_group"

    var id: String { rawValue }

    enum Section: CaseIterable, Identifiable {
        case expenses, payments, reminders, group

        var id: Self { self }

        var kinds: [NotificationKind] {
            NotificationKind.allCases.filter { $0.section == self }
        }
    }

    var section: Section {
        switch self {
        case .expenseAdded, .recurringExpenseAdded, .expenseChanged, .expenseDeleted: .expenses
        case .paymentReceived, .paymentChanged, .paymentDeleted: .payments
        case .paymentReminder: .reminders
        case .inviteAccepted, .removedFromGroup: .group
        }
    }
}

/// The in-app switches. `enabled` is the main switch; `muted` keeps the kinds switched off
/// while it is off, so switching it back on restores them.
struct NotificationSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var muted: [NotificationKind]

    func isOn(_ kind: NotificationKind) -> Bool { !muted.contains(kind) }

    func setting(_ kind: NotificationKind, on: Bool) -> NotificationSettings {
        var copy = self
        copy.muted = NotificationKind.allCases.filter { $0 == kind ? !on : muted.contains($0) }
        return copy
    }

    var body: [String: Any] {
        ["enabled": enabled, "muted": muted.map(\.rawValue)]
    }
}
