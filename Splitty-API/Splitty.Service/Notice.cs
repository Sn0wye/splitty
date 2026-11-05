using Splitty.Domain.Entities;

namespace Splitty.Service;

/// <summary>
/// The sentence a push notification says. Each one belongs to the
/// <see cref="NotificationKind"/> a user switches off, and several sentences share a kind
/// when the recipient's role changes the wording: the payer of an expense is told what they
/// paid, a participant what their share is.
/// </summary>
public enum NoticeMessage
{
    ExpenseAdded,
    ExpenseAddedPaidByYou,
    RecurringExpenseAdded,
    RecurringExpenseAddedPaidByYou,
    ExpenseShareChanged,
    ExpenseIncludedYou,
    ExpenseRemovedYou,
    ExpensePaidTotalChanged,
    ExpensePayerChanged,
    ExpenseDeleted,
    ExpenseDeletedPaidByYou,
    PaymentReceived,
    PaymentToYouChangedByPayer,
    PaymentToYouChanged,
    YourPaymentChangedByPayee,
    YourPaymentChanged,
    PaymentToYouDeletedByPayer,
    PaymentToYouDeleted,
    YourPaymentDeletedByPayee,
    YourPaymentDeleted,
    PaymentReminder,
    InviteAccepted,
    RemovedFromGroup
}

/// <summary>
/// One push notification for one user, decided when the write succeeds and sent later by the
/// worker. Built only from the row the write touched, never from balances, so the
/// eventually consistent ledger cannot make it stale.
/// </summary>
/// <param name="ActorId">Who did it. Never the recipient.</param>
public sealed record Notice(int RecipientId, NoticeMessage Message, int GroupId, int ActorId)
{
    /// The expense or settlement the notice is about: the tap opens its group, and edits to
    /// it replace the notification instead of stacking.
    public int? ExpenseId { get; init; }

    public string? Description { get; init; }

    /// The amount the sentence is about: the recipient's share, what they paid, or a payment.
    /// For a change it is the amount after.
    public decimal? Amount { get; init; }

    /// The amount before, for a change.
    public decimal? Before { get; init; }

    /// The other person a payment notice names, when that is not the actor.
    public int? PeerId { get; init; }

    public RepeatFrequency? Frequency { get; init; }

    public NotificationKind Kind => Message switch
    {
        NoticeMessage.ExpenseAdded or NoticeMessage.ExpenseAddedPaidByYou => NotificationKind.ExpenseAdded,
        NoticeMessage.RecurringExpenseAdded or NoticeMessage.RecurringExpenseAddedPaidByYou =>
            NotificationKind.RecurringExpenseAdded,
        NoticeMessage.ExpenseShareChanged or NoticeMessage.ExpenseIncludedYou or NoticeMessage.ExpenseRemovedYou
            or NoticeMessage.ExpensePaidTotalChanged or NoticeMessage.ExpensePayerChanged =>
            NotificationKind.ExpenseChanged,
        NoticeMessage.ExpenseDeleted or NoticeMessage.ExpenseDeletedPaidByYou => NotificationKind.ExpenseDeleted,
        NoticeMessage.PaymentReceived => NotificationKind.PaymentReceived,
        NoticeMessage.PaymentToYouChangedByPayer or NoticeMessage.PaymentToYouChanged
            or NoticeMessage.YourPaymentChangedByPayee or NoticeMessage.YourPaymentChanged =>
            NotificationKind.PaymentChanged,
        NoticeMessage.PaymentToYouDeletedByPayer or NoticeMessage.PaymentToYouDeleted
            or NoticeMessage.YourPaymentDeletedByPayee or NoticeMessage.YourPaymentDeleted =>
            NotificationKind.PaymentDeleted,
        NoticeMessage.PaymentReminder => NotificationKind.PaymentReminder,
        NoticeMessage.InviteAccepted => NotificationKind.InviteAccepted,
        NoticeMessage.RemovedFromGroup => NotificationKind.RemovedFromGroup,
        _ => throw new ArgumentOutOfRangeException(nameof(Message), Message, null)
    };
}

/// <summary>
/// What an expense looked like to the people in it: who paid, the total, and each
/// participant's share. Taken before an edit so the change can be told per person.
/// </summary>
public sealed record ExpenseShape(
    int Id,
    string Description,
    int PaidBy,
    decimal Amount,
    IReadOnlyDictionary<int, decimal> Shares,
    RepeatFrequency? Frequency = null)
{
    public static ExpenseShape Of(Expense expense) => new(
        expense.Id,
        expense.Description,
        expense.PaidBy,
        expense.Amount,
        expense.Splits.GroupBy(s => s.UserId).ToDictionary(g => g.Key, g => g.Sum(s => s.Amount)),
        expense.RecurringExpense?.Frequency);

    /// The payer and every participant.
    public IEnumerable<int> People => Shares.Keys.Append(PaidBy).Distinct();
}

