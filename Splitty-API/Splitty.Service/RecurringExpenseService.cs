using Splitty.Domain.Entities;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class RecurringExpenseService(
    IRecurringExpenseRepository recurringExpenseRepository,
    IGroupLedger groupLedger,
    TimeProvider timeProvider
) : IRecurringExpenseService
{
    public async Task<bool> CatchUpAsync(int groupId)
    {
        var now = timeProvider.GetUtcNow();
        var added = new List<Expense>();

        foreach (var recurring in await recurringExpenseRepository.GetByGroupAsync(groupId))
        {
            var zone = TimeZoneInfo.FindSystemTimeZoneById(recurring.TimeZone);

            // Due once local midnight has passed, so every day up to today in the zone.
            foreach (var day in RecurringSchedule.DueDaysBetween(
                         recurring.StartDate,
                         recurring.Frequency,
                         recurring.AddedThrough,
                         LocalCalendar.DayOf(now, zone)))
            {
                added.Add(RecurringExpenses.ExpenseFor(recurring, LocalCalendar.MidnightUtc(day, zone)));
                recurring.AddedThrough = day;
            }
        }

        if (added.Count == 0) return false;

        await recurringExpenseRepository.SaveCatchUpAsync(added);
        await groupLedger.RequestRecomputationAsync(groupId);

        return true;
    }

    public Task EndForMemberAsync(int groupId, int userId) =>
        recurringExpenseRepository.DeleteForMemberAsync(groupId, userId);
}

/// <summary>
/// Copies between a recurring expense and the expenses it adds. Splits are copied without
/// the membership checks an expense write runs, which is why a recurring expense ends when
/// anyone in it leaves.
/// </summary>
internal static class RecurringExpenses
{
    public static Expense ExpenseFor(RecurringExpense recurring, DateTime date) => new()
    {
        GroupId = recurring.GroupId,
        PaidBy = recurring.PaidBy,
        Amount = recurring.Amount,
        Description = recurring.Description,
        Category = recurring.Category,
        SplitMode = recurring.SplitMode,
        Type = ExpenseType.Expense,
        Date = date,
        RecurringExpenseId = recurring.Id,
        Splits = recurring.Splits.OrderBy(s => s.Id).Select(s => new ExpenseSplit
        {
            UserId = s.UserId,
            Amount = s.Amount,
            Percentage = s.Percentage
        }).ToList()
    };

    /// Sets the recurring expense's copied values from <paramref name="expense"/>.
    public static void CopyFrom(RecurringExpense recurring, Expense expense)
    {
        recurring.PaidBy = expense.PaidBy;
        recurring.Amount = expense.Amount;
        recurring.Description = expense.Description;
        recurring.Category = expense.Category;
        recurring.SplitMode = expense.SplitMode!.Value;
        recurring.Splits = expense.Splits.Select(s => new RecurringExpenseSplit
        {
            UserId = s.UserId,
            Amount = s.Amount,
            Percentage = s.Percentage
        }).ToList();
    }

    public static RepeatFrequency? FrequencyOf(Repeat repeat) => repeat switch
    {
        Repeat.Never => null,
        Repeat.Weekly => RepeatFrequency.Weekly,
        Repeat.Fortnightly => RepeatFrequency.Fortnightly,
        Repeat.Monthly => RepeatFrequency.Monthly,
        Repeat.Yearly => RepeatFrequency.Yearly,
        _ => throw new ArgumentOutOfRangeException(nameof(repeat), repeat, null)
    };

    /// The zone named by <paramref name="timeZone"/>, or a 400 when there is none.
    public static TimeZoneInfo ZoneOrThrow(string? timeZone)
    {
        if (string.IsNullOrWhiteSpace(timeZone))
        {
            throw new ArgumentException("A repeating expense needs a timeZone.");
        }

        if (!TimeZoneInfo.TryFindSystemTimeZoneById(timeZone, out var zone))
        {
            throw new ArgumentException($"'{timeZone}' is not a known time zone.");
        }

        return zone;
    }
}
