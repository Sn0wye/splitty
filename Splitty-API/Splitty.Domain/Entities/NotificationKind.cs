namespace Splitty.Domain.Entities;

/// <summary>
/// The kinds of push notification a user can switch off one by one. Stored by name in
/// <see cref="User.MutedNotifications"/>, so values are append-only by name, like the other
/// enums stored as text.
/// </summary>
public enum NotificationKind
{
    ExpenseAdded,
    RecurringExpenseAdded,
    ExpenseChanged,
    ExpenseDeleted,
    PaymentReceived,
    PaymentChanged,
    PaymentDeleted,
    PaymentReminder,
    InviteAccepted,
    RemovedFromGroup
}
