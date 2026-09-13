//
//  L10n.swift
//  Splitty
//

import Foundation

/// Tokenized user-facing copy. Keys live in `Localizable.xcstrings`; English is
/// also the `defaultValue` so tests and missing catalog entries still resolve.
enum L10n {
    nonisolated private static var locale: Locale { AppLanguage.currentLocale }

    /// Resolves a catalog entry. Interpolating values into `defaultValue` lets the
    /// localization system pick plural variations and substitutions from the catalog.
    nonisolated static func text(_ key: StaticString, default defaultValue: String.LocalizationValue) -> String {
        var resource = LocalizedStringResource(key, defaultValue: defaultValue)
        resource.locale = locale
        return String(localized: resource)
    }

    /// printf-style substitution for copy that takes arguments but needs no plural
    /// agreement. Anything with two or more arguments must use positional specifiers
    /// (`%1$@`, `%2$lld`) so translators can reorder them; use `text` for counts.
    nonisolated static func format(
        _ key: StaticString,
        default defaultValue: String.LocalizationValue,
        _ args: CVarArg...
    ) -> String {
        String(format: text(key, default: defaultValue), locale: locale, arguments: args)
    }

    enum Common {
        static var cancel: String { text("common.cancel", default: "Cancel") }
        static var ok: String { text("common.ok", default: "OK") }
        static var save: String { text("common.save", default: "Save") }
        static var create: String { text("common.create", default: "Create") }
        static var edit: String { text("common.edit", default: "Edit") }
        static var delete: String { text("common.delete", default: "Delete") }
        static var done: String { text("common.done", default: "Done") }
        static var next: String { text("common.next", default: "Next") }
        static var retry: String { text("common.retry", default: "Retry") }
        static var tryAgain: String { text("common.try_again", default: "Try again") }
        static var you: String { text("common.you", default: "You") }
        static var youLowercase: String { text("common.you_lowercase", default: "you") }
        static var someone: String { text("common.someone", default: "someone") }
        static var member: String { text("common.member", default: "member") }
        static var unknown: String { text("common.unknown", default: "Unknown") }
        static var loading: String { text("common.loading", default: "Loading...") }
        static var updating: String { text("common.updating", default: "Updating") }
        static var today: String { text("common.today", default: "Today") }
        static var yesterday: String { text("common.yesterday", default: "Yesterday") }
        static var date: String { text("common.date", default: "Date") }
    }

    enum Settings {
        static var title: String { text("settings.title", default: "Settings") }
        static var preferences: String { text("settings.preferences", default: "Preferences") }
        static var account: String { text("settings.account", default: "Account") }
        static var appearance: String { text("settings.appearance", default: "Appearance") }
        static var language: String { text("settings.language", default: "Language") }
        static var logOut: String { text("settings.log_out", default: "Log Out") }
        static var logOutConfirm: String {
            text("settings.log_out_confirm", default: "Are you sure you want to log out?")
        }
    }

    enum Language {
        static var title: String { text("language.title", default: "Language") }
    }

    enum Appearance {
        static var title: String { text("appearance.title", default: "Appearance") }
        static var footer: String {
            text(
                "appearance.footer",
                default: "System follows your device's light and dark appearance."
            )
        }
        static var system: String { text("appearance.system", default: "System") }
        static var light: String { text("appearance.light", default: "Light") }
        static var dark: String { text("appearance.dark", default: "Dark") }
    }

    enum Tabs {
        static var groups: String { text("tabs.groups", default: "Groups") }
        static var group: String { text("tabs.group", default: "Group") }
        static var people: String { text("tabs.people", default: "People") }
        static var settings: String { text("tabs.settings", default: "Settings") }
        static var addExpense: String { text("tabs.add_expense", default: "Add expense") }
    }

    enum Login {
        static var tagline: String { text("login.tagline", default: "Split expenses, settle up.") }
        static var signInGoogle: String { text("login.sign_in_google", default: "Sign in with Google") }
        static var signInApple: String { text("login.sign_in_apple", default: "Sign in with Apple") }
        static var comingSoon: String { text("login.coming_soon", default: "Coming soon") }
        static var devSignIn: String { text("login.dev_sign_in", default: "Dev sign in") }
        static var setupError: String {
            text("login.setup_error", default: "Sign-in isn't set up correctly on this build.")
        }
        static var failed: String { text("login.failed", default: "Sign-in failed. Try again.") }
        static var googleUnverified: String {
            text("login.google_unverified", default: "Google couldn't verify that account. Try again.")
        }
        static var genericError: String {
            text(
                "login.generic_error",
                default: "Something went wrong signing you in. Try again in a moment."
            )
        }
        static var network: String {
            text(
                "login.network",
                default: "Couldn't reach Splitty. Check your connection and try again."
            )
        }
    }

