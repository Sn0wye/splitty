using Splitty.Domain.Entities;
using Splitty.DTO.Internal;
using Splitty.DTO.Response;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

/// <summary>
/// Every write here changes money, so each one that succeeds requests its own recomputation
/// rather than leaving that to the caller. A route that saved an expense without it would
/// leave balances describing rows that no longer exist — invariant 1.
/// </summary>
public class ExpenseService(
    IExpenseRepository expenseRepository,
    IRecurringExpenseRepository recurringExpenseRepository,
    IRecurringExpenseService recurringExpenseService,
    IGroupLedger groupLedger,
    IGroupReadModel readModel,
    TimeProvider timeProvider
    ): IExpenseService
{
    public async Task<ExpenseResponse> CreateAsync(CreateExpenseDTO dto, int userId)
    {
        // Percentages are meaningless off a percentage expense, so they are dropped rather
        // than refused: a client that sends both a mode and leftover percentages is
        // describing an equal split, and the stored rows should say only that.
        var percentages = PercentagesFor(dto.SplitMode, dto.ExpenseSplits.Select(s => s.Percentage));

        EnsureNotPaymentCategory(dto.Category);

        ExpenseSplitInvariants.Ensure(
            ExpenseType.Expense,
            dto.SplitMode,
            dto.Amount,
            dto.ExpenseSplits.Zip(percentages, (s, p) => new SplitShape(s.Amount, p)));

        var splits = dto.ExpenseSplits;

        await EnsureMemberAsync(dto.GroupId, userId);
        await EnsureMemberAsync(dto.GroupId, dto.PaidBy);
        await EnsureMembersAsync(dto.GroupId, splits.Select(s => s.UserId));

        var expense = new Expense
        {
            Amount = dto.Amount,
            Description = dto.Description,
            GroupId = dto.GroupId,
            PaidBy = dto.PaidBy,
            Date = ExpenseDate.Normalize(dto.Date),
            Category = dto.Category ?? ExpenseCategory.General,
            SplitMode = dto.SplitMode,
            Splits = splits.Zip(percentages, (s, percentage) => new ExpenseSplit
            {
                Amount = s.Amount,
                UserId = s.UserId,
                Percentage = percentage,
            }).ToList()
        };

        // Saved with its first expense in one insert, so neither exists without the other.
        if (dto.Repeat is { } repeat && RecurringExpenses.FrequencyOf(repeat) is { } frequency)
        {
            expense.RecurringExpense = StartRecurring(expense, frequency, dto.TimeZone);
        }

        await expenseRepository.CreateAsync(expense);
        await groupLedger.RequestRecomputationAsync(expense.GroupId);
        
        return await readModel.GetExpenseAsync(expense.GroupId, expense.Id, userId);
    }

    /// <summary>
    /// Refuses settlements: they are deleted through their own route, which re-reads the
    /// cap and keeps one delete path per row type. See
    /// docs/adr/0001-settlements-have-their-own-routes.md.
    /// </summary>
    public async Task DeleteAsync(int groupId, int expenseId, int userId, ExpenseScope scope = ExpenseScope.This)
    {
        await EnsureMemberAsync(groupId, userId);

        var expense = await FindInGroupAsync(groupId, expenseId);

        if (expense.Type == ExpenseType.Payment)
        {
            throw new InvalidOperationException(
                "This is a settlement. Delete it through /group/{groupId}/settlements/{expenseId}.");
        }

        if (scope == ExpenseScope.Following)
        {
            var recurringExpenseId = RecurringExpenseIdOrThrow(expense);
            var later = await expenseRepository.GetAddedAfterAsync(recurringExpenseId, DateOf(expense));
            var recurring = await recurringExpenseRepository.GetForUpdateAsync(recurringExpenseId);

            await expenseRepository.SaveFollowingAsync(later.Append(expense), recurring);
        }
        else
        {
            // The recurring expense keeps going. Its AddedThrough is unchanged, so this
            // expense is never added again.
            await expenseRepository.DeleteAsync(expense);
        }

        await groupLedger.RequestRecomputationAsync(groupId);
    }
    
    public async Task<ExpenseResponse> UpdateAsync(UpdateExpenseDTO dto, int userId)
    {
        // The rows and the mode naming them are one fact. Accepting new splits without a
        // mode would leave the stored mode describing rows it has never seen.
        if (dto.ExpenseSplits is not null && dto.SplitMode is null)
        {
            throw new ArgumentException("An update that changes the splits must also send the split mode.");
        }

        if (dto.Repeat is not null && dto.Scope != ExpenseScope.Following)
        {
            throw new ArgumentException("repeat changes the expenses that follow, so it needs scope=following.");
        }

        if (dto.TimeZone is not null && dto.Scope != ExpenseScope.Following)
        {
            throw new ArgumentException("timeZone moves the expenses that follow, so it needs scope=following.");
        }

        // Resolved before anything is written, so an unknown zone refuses the whole edit.
        var zone = dto.TimeZone is null ? null : RecurringExpenses.ZoneOrThrow(dto.TimeZone);

        var expense = await expenseRepository.GetForUpdateAsync(dto.Id);

        if (expense is null)
        {
            throw new KeyNotFoundException("Expense not found");
        }

        // The expense must belong to the group the request was made against,
        // otherwise a member of group A could edit an expense of group B.
        if (dto.GroupId is not null && dto.GroupId != expense.GroupId)
        {
            throw new UnauthorizedAccessException("Expense does not belong to the group");
        }

        await EnsureMemberAsync(expense.GroupId, userId);

        // Same reason the delete route refuses them: a settlement's amount is capped and its
        // splits are rebuilt rather than accepted, neither of which this path does.
        if (expense.Type == ExpenseType.Payment)
        {
            throw new InvalidOperationException(
                "This is a settlement. Edit it through /group/{groupId}/settlements/{expenseId}.");
        }

        EnsureNotPaymentCategory(dto.Category);

        // Read before the edit moves it: "following" means after where the expense was.
        var originalDate = DateOf(expense);
        var recurringExpenseId = dto.Scope == ExpenseScope.Following ? RecurringExpenseIdOrThrow(expense) : (int?)null;

        // Validate the resulting state, not just the supplied fields: an
        // amount-only update must not leave a nonmember payer or split behind.
        await EnsureMemberAsync(expense.GroupId, dto.PaidBy ?? expense.PaidBy);
        await EnsureMembersAsync(
            expense.GroupId,
            dto.ExpenseSplits is not null
                ? dto.ExpenseSplits.Select(s => s.UserId)
                : expense.Splits.Select(s => s.UserId));

        var resultingAmount = dto.Amount ?? expense.Amount;
        var resultingMode = dto.SplitMode ?? expense.SplitMode;

        // Validate the mode against the rows it will actually name, which for a mode-only
        // edit are the rows already stored. Leaving percentage mode nulls them here too,
        // so an expense never carries percentages its mode does not claim.
        var resultingAmounts = dto.ExpenseSplits is not null
            ? dto.ExpenseSplits.Select(s => s.Amount).ToList()
            : expense.Splits.Select(s => s.Amount).ToList();
        var resultingPercentages = PercentagesFor(
            resultingMode,
            dto.ExpenseSplits is not null
                ? dto.ExpenseSplits.Select(s => s.Percentage)
                : expense.Splits.Select(s => s.Percentage));

        ExpenseSplitInvariants.Ensure(
            expense.Type,
            resultingMode,
            resultingAmount,
            resultingAmounts.Zip(resultingPercentages, (amount, percentage) => new SplitShape(amount, percentage)));

        expense.Amount = resultingAmount;
        expense.SplitMode = resultingMode;
        expense.Category = dto.Category ?? expense.Category;
        expense.Description = dto.Description ?? expense.Description;
        expense.PaidBy = dto.PaidBy ?? expense.PaidBy;
        expense.Date = ExpenseDate.Normalize(dto.Date) ?? expense.Date;
        expense.UpdatedAt = DateTime.UtcNow;

        // Sent splits replace the stored rows outright: the old rows are orphaned and deleted,
        // the new ones inserted. A row is never re-pointed, so an edit cannot reach another
        // expense's split however the request is shaped.
        if (dto.ExpenseSplits is not null)
        {
            expense.Splits = dto.ExpenseSplits.Zip(resultingPercentages, (s, percentage) => new ExpenseSplit
            {
                Amount = s.Amount,
                UserId = s.UserId,
                Percentage = percentage,
            }).ToList();
        }
        else
        {
            foreach (var (split, percentage) in expense.Splits.Zip(resultingPercentages))
            {
                split.Percentage = percentage;
            }
        }
        
        if (recurringExpenseId is { } id)
        {
            await UpdateFollowingAsync(expense, id, originalDate, dto.Repeat, zone);
        }
        else
        {
            await expenseRepository.UpdateAsync(expense);
            await groupLedger.RequestRecomputationAsync(expense.GroupId);
        }

        return await readModel.GetExpenseAsync(expense.GroupId, expense.Id, userId);
    }

    /// <summary>
    /// Applies an edit already made to <paramref name="expense"/> to every expense after it:
    /// the recurring expense restarts from this one and the later ones it added are rewritten
    /// onto the new days (see <see cref="RestartFrom"/>). <see cref="Repeat.Never"/> deletes
    /// the later ones and the recurring expense instead, leaving this one and the earlier ones
    /// plain. Either way the group catches up, all in one transaction, and the recomputation
    /// is requested once it has committed.
    /// </summary>
    private async Task UpdateFollowingAsync(
        Expense expense,
        int recurringExpenseId,
        DateTime originalDate,
        Repeat? repeat,
        TimeZoneInfo? zone)
    {
        var later = await expenseRepository.GetAddedAfterAsync(recurringExpenseId, originalDate);
        var recurring = await recurringExpenseRepository.GetForUpdateAsync(recurringExpenseId)
            ?? throw new KeyNotFoundException("Recurring expense not found");

        var frequency = repeat is { } r ? RecurringExpenses.FrequencyOf(r) : recurring.Frequency;

        // A new zone re-expresses every expense it added, so the earlier ones are needed too.
        var laterIds = later.Select(e => e.Id).ToHashSet();
        var earlier = frequency is not null && zone is not null && zone.Id != recurring.TimeZone
            ? (await expenseRepository.GetAddedAsync(recurringExpenseId))
                .Where(e => e.Id != expense.Id && !laterIds.Contains(e.Id))
                .ToList()
            : [];

        var removed = frequency is { } f
            ? RestartFrom(recurring, expense, originalDate, f, zone, earlier, later)
            : later;

        await expenseRepository.InTransactionAsync(async () =>
        {
            await expenseRepository.SaveFollowingAsync(removed, stopped: frequency is null ? recurring : null);
            await recurringExpenseService.AddDueAsync(expense.GroupId);
        });

        await groupLedger.RequestRecomputationAsync(expense.GroupId);
    }

    /// <summary>
    /// Restarts <paramref name="recurring"/> from <paramref name="expense"/>'s values, day,
    /// <paramref name="frequency"/> and, when one is given, <paramref name="newZone"/>, and
    /// rewrites the <paramref name="later"/> expenses onto the new days. Each keeps its place:
    /// the nth repeat after this expense stays the nth, so one deleted on its own stays a gap
    /// rather than being added again. A place whose new day is not due yet is dropped, since
    /// nothing is added before it is due. Returns the expenses to delete.
    ///
    /// Every expense it added is stored as local midnight of its day in its zone. A new zone
    /// keeps each day and moves its midnight, the <paramref name="earlier"/> expenses
    /// included, so an edit made later from the new zone reads the same days.
    /// </summary>
    private List<Expense> RestartFrom(
        RecurringExpense recurring,
        Expense expense,
        DateTime originalDate,
        RepeatFrequency frequency,
        TimeZoneInfo? newZone,
        List<Expense> earlier,
        List<Expense> later)
    {
        var oldZone = TimeZoneInfo.FindSystemTimeZoneById(recurring.TimeZone);
        var zone = newZone ?? oldZone;
        var originalDay = LocalCalendar.DayOf(originalDate, oldZone);

        // The places after this expense that were already added, under the old values.
        var oldDays = RecurringDueDays.DueDaysBetween(
            recurring.StartDate,
            recurring.Frequency,
            originalDay,
            recurring.AddedThrough).ToList();

        // A date is the day the member picked where they are, the zone they sent. Clients
        // resend the date they were given, and an unchanged date is not a move however its
        // two zones read it: it stays the day it was.
        var moved = LocalCalendar.DayOf(DateOf(expense), zone) != LocalCalendar.DayOf(originalDate, zone);
        var startDay = moved ? LocalCalendar.DayOf(DateOf(expense), zone) : originalDay;

        RecurringExpenses.CopyFrom(recurring, expense);
        recurring.Frequency = frequency;
        recurring.StartDate = startDay;
        recurring.UpdatedAt = DateTime.UtcNow;

        if (zone.Id != oldZone.Id)
        {
            foreach (var earlierExpense in earlier)
            {
                earlierExpense.Date = LocalCalendar.MidnightUtc(LocalCalendar.DayOf(DateOf(earlierExpense), oldZone), zone);
                earlierExpense.UpdatedAt = DateTime.UtcNow;
            }

            expense.Date = LocalCalendar.MidnightUtc(startDay, zone);
            recurring.TimeZone = zone.Id;
        }

        var today = LocalCalendar.DayOf(timeProvider.GetUtcNow(), zone);
        var kept = Enumerable.Range(1, oldDays.Count)
            .TakeWhile(n => RecurringDueDays.DueDay(recurring.StartDate, frequency, n) <= today)
            .Count();

        // Covers the gaps too, so catch-up adds only places that were never added.
        recurring.AddedThrough = RecurringDueDays.DueDay(recurring.StartDate, frequency, kept);

        var removed = new List<Expense>();

        foreach (var laterExpense in later)
        {
            // An expense moved off its day on its own counts as the latest place on or before it.
            var day = LocalCalendar.DayOf(DateOf(laterExpense), oldZone);
            var place = Math.Max(1, oldDays.Count(d => d <= day));

            if (place > kept)
            {
                removed.Add(laterExpense);
                continue;
            }

            var newDay = RecurringDueDays.DueDay(recurring.StartDate, frequency, place);
            RecurringExpenses.CopyTo(laterExpense, recurring, LocalCalendar.MidnightUtc(newDay, zone));
            laterExpense.UpdatedAt = DateTime.UtcNow;
        }

        return removed;
    }

    /// <summary>
    /// The recurring expense <paramref name="first"/> starts, unsaved. Its start day is the
    /// expense's date, or now, as a day in <paramref name="timeZone"/>, and may not be
    /// before today there: a mistyped date must not add months of expenses.
    /// </summary>
    private RecurringExpense StartRecurring(Expense first, RepeatFrequency frequency, string? timeZone)
    {
        var zone = RecurringExpenses.ZoneOrThrow(timeZone);
        var now = timeProvider.GetUtcNow();
        var today = LocalCalendar.DayOf(now, zone);
        var start = first.Date is { } date ? LocalCalendar.DayOf(date, zone) : today;

        if (start < today)
        {
            throw new ArgumentException("A repeating expense cannot start before today.");
        }

        var recurring = new RecurringExpense
        {
            GroupId = first.GroupId,
            Description = first.Description,
            Frequency = frequency,
            StartDate = start,
            AddedThrough = start,
            TimeZone = zone.Id
        };
        RecurringExpenses.CopyFrom(recurring, first);

        return recurring;
    }

    private static int RecurringExpenseIdOrThrow(Expense expense) =>
        expense.RecurringExpenseId
            ?? throw new ArgumentException("This expense does not repeat, so no expenses follow it.");

    /// The date an expense reads as, the same fallback the expense list sorts by.
    private static DateTime DateOf(Expense expense) => expense.Date ?? expense.CreatedAt;

    /// <summary>
    /// Payment is the category a settlement carries, and settlements are written through
    /// their own routes — a client filing an expense as one is confused about what it is
    /// writing, the same way a client editing a settlement through the expense route is.
    /// </summary>
    private static void EnsureNotPaymentCategory(ExpenseCategory? category)
    {
        if (category is ExpenseCategory.Payment)
        {
            throw new ArgumentException(
                "Payment is the category of a settlement. Record one through /group/{groupId}/settle.");
        }
    }

    /// <summary>
    /// The percentage each split row should store under <paramref name="mode"/>: what was
    /// supplied when the mode is <see cref="SplitMode.Percentage"/>, and <c>null</c>
    /// otherwise. Nulling rather than rejecting is what lets a client switch an expense
    /// back to an equal split without first stripping the fields it no longer means.
    /// </summary>
    private static List<decimal?> PercentagesFor(SplitMode? mode, IEnumerable<decimal?> supplied) =>
        mode is SplitMode.Percentage
            ? supplied.ToList()
            : supplied.Select(_ => (decimal?)null).ToList();

    /// The expense must belong to the group the request was made against, otherwise a
    /// member of group A could read or delete an expense of group B.
    private async Task<Expense> FindInGroupAsync(int groupId, int expenseId)
    {
        var expense = await expenseRepository.GetForUpdateAsync(expenseId);

        if (expense is null || expense.GroupId != groupId)
        {
            throw new KeyNotFoundException("Expense not found");
        }

        return expense;
    }

    private async Task EnsureMemberAsync(int groupId, int userId)
    {
        if (!await readModel.IsMemberAsync(groupId, userId))
        {
            throw new UnauthorizedAccessException("User is not a member of the group");
        }
    }

    private async Task EnsureMembersAsync(int groupId, IEnumerable<int> userIds)
    {
        foreach (var userId in userIds.Distinct())
        {
            await EnsureMemberAsync(groupId, userId);
        }
    }
}
