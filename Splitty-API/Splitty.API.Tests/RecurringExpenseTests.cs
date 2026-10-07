using System.Net;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace Splitty.API.Tests;

/// <summary>
/// A recurring expense adds its first expense at once and each later one once it is due,
/// the next time the group is opened. What it adds are ordinary expenses. See
/// docs/adr/0006-recurring-expenses-add-rows-on-group-read.md.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class RecurringExpenseTests : IDisposable
{
    /// A Tuesday, at noon UTC.
    private static readonly DateTimeOffset Now = new(2030, 1, 15, 12, 0, 0, TimeSpan.Zero);

    private readonly ApiFactory _factory;

    public RecurringExpenseTests(ApiFactory factory)
    {
        _factory = factory;
        _factory.Clock.Set(Now);
    }

    public void Dispose() => _factory.Clock.Reset();

    // Creating.

    [Fact]
    public async Task An_expense_created_without_repeat_is_plain()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        var expense = await group.CreateRecurringAsync(repeat: null, date: Now.UtcDateTime, timeZone: null);

        Assert.Equal(JsonValueKind.Null, expense.GetProperty("recurringExpenseId").ValueKind);
        Assert.Equal(JsonValueKind.Null, expense.GetProperty("repeat").ValueKind);
    }

    [Fact]
    public async Task Repeat_never_is_plain_too()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        var expense = await group.CreateRecurringAsync(repeat: "never", date: Now.UtcDateTime, timeZone: null);

        Assert.Equal(JsonValueKind.Null, expense.GetProperty("recurringExpenseId").ValueKind);
    }

    [Fact]
    public async Task Creating_a_recurring_expense_adds_its_first_expense_at_once()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        var expense = await group.CreateRecurringAsync("monthly", Now.UtcDateTime);

        Assert.Equal(JsonValueKind.Number, expense.GetProperty("recurringExpenseId").ValueKind);
        Assert.Equal("monthly", expense.GetProperty("repeat").GetString());
        // The first expense keeps the date as sent.
        Assert.Equal(Now.UtcDateTime, expense.GetProperty("date").GetDateTime());

        var listed = Assert.Single(await group.ExpensesAsync());
        Assert.Equal(expense.GetProperty("id").GetInt32(), listed.GetProperty("id").GetInt32());
        Assert.Equal("monthly", listed.GetProperty("repeat").GetString());
    }

    [Fact]
    public async Task A_future_start_still_shows_its_first_expense_and_adds_nothing_more()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        var start = Now.UtcDateTime.AddDays(10);

        var expense = await group.CreateRecurringAsync("weekly", start);
        await group.OpenAsync();

        Assert.Equal(start, expense.GetProperty("date").GetDateTime());
        Assert.Single(await group.ExpensesAsync());
    }

    [Fact]
    public async Task A_start_before_today_is_refused()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        var response = await group.Owner.CreateExpenseAsync(group.Id,
            group.RecurringBody("monthly", Now.UtcDateTime.AddDays(-1), "UTC"));

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
        Assert.Empty(await group.ExpensesAsync());
    }

    [Fact]
    public async Task Earlier_today_is_not_in_the_past()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        var response = await group.Owner.CreateExpenseAsync(group.Id,
            group.RecurringBody("monthly", new DateTime(2030, 1, 15, 0, 0, 0, DateTimeKind.Utc), "UTC"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task The_past_is_judged_in_the_given_zone()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        // 01:00 UTC on the 15th is 22:00 on the 14th in São Paulo.
        var response = await group.Owner.CreateExpenseAsync(group.Id,
            group.RecurringBody("monthly", new DateTime(2030, 1, 15, 1, 0, 0, DateTimeKind.Utc), "America/Sao_Paulo"));

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task An_unknown_or_missing_zone_is_refused()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        var unknown = await group.Owner.CreateExpenseAsync(group.Id,
            group.RecurringBody("monthly", Now.UtcDateTime, "Mars/Olympus_Mons"));
        var missing = await group.Owner.CreateExpenseAsync(group.Id,
            group.RecurringBody("monthly", Now.UtcDateTime, null));

        await ErrorResponseAssertions.AssertErrorAsync(unknown, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(missing, HttpStatusCode.BadRequest);
        Assert.Empty(await group.ExpensesAsync());
    }

    [Fact]
    public async Task An_unknown_frequency_is_refused()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        var response = await group.Owner.CreateExpenseAsync(group.Id,
            group.RecurringBody("hourly", Now.UtcDateTime, "UTC"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Empty(await group.ExpensesAsync());
    }

    // Catching up.

    [Fact]
    public async Task Nothing_is_added_before_it_is_due()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime);

        _factory.Clock.Set(Now.AddDays(6));
        await group.OpenAsync();

        Assert.Single(await group.ExpensesAsync());
    }

    [Fact]
    public async Task Opening_the_group_adds_every_missed_repeat_and_balances_include_them()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await _factory.DrainProcessedAsync();
        var first = await group.CreateRecurringAsync("weekly", Now.UtcDateTime);
        await WorkerHarness.WaitForProcessedAsync(_factory);

        _factory.Clock.Set(Now.AddDays(21));
        await group.OpenAsync();
        await WorkerHarness.WaitForProcessedAsync(_factory);

        var expenses = await group.ExpensesAsync();
        Assert.Equal(
            [Day(2030, 1, 15), Day(2030, 1, 22), Day(2030, 1, 29), Day(2030, 2, 5)],
            expenses.Select(DayOf).Order());
        Assert.All(expenses, e =>
        {
            Assert.Equal(first.GetProperty("recurringExpenseId").GetInt32(), e.GetProperty("recurringExpenseId").GetInt32());
            Assert.Equal(20m, e.GetProperty("amount").GetDecimal());
            Assert.Equal("rent", e.GetProperty("category").GetString());
            Assert.Equal("Rent", e.GetProperty("description").GetString());
            Assert.Equal(group.OwnerId, e.GetProperty("paidBy").GetInt32());
            Assert.Equal(
                [group.OwnerId, group.GuestId],
                e.GetProperty("splits").EnumerateArray().Select(s => s.GetProperty("userId").GetInt32()));
        });

        var summary = await group.Owner.ReadSummaryAsync(group.Id);
        Assert.False(summary.BalancesPending);
        Assert.Equal(40m, summary.AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task Opening_the_group_again_adds_nothing_twice()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime);

        _factory.Clock.Set(Now.AddDays(7));
        await group.OpenAsync();
        await group.OpenAsync();

        Assert.Equal(2, (await group.ExpensesAsync()).Count);
    }

    [Fact]
    public async Task The_expense_list_and_summary_do_not_catch_up()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime);

        _factory.Clock.Set(Now.AddDays(21));
        (await group.Owner.GetSummaryAsync(group.Id)).EnsureSuccessStatusCode();
        (await group.Owner.GetStatsAsync(group.Id, "tz=UTC")).EnsureSuccessStatusCode();
        (await group.Owner.GetPeopleAsync()).EnsureSuccessStatusCode();

        Assert.Single(await group.ExpensesAsync());
    }

    [Fact]
    public async Task A_monthly_expense_started_on_the_31st_clamps_and_returns()
    {
        var start = new DateTimeOffset(2030, 1, 31, 10, 0, 0, TimeSpan.Zero);
        _factory.Clock.Set(start);
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("monthly", start.UtcDateTime);

        _factory.Clock.Set(new DateTimeOffset(2030, 5, 1, 10, 0, 0, TimeSpan.Zero));
        await group.OpenAsync();

        Assert.Equal(
            [Day(2030, 1, 31), Day(2030, 2, 28), Day(2030, 3, 31), Day(2030, 4, 30)],
            (await group.ExpensesAsync()).Select(DayOf).Order());
    }

    [Fact]
    public async Task A_yearly_expense_started_on_29_february_lands_on_28_february()
    {
        var start = new DateTimeOffset(2028, 2, 29, 10, 0, 0, TimeSpan.Zero);
        _factory.Clock.Set(start);
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("yearly", start.UtcDateTime);

        _factory.Clock.Set(new DateTimeOffset(2032, 3, 1, 10, 0, 0, TimeSpan.Zero));
        await group.OpenAsync();

        Assert.Equal(
            [Day(2028, 2, 29), Day(2029, 2, 28), Day(2030, 2, 28), Day(2031, 2, 28), Day(2032, 2, 29)],
            (await group.ExpensesAsync()).Select(DayOf).Order());
    }

    [Fact]
    public async Task A_fortnightly_expense_adds_every_fourteen_days()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("fortnightly", Now.UtcDateTime);

        _factory.Clock.Set(Now.AddDays(28));
        await group.OpenAsync();

        Assert.Equal(
            [Day(2030, 1, 15), Day(2030, 1, 29), Day(2030, 2, 12)],
            (await group.ExpensesAsync()).Select(DayOf).Order());
    }

    [Fact]
    public async Task A_repeat_comes_due_at_local_midnight_in_the_zone_it_was_created_in()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        // Noon UTC is 09:00 in São Paulo, so the start day is the 15th there too.
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime, "America/Sao_Paulo");

        // 23:30 on the 21st in São Paulo, though already the 22nd in UTC.
        _factory.Clock.Set(new DateTimeOffset(2030, 1, 22, 2, 30, 0, TimeSpan.Zero));
        await group.OpenAsync();
        Assert.Single(await group.ExpensesAsync());

        // Just past midnight on the 22nd in São Paulo.
        _factory.Clock.Set(new DateTimeOffset(2030, 1, 22, 3, 1, 0, TimeSpan.Zero));
        await group.OpenAsync();

        var added = (await group.ExpensesAsync()).MaxBy(e => e.GetProperty("date").GetDateTime());
        // Stored as the instant of local midnight.
        Assert.Equal(new DateTime(2030, 1, 22, 3, 0, 0, DateTimeKind.Utc), added.GetProperty("date").GetDateTime());
    }

    // Editing and deleting one expense.

    [Fact]
    public async Task Editing_one_added_expense_leaves_the_others_and_the_recurring_expense_alone()
    {
        var group = await WeeklyThroughAsync(Now.AddDays(14));
        var second = ExpenseOn(await group.ExpensesAsync(), Day(2030, 1, 22));

        var edited = await group.Owner.ReadJsonAsync(
            await group.Owner.UpdateExpenseAsync(group.Id, Id(second), new { amount = 30m, splitMode = "equal", splits = Splits(group, 15m) }));

        Assert.Equal(second.GetProperty("recurringExpenseId").GetInt32(), edited.GetProperty("recurringExpenseId").GetInt32());
        Assert.Equal("weekly", edited.GetProperty("repeat").GetString());

        _factory.Clock.Set(Now.AddDays(21));
        await group.OpenAsync();

        Assert.Equal(
            [20m, 30m, 20m, 20m],
            (await group.ExpensesAsync()).OrderBy(DayOf).Select(e => e.GetProperty("amount").GetDecimal()));
    }

    [Fact]
    public async Task Scope_this_with_repeat_is_refused()
    {
        var group = await WeeklyThroughAsync(Now);
        var first = Assert.Single(await group.ExpensesAsync());

        var response = await group.Owner.UpdateExpenseAsync(group.Id, Id(first), "this", new { repeat = "monthly" });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Deleting_one_added_expense_keeps_the_recurring_expense_and_never_adds_it_again()
    {
        var group = await WeeklyThroughAsync(Now.AddDays(14));
        var second = ExpenseOn(await group.ExpensesAsync(), Day(2030, 1, 22));

        Assert.Equal(HttpStatusCode.NoContent, (await group.Owner.DeleteExpenseAsync(group.Id, Id(second))).StatusCode);
        await group.OpenAsync();

        Assert.Equal([Day(2030, 1, 15), Day(2030, 1, 29)], (await group.ExpensesAsync()).Select(DayOf).Order());

        _factory.Clock.Set(Now.AddDays(21));
        await group.OpenAsync();

        Assert.Equal(
            [Day(2030, 1, 15), Day(2030, 1, 29), Day(2030, 2, 5)],
            (await group.ExpensesAsync()).Select(DayOf).Order());
    }

    // Editing and deleting it and every one after it.

    [Fact]
    public async Task Editing_this_and_following_rewrites_the_later_expenses()
    {
        var group = await WeeklyThroughAsync(Now.AddDays(21));
        await _factory.DrainProcessedAsync();
        var second = ExpenseOn(await group.ExpensesAsync(), Day(2030, 1, 22));

        (await group.Owner.UpdateExpenseAsync(group.Id, Id(second), "following",
            new { amount = 30m, splitMode = "equal", splits = Splits(group, 15m) })).EnsureSuccessStatusCode();
        await WorkerHarness.WaitForProcessedAsync(_factory);

        var expenses = (await group.ExpensesAsync()).OrderBy(DayOf).ToList();
        Assert.Equal(
            [Day(2030, 1, 15), Day(2030, 1, 22), Day(2030, 1, 29), Day(2030, 2, 5)],
            expenses.Select(DayOf));
        Assert.Equal([20m, 30m, 30m, 30m], expenses.Select(e => e.GetProperty("amount").GetDecimal()));
        Assert.All(expenses, e => Assert.Equal(JsonValueKind.Number, e.GetProperty("recurringExpenseId").ValueKind));

        var summary = await group.Owner.ReadSummaryAsync(group.Id);
        Assert.Equal(55m, summary.AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task Editing_this_and_following_leaves_a_deleted_later_expense_deleted()
    {
        var group = await WeeklyThroughAsync(Now.AddDays(21));
        var expenses = await group.ExpensesAsync();
        (await group.Owner.DeleteExpenseAsync(group.Id, Id(ExpenseOn(expenses, Day(2030, 1, 29))))).EnsureSuccessStatusCode();
        var last = ExpenseOn(expenses, Day(2030, 2, 5));

        (await group.Owner.UpdateExpenseAsync(group.Id, Id(ExpenseOn(expenses, Day(2030, 1, 22))), "following",
            new { amount = 30m, splitMode = "equal", splits = Splits(group, 15m) })).EnsureSuccessStatusCode();
        await group.OpenAsync();

        var after = (await group.ExpensesAsync()).OrderBy(DayOf).ToList();
        Assert.Equal([Day(2030, 1, 15), Day(2030, 1, 22), Day(2030, 2, 5)], after.Select(DayOf));
        Assert.Equal([20m, 30m, 30m], after.Select(e => e.GetProperty("amount").GetDecimal()));
        // Rewritten where it stands, not deleted and added again.
        Assert.Equal(Id(last), Id(after[2]));
    }

    [Fact]
    public async Task Moving_the_date_this_and_following_moves_the_later_expenses_onto_the_new_day()
    {
        var start = new DateTimeOffset(2030, 1, 1, 12, 0, 0, TimeSpan.Zero);
        _factory.Clock.Set(start);
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("monthly", start.UtcDateTime);
        _factory.Clock.Set(new DateTimeOffset(2030, 3, 10, 12, 0, 0, TimeSpan.Zero));
        await group.OpenAsync();
        var february = ExpenseOn(await group.ExpensesAsync(), Day(2030, 2, 1));

        (await group.Owner.UpdateExpenseAsync(group.Id, Id(february), "following",
            new { date = new DateTime(2030, 2, 5, 0, 0, 0, DateTimeKind.Utc) })).EnsureSuccessStatusCode();

        Assert.Equal(
            [Day(2030, 1, 1), Day(2030, 2, 5), Day(2030, 3, 5)],
            (await group.ExpensesAsync()).Select(DayOf).Order());
    }

    [Fact]
    public async Task Changing_the_frequency_this_and_following_carries_forward()
    {
        var group = await WeeklyThroughAsync(Now.AddDays(21));
        var second = ExpenseOn(await group.ExpensesAsync(), Day(2030, 1, 22));

        var edited = await group.Owner.ReadJsonAsync(
            await group.Owner.UpdateExpenseAsync(group.Id, Id(second), "following", new { repeat = "monthly" }));

        Assert.Equal("monthly", edited.GetProperty("repeat").GetString());
        Assert.Equal([Day(2030, 1, 15), Day(2030, 1, 22)], (await group.ExpensesAsync()).Select(DayOf).Order());

        _factory.Clock.Set(new DateTimeOffset(2030, 2, 22, 12, 0, 0, TimeSpan.Zero));
        await group.OpenAsync();

        Assert.Equal(
            [Day(2030, 1, 15), Day(2030, 1, 22), Day(2030, 2, 22)],
            (await group.ExpensesAsync()).Select(DayOf).Order());
    }

    // A member who moved sends their new zone with a "this and following" edit, so "every
    // Tuesday" means Tuesday where they are now. Tokyo is ahead of UTC, so a local midnight
    // there is the afternoon before in UTC.
    [Fact]
    public async Task A_new_zone_this_and_following_moves_the_later_expenses_to_its_midnight()
    {
        var group = await WeeklyThroughAsync(Now.AddDays(14));
        var second = ExpenseOn(await group.ExpensesAsync(), Day(2030, 1, 22));

        (await group.Owner.UpdateExpenseAsync(group.Id, Id(second), "following",
            new { timeZone = "Asia/Tokyo" })).EnsureSuccessStatusCode();

        var third = Assert.Single(await group.ExpensesAsync(), e => Id(e) != Id(second) && DayOf(e) > Day(2030, 1, 22));
        Assert.Equal(new DateTime(2030, 1, 28, 15, 0, 0, DateTimeKind.Utc), third.GetProperty("date").GetDateTime());

        // Just past midnight on 5 February in Tokyo, still the 4th in UTC.
        _factory.Clock.Set(new DateTimeOffset(2030, 2, 4, 15, 1, 0, TimeSpan.Zero));
        await group.OpenAsync();

        var added = (await group.ExpensesAsync()).MaxBy(e => e.GetProperty("date").GetDateTime());
        Assert.Equal(new DateTime(2030, 2, 4, 15, 0, 0, DateTimeKind.Utc), added.GetProperty("date").GetDateTime());
    }

    // West of UTC, the stored instant of "the 1st" is the evening of the 31st locally. A zone
    // change keeps the day the expense was on and moves only its midnight; the app resends
    // the date it was given, so an unchanged date counts as not moved.
    [Fact]
    public async Task A_new_zone_west_of_utc_keeps_the_day_the_expense_was_on()
    {
        var start = new DateTimeOffset(2030, 1, 1, 12, 0, 0, TimeSpan.Zero);
        _factory.Clock.Set(start);
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("monthly", start.UtcDateTime);
        _factory.Clock.Set(new DateTimeOffset(2030, 3, 10, 12, 0, 0, TimeSpan.Zero));
        await group.OpenAsync();
        var february = ExpenseOn(await group.ExpensesAsync(), Day(2030, 2, 1));

        (await group.Owner.UpdateExpenseAsync(group.Id, Id(february), "following", new
        {
            date = february.GetProperty("date").GetDateTime(),
            timeZone = "America/Los_Angeles"
        })).EnsureSuccessStatusCode();

        // Midnight on 1 March in Los Angeles, eight hours behind UTC in winter.
        var march = Assert.Single(await group.ExpensesAsync(), e => e.GetProperty("date").GetDateTime() > new DateTime(2030, 2, 2));
        Assert.Equal(new DateTime(2030, 3, 1, 8, 0, 0, DateTimeKind.Utc), march.GetProperty("date").GetDateTime());

        // Just past midnight on 1 April there, under daylight saving.
        _factory.Clock.Set(new DateTimeOffset(2030, 4, 1, 7, 1, 0, TimeSpan.Zero));
        await group.OpenAsync();

        var added = (await group.ExpensesAsync()).MaxBy(e => e.GetProperty("date").GetDateTime());
        Assert.Equal(new DateTime(2030, 4, 1, 7, 0, 0, DateTimeKind.Utc), added.GetProperty("date").GetDateTime());
    }

    [Fact]
    public async Task A_zone_needs_scope_following_and_must_be_known()
    {
        var group = await WeeklyThroughAsync(Now);
        var first = Assert.Single(await group.ExpensesAsync());

        var withThis = await group.Owner.UpdateExpenseAsync(group.Id, Id(first), "this", new { timeZone = "Asia/Tokyo" });
        var unknown = await group.Owner.UpdateExpenseAsync(group.Id, Id(first), "following", new { timeZone = "Mars/Olympus" });

        await ErrorResponseAssertions.AssertErrorAsync(withThis, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(unknown, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Stopping_with_repeat_never_keeps_this_expense_and_leaves_everything_plain()
    {
        var group = await WeeklyThroughAsync(Now.AddDays(21));
        var second = ExpenseOn(await group.ExpensesAsync(), Day(2030, 1, 22));

        var edited = await group.Owner.ReadJsonAsync(
            await group.Owner.UpdateExpenseAsync(group.Id, Id(second), "following", new { repeat = "never" }));

        Assert.Equal(JsonValueKind.Null, edited.GetProperty("recurringExpenseId").ValueKind);
        Assert.Equal(JsonValueKind.Null, edited.GetProperty("repeat").ValueKind);

        _factory.Clock.Set(Now.AddDays(70));
        await group.OpenAsync();

        var expenses = await group.ExpensesAsync();
        Assert.Equal([Day(2030, 1, 15), Day(2030, 1, 22)], expenses.Select(DayOf).Order());
        Assert.All(expenses, e => Assert.Equal(JsonValueKind.Null, e.GetProperty("recurringExpenseId").ValueKind));
        Assert.False(await _factory.UseDbAsync(db => db.RecurringExpense.AnyAsync(r => r.GroupId == group.Id)));
    }

    [Fact]
    public async Task Stopping_one_still_catches_up_the_rest_of_the_group()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        var stopped = await group.CreateRecurringAsync("weekly", Now.UtcDateTime);
        await group.CreateRecurringAsync("monthly", Now.UtcDateTime);

        _factory.Clock.Set(Now.AddDays(31));
        (await group.Owner.UpdateExpenseAsync(group.Id, Id(stopped), "following", new { repeat = "never" }))
            .EnsureSuccessStatusCode();

        Assert.Contains(await group.ExpensesAsync(), e =>
            DayOf(e) == Day(2030, 2, 15) && e.GetProperty("repeat").GetString() == "monthly");
    }

    [Fact]
    public async Task Deleting_this_and_following_stops_the_recurring_expense_and_unlinks_the_earlier_ones()
    {
        var group = await WeeklyThroughAsync(Now.AddDays(21));
        var second = ExpenseOn(await group.ExpensesAsync(), Day(2030, 1, 22));

        Assert.Equal(HttpStatusCode.NoContent,
            (await group.Owner.DeleteExpenseAsync(group.Id, Id(second), "following")).StatusCode);

        _factory.Clock.Set(Now.AddDays(70));
        await group.OpenAsync();

        var remaining = Assert.Single(await group.ExpensesAsync());
        Assert.Equal(Day(2030, 1, 15), DayOf(remaining));
        Assert.Equal(JsonValueKind.Null, remaining.GetProperty("recurringExpenseId").ValueKind);
        Assert.False(await _factory.UseDbAsync(db => db.RecurringExpense.AnyAsync(r => r.GroupId == group.Id)));
    }

    [Fact]
    public async Task Following_and_repeat_on_a_plain_expense_are_refused()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        var plain = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        var editFollowing = await group.Owner.UpdateExpenseAsync(group.Id, plain, "following", new { amount = 20m });
        var repeat = await group.Owner.UpdateExpenseAsync(group.Id, plain, "following", new { repeat = "weekly" });
        var repeatThis = await group.Owner.UpdateExpenseAsync(group.Id, plain, new { repeat = "weekly" });
        var deleteFollowing = await group.Owner.DeleteExpenseAsync(group.Id, plain, "following");

        await ErrorResponseAssertions.AssertErrorAsync(editFollowing, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(repeat, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(repeatThis, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(deleteFollowing, HttpStatusCode.BadRequest);
        Assert.Single(await group.ExpensesAsync());
    }

    // Helpers.

    private static DateOnly Day(int year, int month, int day) => new(year, month, day);

    private static DateOnly DayOf(JsonElement expense) =>
        DateOnly.FromDateTime(expense.GetProperty("date").GetDateTime());

    /// A weekly rent from <see cref="Now"/>, with the group opened at <paramref name="through"/>.
    private async Task<GroupFixture> WeeklyThroughAsync(DateTimeOffset through)
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime);
        _factory.Clock.Set(through);
        await group.OpenAsync();
        return group;
    }

    private static int Id(JsonElement expense) => expense.GetProperty("id").GetInt32();

    private static JsonElement ExpenseOn(IEnumerable<JsonElement> expenses, DateOnly day) =>
        expenses.Single(e => DayOf(e) == day);

    private static object[] Splits(GroupFixture group, decimal share) =>
    [
        new { userId = group.OwnerId, amount = share },
        new { userId = group.GuestId, amount = share }
    ];
}