    enum Groups {
        static var title: String { text("groups.title", default: "Groups") }
        static var newGroup: String { text("groups.new", default: "New group") }
        static var joinWithCode: String { text("groups.join_with_code", default: "Join with code") }
        static var youAreOwed: String { text("groups.you_are_owed", default: "You are owed") }
        static var youOwe: String { text("groups.you_owe", default: "You owe") }
        static var choose: String { text("groups.choose", default: "Choose a group") }
        static var noneSelected: String { text("groups.none_selected", default: "No group selected") }
        static var pickFromTab: String {
            text("groups.pick_from_tab", default: "Pick a group from the Groups tab.")
        }
        static var couldNotStartExpense: String {
            text("groups.could_not_start_expense", default: "Could not start an expense")
        }
    }

    enum Group {
        static var backToGroups: String { text("group.back_to_groups", default: "Back to groups") }
        static var settings: String { text("group.settings", default: "Group settings") }
        static var settingsHint: String { text("group.settings_hint", default: "Opens group settings") }
        static var deleteQuestion: String { text("group.delete_question", default: "Delete?") }
        static var deleteUndone: String { text("group.delete_undone", default: "This cannot be undone.") }
        static func error(_ message: String) -> String {
            format("group.error", default: "Error: %@", message)
        }
        static var noExpenses: String {
            text("group.no_expenses", default: "No expenses yet. Add the first one.")
        }
        static var loadingBalance: String { text("group.loading_balance", default: "Loading balance...") }
        static var settleUp: String { text("group.settle_up", default: "Settle up") }
        static var charts: String { text("group.charts", default: "Charts") }
        static var balances: String { text("group.balances", default: "Balances") }
        static var export: String { text("group.export", default: "Export") }
        static func youPaidPeer(_ name: String) -> String {
            format("group.you_paid_peer", default: "You paid %@", name)
        }
        static func payerPaidPayee(_ payer: String, _ payee: String) -> String {
            format("group.payer_paid_payee", default: "%1$@ paid %2$@", payer, payee)
        }
        static func youPaidAmount(_ amount: String) -> String {
            format("group.you_paid_amount", default: "You paid %@", amount)
        }
        static func payerPaidAmount(_ payer: String, _ amount: String) -> String {
            format("group.payer_paid_amount", default: "%1$@ paid %2$@", payer, amount)
        }
        static var payment: String { text("group.payment", default: "payment") }
        static var notInvolved: String { text("group.not_involved", default: "not involved") }
        static var youLent: String { text("group.you_lent", default: "you lent") }
        static var youBorrowed: String { text("group.you_borrowed", default: "you borrowed") }
        static func deletePayment(_ amount: String) -> String {
            format("group.delete_payment", default: "Delete the %@ payment?", amount)
        }
        static func deleteExpense(_ description: String) -> String {
            format("group.delete_expense", default: "Delete \"%@\"?", description)
        }
        static func failedToLoadGroup(_ detail: String) -> String {
            format("group.failed_to_load_group", default: "Failed to load group: %@", detail)
        }
        static func failedToLoadExpenses(_ detail: String) -> String {
            format("group.failed_to_load_expenses", default: "Failed to load expenses: %@", detail)
        }
    }

    enum GroupSettings {
        static var title: String { text("group_settings.title", default: "Group settings") }
        static var members: String { text("group_settings.members", default: "Members") }
        static var invitePeople: String { text("group_settings.invite_people", default: "Invite people") }
        static var leaveGroup: String { text("group_settings.leave_group", default: "Leave group") }
        static var noDescription: String { text("group_settings.no_description", default: "No description") }
        static var removeMember: String {
            text("group_settings.remove_member", default: "Remove from group")
        }
        static var editGroup: String { text("group_settings.edit_group", default: "Edit group") }
        static var name: String { text("group_settings.name", default: "Name") }
        static var descriptionOptional: String {
            text("group_settings.description_optional", default: "Description (optional)")
        }
        static var checkName: String {
            text("group_settings.check_name", default: "Check the name and try again.")
        }
        static var notMember: String {
            text("group_settings.not_member", default: "You are not a member of this group.")
        }
        static var gone: String { text("group_settings.gone", default: "This group no longer exists.") }
    }