/// <summary>
/// Decides who hears about a write and what each of them is told. Pure, so the rules read
/// in one place: the actor is never told about their own action, and an expense change is
/// told only to someone whose money in it moved.
/// </summary>
public static class Notices
{
    public static IEnumerable<Notice> ExpenseAdded(ExpenseShape expense, int groupId, int actorId) =>
        expense.People.Where(id => id != actorId).Select(id =>
        {
            var recurring = expense.Frequency is not null;
            var (message, amount) = expense.Shares.TryGetValue(id, out var share)
                ? (recurring ? NoticeMessage.RecurringExpenseAdded : NoticeMessage.ExpenseAdded, share)
                : (recurring ? NoticeMessage.RecurringExpenseAddedPaidByYou : NoticeMessage.ExpenseAddedPaidByYou,
                    expense.Amount);

            return About(expense, new Notice(id, message, groupId, actorId) { Amount = amount });
        });

    public static IEnumerable<Notice> ExpenseDeleted(ExpenseShape expense, int groupId, int actorId) =>
        expense.People.Where(id => id != actorId).Select(id =>
            About(expense, expense.Shares.TryGetValue(id, out var share)
                ? new Notice(id, NoticeMessage.ExpenseDeleted, groupId, actorId) { Amount = share }
                : new Notice(id, NoticeMessage.ExpenseDeletedPaidByYou, groupId, actorId) { Amount = expense.Amount }));

    /// <summary>
    /// One notice per person whose money in the expense moved, with the change that matters
    /// most to them: being added or removed, then their share, then what they paid. A
    /// description, category or date edit tells no one.
    /// </summary>
    public static IEnumerable<Notice> ExpenseChanged(ExpenseShape before, ExpenseShape after, int groupId, int actorId)
    {
        foreach (var id in before.People.Concat(after.People).Distinct().Where(id => id != actorId))
        {
            var wasIn = before.Shares.TryGetValue(id, out var oldShare);
            var isIn = after.Shares.TryGetValue(id, out var newShare);
            var paidBefore = before.PaidBy == id;
            var paidAfter = after.PaidBy == id;

            Notice? notice = (wasIn, isIn) switch
            {
                (true, false) => new Notice(id, NoticeMessage.ExpenseRemovedYou, groupId, actorId),
                (false, true) => new Notice(id, NoticeMessage.ExpenseIncludedYou, groupId, actorId) { Amount = newShare },
                (true, true) when oldShare != newShare =>
                    new Notice(id, NoticeMessage.ExpenseShareChanged, groupId, actorId) { Before = oldShare, Amount = newShare },
                _ when paidBefore && paidAfter && before.Amount != after.Amount =>
                    new Notice(id, NoticeMessage.ExpensePaidTotalChanged, groupId, actorId)
                    {
                        Before = before.Amount, Amount = after.Amount
                    },
                _ when paidBefore != paidAfter => new Notice(id, NoticeMessage.ExpensePayerChanged, groupId, actorId),
                _ => null
            };

            if (notice is not null)
            {
                yield return About(after, notice);
            }
        }
    }

    /// Settling is always caller-as-debtor, so the payer recorded it and only the payee hears.
    public static IEnumerable<Notice> PaymentRecorded(int expenseId, int groupId, int payerId, int payeeId, decimal amount)
    {
        yield return new Notice(payeeId, NoticeMessage.PaymentReceived, groupId, payerId)
        {
            ExpenseId = expenseId, Amount = amount
        };
    }

    /// Any member may edit a payment, so both sides hear, minus whoever made the edit.
    public static IEnumerable<Notice> PaymentChanged(
        int expenseId, int groupId, int actorId, int payerId, int payeeId, decimal before, decimal after)
    {
        if (before == after)
        {
            return [];
        }

        return Payment(expenseId, groupId, actorId, payerId, payeeId,
            NoticeMessage.PaymentToYouChangedByPayer, NoticeMessage.PaymentToYouChanged,
            NoticeMessage.YourPaymentChangedByPayee, NoticeMessage.YourPaymentChanged,
            n => n with { Before = before, Amount = after });
    }

    public static IEnumerable<Notice> PaymentDeleted(
        int expenseId, int groupId, int actorId, int payerId, int payeeId, decimal amount) =>
        Payment(expenseId, groupId, actorId, payerId, payeeId,
            NoticeMessage.PaymentToYouDeletedByPayer, NoticeMessage.PaymentToYouDeleted,
            NoticeMessage.YourPaymentDeletedByPayee, NoticeMessage.YourPaymentDeleted,
            n => n with { Amount = amount });

    private static IEnumerable<Notice> Payment(
        int expenseId, int groupId, int actorId, int payerId, int payeeId,
        NoticeMessage toYouByPayer, NoticeMessage toYou, NoticeMessage yoursByPayee, NoticeMessage yours,
        Func<Notice, Notice> amounts)
    {
        if (payeeId != actorId)
        {
            yield return amounts(actorId == payerId
                ? new Notice(payeeId, toYouByPayer, groupId, actorId) { ExpenseId = expenseId }
                : new Notice(payeeId, toYou, groupId, actorId) { ExpenseId = expenseId, PeerId = payerId });
        }

        if (payerId != actorId)
        {
            yield return amounts(actorId == payeeId
                ? new Notice(payerId, yoursByPayee, groupId, actorId) { ExpenseId = expenseId }
                : new Notice(payerId, yours, groupId, actorId) { ExpenseId = expenseId, PeerId = payeeId });
        }
    }

    private static Notice About(ExpenseShape expense, Notice notice) => notice with
    {
        ExpenseId = expense.Id,
        Description = expense.Description,
        Frequency = expense.Frequency
    };
}