    enum Leave {
        static var thisGroup: String { text("leave.this_group", default: "this group") }
        static func deleteTitle(_ group: String) -> String {
            format("leave.delete_title", default: "Leave and delete %@?", group)
        }
        static var deleteMessage: String {
            text(
                "leave.delete_message",
                default: "The group and all of its expenses are deleted permanently."
            )
        }
        static var deleteConfirm: String { text("leave.delete_confirm", default: "Leave and delete") }
        static func title(_ group: String) -> String {
            format("leave.title", default: "Leave %@?", group)
        }
        static var message: String {
            text(
                "leave.message",
                default: "You will lose access to this group's expenses. You can re-join with a new invite code."
            )
        }
        static var confirm: String { text("leave.confirm", default: "Leave") }
    }

    enum People {
        static var title: String { text("people.title", default: "People") }
        static var settled: String { text("people.settled", default: "Settled") }
        static var emptyTitle: String { text("people.empty_title", default: "No people yet") }
        static var emptyMessage: String {
            text("people.empty_message", default: "People you share a group with will appear here.")
        }
        static var opensGroup: String { text("people.opens_group", default: "Opens this group") }
        static func youOwe(_ amount: String) -> String {
            format("people.you_owe", default: "You owe %@", amount)
        }
        static func owesYou(_ amount: String) -> String {
            format("people.owes_you", default: "Owes you %@", amount)
        }
        static var settledUp: String { text("people.settled_up", default: "Settled up") }
    }

    enum Expense {
        static var title: String { text("expense.title", default: "Expense") }
        static var newExpense: String { text("expense.new", default: "New expense") }
        static var editExpense: String { text("expense.edit", default: "Edit expense") }
        static var whatFor: String { text("expense.what_for", default: "What was it for?") }
        static var selectSplit: String {
            text("expense.select_split", default: "Select who this is split between")
        }
        static func leftToAssign(_ amount: String) -> String {
            format("expense.left_to_assign", default: "%@ left to assign", amount)
        }
        static func overTotal(_ amount: String) -> String {
            format("expense.over_total", default: "%@ over the total", amount)
        }
        static func percentLeft(_ percent: String) -> String {
            format("expense.percent_left", default: "%@%% left to assign", percent)
        }
        static func percentOver(_ percent: String) -> String {
            format("expense.percent_over", default: "%@%% over 100%%", percent)
        }
        static func roundsToZero(_ name: String) -> String {
            format("expense.rounds_to_zero", default: "%@'s share rounds down to nothing", name)
        }
        static var deleteA11y: String { text("expense.delete_a11y", default: "Delete expense") }
        static func deleteTitle(_ description: String) -> String {
            format("expense.delete_title", default: "Delete \"%@\"?", description)
        }
        static var deleteMessage: String {
            text("expense.delete_message", default: "This removes the expense and everyone's share of it.")
        }
        static var splitEqually: String { text("expense.split_equally", default: "Split equally") }
        static var splitByAmounts: String { text("expense.split_by_amounts", default: "Split by amounts") }
        static var splitByPercentages: String {
            text("expense.split_by_percentages", default: "Split by percentages")
        }
        static var split: String { text("expense.split", default: "Split") }
        static var unknownDate: String { text("expense.unknown_date", default: "Unknown date") }
        static func payerPaidDate(_ payer: String, _ date: String) -> String {
            format("expense.payer_paid_date", default: "%1$@ paid · %2$@", payer, date)
        }
        static var unknownDay: String { text("expense.unknown_day", default: "Unknown") }
    }

    enum Split {
        static var title: String { text("split.title", default: "Split") }
        static var paidBy: String { text("split.paid_by", default: "Paid by") }
        static var equally: String { text("split.equally", default: "Equally") }
        static var amounts: String { text("split.amounts", default: "Amounts") }
        static var percentages: String { text("split.percentages", default: "Percentages") }
        static var between: String { text("split.between", default: "Split between") }
        static var blankHint: String {
            text(
                "split.blank_hint",
                default: "Everything is assigned. A blank field is someone left out."
            )
        }
        static var you: String { text("split.you", default: "you") }
        static var someoneElse: String { text("split.someone_else", default: "someone else") }
        static var youOwe: String { text("split.you_owe", default: "you owe") }
        static func theyOwe(_ name: String) -> String {
            format("split.they_owe", default: "%@ owes", name)
        }
        static var they: String { text("split.they", default: "they") }
        static func summaryAmounts(_ payer: String) -> String {
            format("split.summary_amounts", default: "Paid by %@ and split by amounts", payer)
        }
        static func summaryPercentLeft(_ payer: String, _ percent: String) -> String {
            format("split.summary_percent_left", default: "Paid by %1$@, %2$@%% left to assign", payer, percent)
        }
        static func summaryPercentOver(_ payer: String, _ percent: String) -> String {
            format("split.summary_percent_over", default: "Paid by %1$@, %2$@%% over 100%%", payer, percent)
        }
        static func summaryPercentages(_ payer: String) -> String {
            format("split.summary_percentages", default: "Paid by %@ and split by percentages", payer)
        }
        static func summaryFullAmount(_ payer: String, _ debtor: String) -> String {
            format("split.summary_full_amount", default: "Paid by %1$@, %2$@ the full amount", payer, debtor)
        }
        static func summaryEqually(_ payer: String) -> String {
            format("split.summary_equally", default: "Paid by %@ and split equally", payer)
        }
        static func summaryEquallyBetween(_ payer: String, _ count: Int) -> String {
            text(
                "split.summary_equally_between",
                default: "Paid by \(payer) and split equally between \(count) people"
            )
        }
    }

    enum Settlement {
        static var title: String { text("settlement.title", default: "Payment") }
        static var edit: String { text("settlement.edit", default: "Edit payment") }
        static var record: String { text("settlement.record", default: "Record payment") }
        static var settleUp: String { text("settlement.settle_up", default: "Settle up") }
        static var deleteA11y: String { text("settlement.delete_a11y", default: "Delete payment") }
        static var anyMemberDelete: String {
            text(
                "settlement.any_member_delete",
                default: "Any member can delete a payment, including one someone else recorded."
            )
        }
        static func deleteTitle(_ amount: String, _ payer: String, _ payee: String) -> String {
            format(
                "settlement.delete_title",
                default: "Delete the %1$@ payment from %2$@ to %3$@?",
                amount,
                payer,
                payee
            )
        }
        static var deleteMessage: String {
            text(
                "settlement.delete_message",
                default: "The balance between them goes back to what it was before this payment."
            )
        }
        static var paidConnector: String { text("settlement.paid_connector", default: " paid ") }
        static func paymentWith(_ name: String) -> String {
            format("settlement.payment_with", default: "Payment with %@", name)
        }
        static func pay(_ name: String) -> String {
            format("settlement.pay", default: "Pay %@", name)
        }
        static func payAll(_ amount: String) -> String {
            format("settlement.pay_all", default: "Pay all %@", amount)
        }
        static func onlyOwe(_ name: String, _ amount: String) -> String {
            format("settlement.only_owe", default: "You only owe %1$@ %2$@.", name, amount)
        }
        static var recordFailed: String {
            text(
                "settlement.record_failed",
                default: "Couldn't record that payment. Pull down to refresh and try again."
            )
        }
        static func paymentTo(_ name: String) -> String {
            format("settlement.payment_to", default: "Payment to %@", name)
        }
    }

    enum Balances {
        static var title: String { text("balances.title", default: "Balances") }
        static var owedOverall: String { text("balances.owed_overall", default: "You are owed overall") }
        static var oweOverall: String { text("balances.owe_overall", default: "You owe overall") }
        static var yourBalance: String { text("balances.your_balance", default: "Your balance") }
        static var loading: String { text("balances.loading", default: "Loading balances…") }
        static var everyoneSettled: String {
            text("balances.everyone_settled", default: "Everyone is settled up")
        }
        static var recordsPayment: String { text("balances.records_payment", default: "Records a payment") }
        static var youOwe: String { text("balances.you_owe", default: "You owe") }
        static var owesYou: String { text("balances.owes_you", default: "Owes you") }
        static var settle: String { text("balances.settle", default: "Settle") }
        static func owedOverallAmount(_ amount: String) -> String {
            format("balances.owed_overall_amount", default: "You are owed %@ overall", amount)
        }
        static func oweOverallAmount(_ amount: String) -> String {
            format("balances.owe_overall_amount", default: "You owe %@ overall", amount)
        }
        static var allSettled: String { text("balances.all_settled", default: "You are all settled up") }
        static func youOwePeer(_ name: String, _ amount: String) -> String {
            format("balances.you_owe_peer", default: "You owe %1$@ %2$@", name, amount)
        }
        static func peerOwesYou(_ name: String, _ amount: String) -> String {
            format("balances.peer_owes_you", default: "%1$@ owes you %2$@", name, amount)
        }
    }

    enum Invite {
        static var creating: String { text("invite.creating", default: "Creating invite…") }
        static var title: String { text("invite.title", default: "Invite people") }
        static var code: String { text("invite.code", default: "Invite code") }
        static func codeA11y(_ code: String) -> String {
            format("invite.code_a11y", default: "Invite code %@", code)
        }
        static func shareHint(_ groupName: String) -> String {
            format(
                "invite.share_hint",
                default: "Share this code with someone you want to add to \"%@\".",
                groupName
            )
        }
        static var copy: String { text("invite.copy", default: "Copy") }
        static var share: String { text("invite.share", default: "Share") }
        static func joinSubject(_ groupName: String) -> String {
            format("invite.join_subject", default: "Join %@ on Splitty", groupName)
        }
        static func shareText(_ groupName: String, _ code: String) -> String {
            format(
                "invite.share_text",
                default: "Join \"%1$@\" on Splitty with invite code %2$@",
                groupName,
                code
            )
        }
        static var interrupted: String {
            text("invite.interrupted", default: "Invite creation was interrupted. Try again.")
        }
        static var joinTitle: String { text("invite.join_title", default: "Join with code") }
        static var enterCode: String {
            text(
                "invite.enter_code",
                default: "Enter the six-character invite code shared by a group member."
            )
        }
        static var join: String { text("invite.join", default: "Join") }
        static var checking: String { text("invite.checking", default: "Checking invite…") }
        static var groupInvite: String { text("invite.group_invite", default: "Group invite") }
        static func invitedBy(_ name: String) -> String {
            format("invite.invited_by", default: "Invited by %@", name)
        }
        static var alreadyMember: String {
            text("invite.already_member", default: "You're already a member of this group.")
        }
        static var openGroup: String { text("invite.open_group", default: "Open group") }
        static var invalidLink: String {
            text("invite.invalid_link", default: "This invite link isn't valid. Ask for a new one.")
        }
        static var invalidCode: String {
            text("invite.invalid_code", default: "That invite code isn't valid.")
        }
        static var expired: String {
            text("invite.expired", default: "That invite has expired. Ask for a new one.")
        }
        static var exhausted: String {
            text("invite.exhausted", default: "That invite has no uses left. Ask for a new one.")
        }
        static var tooMany: String {
            text("invite.too_many", default: "Too many attempts. Wait a minute and try again.")
        }
        static var linkAlert: String { text("invite.link_alert", default: "Invite link") }
        /// Plural category is chosen by the catalog, not by Swift, so locales with
        /// more than two forms stay correct without touching this call site.
        static func members(_ count: Int) -> String {
            text("invite.members", default: "\(count) members")
        }
        static var codeHint: String {
            text("invite.code_hint", default: "Submits automatically after six characters")
        }
        static var a11yEmpty: String { text("invite.a11y_empty", default: "Empty") }
        static func a11yValue(_ characters: String, _ entered: Int, _ length: Int) -> String {
            format(
                "invite.a11y_value",
                default: "%1$@, %2$lld of %3$lld characters entered",
                characters,
                entered,
                length
            )
        }
    }

    enum Errors {
        static var rejected: String {
            text("errors.rejected", default: "The server rejected this. Check the amounts and try again.")
        }
        static var notMember: String {
            text("errors.not_member", default: "You are not a member of this group.")
        }
        static var gone: String { text("errors.gone", default: "This no longer exists.") }
        static var outstandingBalance: String {
            text("errors.outstanding_balance", default: "This member has an outstanding balance.")
        }
        static func status(_ code: Int) -> String {
            format("errors.status", default: "Something went wrong (%lld). Try again.", code)
        }
        static var network: String {
            text(
                "errors.network",
                default: "Couldn't reach Splitty. Check your connection and try again."
            )
        }
        static var generic: String {
            text("errors.generic", default: "Something went wrong. Try again.")
        }
        static var groupUnavailable: String {
            text("errors.group_unavailable", default: "This group is no longer available")
        }
        static var removedMember: String { text("errors.removed_member", default: "Removed member") }
    }

    enum Keypad {
        static var delete: String { text("keypad.delete", default: "delete") }
        static var clearAmount: String { text("keypad.clear_amount", default: "Clear amount") }
        static var done: String { text("keypad.done", default: "done") }
    }
}
