using System.Net;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace Splitty.API.Tests;

/// <summary>
/// A recurring expense may have an end: the last day an installment may be due. It adds no
/// day after it and then finishes by itself. The expenses it adds are numbered from the rows
/// that exist, and <c>GET /group/{groupId}/recurring</c> lists the group's active ones.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class InstallmentTests : IDisposable
{
    /// A Tuesday, at noon UTC.
    private static readonly DateTimeOffset Now = new(2030, 1, 15, 12, 0, 0, TimeSpan.Zero);

    private readonly ApiFactory _factory;

    public InstallmentTests(ApiFactory factory)
    {
        _factory = factory;
        _factory.Clock.Set(Now);
    }

    public void Dispose() => _factory.Clock.Reset();

    // Ending.

    [Fact]
    public async Task A_recurring_expense_with_an_end_adds_exactly_its_installments_across_a_catch_up()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime, endsOn: Day(2030, 1, 29));

        _factory.Clock.Set(Now.AddDays(35));
        await group.OpenAsync();

        var expenses = (await group.ExpensesAsync()).OrderBy(DayOf).ToList();
        Assert.Equal([Day(2030, 1, 15), Day(2030, 1, 22), Day(2030, 1, 29)], expenses.Select(DayOf));
        Assert.Equal([(1, 3), (2, 3), (3, 3)], expenses.Select(Installment));
    }

    [Fact]
    public async Task An_end_between_due_days_stops_after_the_last_day_before_it()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime, endsOn: Day(2030, 1, 25));

        _factory.Clock.Set(Now.AddDays(35));
        await group.OpenAsync();

        Assert.Equal([Day(2030, 1, 15), Day(2030, 1, 22)], (await group.ExpensesAsync()).Select(DayOf).Order());
    }

    // The app turns "after 4 times" into the due day of the 4th installment.
    [Fact]
    public async Task A_monthly_count_from_the_31st_lands_on_the_right_final_day()
    {
        var start = new DateTimeOffset(2030, 1, 31, 10, 0, 0, TimeSpan.Zero);
        _factory.Clock.Set(start);
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("monthly", start.UtcDateTime, endsOn: Day(2030, 4, 30));

        _factory.Clock.Set(new DateTimeOffset(2030, 8, 1, 10, 0, 0, TimeSpan.Zero));
        await group.OpenAsync();

        var expenses = (await group.ExpensesAsync()).OrderBy(DayOf).ToList();
        Assert.Equal(
            [Day(2030, 1, 31), Day(2030, 2, 28), Day(2030, 3, 31), Day(2030, 4, 30)],
            expenses.Select(DayOf));
        Assert.Equal((4, 4), Installment(expenses[^1]));
    }

    [Fact]
    public async Task The_total_counts_installments_not_due_yet()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        var first = await group.CreateRecurringAsync("monthly", Now.UtcDateTime, endsOn: Day(2030, 12, 15));

        Assert.Equal((1, 12), Installment(first));
        Assert.Equal("2030-12-15", first.GetProperty("endsOn").GetString());
    }

    [Fact]
    public async Task Expenses_without_an_end_have_no_installment()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        var recurring = await group.CreateRecurringAsync("monthly", Now.UtcDateTime);
        await group.CreateExpenseAsync(amount: 20m, share: 10m);

        Assert.Equal(JsonValueKind.Null, recurring.GetProperty("installment").ValueKind);
        Assert.All(await group.ExpensesAsync(),
            e => Assert.Equal(JsonValueKind.Null, e.GetProperty("installment").ValueKind));
    }

    [Fact]
    public async Task An_end_before_the_start_is_refused()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        var response = await group.Owner.CreateExpenseAsync(group.Id,
            group.RecurringBody("monthly", Now.UtcDateTime, endsOn: Day(2030, 1, 14)));

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
        Assert.Empty(await group.ExpensesAsync());
    }

    [Fact]
    public async Task An_end_on_an_expense_that_never_repeats_is_refused()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        var absent = await group.Owner.CreateExpenseAsync(group.Id,
            group.RecurringBody(null, Now.UtcDateTime, endsOn: Day(2030, 6, 1)));
        var never = await group.Owner.CreateExpenseAsync(group.Id,
            group.RecurringBody("never", Now.UtcDateTime, endsOn: Day(2030, 6, 1)));

        await ErrorResponseAssertions.AssertErrorAsync(absent, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(never, HttpStatusCode.BadRequest);
        Assert.Empty(await group.ExpensesAsync());
    }

    // Numbering.

    [Fact]
    public async Task Deleting_one_installment_on_its_own_lowers_both_numbers()
    {
        var group = await MonthlyTwelveOpenedInAprilAsync();
        var expenses = await group.ExpensesAsync();
        (await group.Owner.DeleteExpenseAsync(group.Id, Id(ExpenseOn(expenses, Day(2030, 2, 15))))).EnsureSuccessStatusCode();

        var april = ExpenseOn(await group.ExpensesAsync(), Day(2030, 4, 15));

        Assert.Equal((3, 11), Installment(april));
        Assert.Equal((3, 11), Installment(await group.Owner.ReadJsonAsync(await group.Owner.GetExpenseAsync(group.Id, Id(april)))));
    }

    [Fact]
    public async Task A_following_edit_of_the_amount_keeps_the_numbering()
    {
        var group = await MonthlyTwelveOpenedInAprilAsync();
        var march = ExpenseOn(await group.ExpensesAsync(), Day(2030, 3, 15));

        var edited = await group.Owner.ReadJsonAsync(await group.Owner.UpdateExpenseAsync(group.Id, Id(march), "following",
            new { amount = 30m, splitMode = "equal", splits = Splits(group, 15m) }));

        Assert.Equal((3, 12), Installment(edited));
        Assert.Equal(
            [(1, 12), (2, 12), (3, 12), (4, 12)],
            (await group.ExpensesAsync()).OrderBy(DayOf).Select(Installment));
    }

    // Changing the end with "this and following".

    [Fact]
    public async Task A_following_edit_can_shorten_the_end()
    {
        var group = await MonthlyTwelveOpenedInAprilAsync();
        var february = ExpenseOn(await group.ExpensesAsync(), Day(2030, 2, 15));

        (await group.Owner.UpdateExpenseAsync(group.Id, Id(february), "following",
            new { endsOn = Day(2030, 3, 15) })).EnsureSuccessStatusCode();

        _factory.Clock.Set(new DateTimeOffset(2030, 9, 1, 12, 0, 0, TimeSpan.Zero));
        await group.OpenAsync();

        var expenses = (await group.ExpensesAsync()).OrderBy(DayOf).ToList();
        Assert.Equal([Day(2030, 1, 15), Day(2030, 2, 15), Day(2030, 3, 15)], expenses.Select(DayOf));
        Assert.Equal([(1, 3), (2, 3), (3, 3)], expenses.Select(Installment));
    }

    [Fact]
    public async Task An_end_before_the_next_due_day_stops_after_what_was_added()
    {
        var group = await MonthlyTwelveOpenedInAprilAsync();
        var april = ExpenseOn(await group.ExpensesAsync(), Day(2030, 4, 15));

        (await group.Owner.UpdateExpenseAsync(group.Id, Id(april), "following",
            new { endsOn = Day(2030, 4, 20) })).EnsureSuccessStatusCode();

        _factory.Clock.Set(new DateTimeOffset(2030, 9, 1, 12, 0, 0, TimeSpan.Zero));
        await group.OpenAsync();

        Assert.Equal(4, (await group.ExpensesAsync()).Count);
        Assert.Empty((await RecurringAsync(group)).EnumerateArray());
    }

    [Fact]
    public async Task A_following_edit_can_add_an_end_to_one_that_had_none()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime);
        _factory.Clock.Set(Now.AddDays(7));
        await group.OpenAsync();
        var second = ExpenseOn(await group.ExpensesAsync(), Day(2030, 1, 22));

        var edited = await group.Owner.ReadJsonAsync(await group.Owner.UpdateExpenseAsync(group.Id, Id(second), "following",
            new { endsOn = Day(2030, 2, 5) }));

        Assert.Equal((2, 4), Installment(edited));

        _factory.Clock.Set(Now.AddDays(70));
        await group.OpenAsync();

        Assert.Equal(
            [Day(2030, 1, 15), Day(2030, 1, 22), Day(2030, 1, 29), Day(2030, 2, 5)],
            (await group.ExpensesAsync()).Select(DayOf).Order());
    }

    [Fact]
    public async Task A_following_edit_can_clear_the_end()
    {
        var group = await MonthlyTwelveOpenedInAprilAsync();
        var april = ExpenseOn(await group.ExpensesAsync(), Day(2030, 4, 15));

        var edited = await group.Owner.ReadJsonAsync(await group.Owner.UpdateExpenseAsync(group.Id, Id(april), "following",
            new { endsNever = true }));

        Assert.Equal(JsonValueKind.Null, edited.GetProperty("installment").ValueKind);
        Assert.Equal(JsonValueKind.Null, edited.GetProperty("endsOn").ValueKind);

        _factory.Clock.Set(new DateTimeOffset(2031, 3, 1, 12, 0, 0, TimeSpan.Zero));
        await group.OpenAsync();

        Assert.Contains(await group.ExpensesAsync(), e => DayOf(e) == Day(2031, 2, 15));
    }

    [Fact]
    public async Task An_edit_that_leaves_the_end_out_keeps_it()
    {
        var group = await MonthlyTwelveOpenedInAprilAsync();
        var march = ExpenseOn(await group.ExpensesAsync(), Day(2030, 3, 15));

        var edited = await group.Owner.ReadJsonAsync(await group.Owner.UpdateExpenseAsync(group.Id, Id(march), "following",
            new { repeat = "monthly" }));

        Assert.Equal((3, 12), Installment(edited));
    }

    [Fact]
    public async Task Changing_the_end_needs_scope_following_and_a_start_on_or_before_it()
    {
        var group = await MonthlyTwelveOpenedInAprilAsync();
        var march = ExpenseOn(await group.ExpensesAsync(), Day(2030, 3, 15));

        var endsOnThis = await group.Owner.UpdateExpenseAsync(group.Id, Id(march), "this", new { endsOn = Day(2030, 6, 15) });
        var neverThis = await group.Owner.UpdateExpenseAsync(group.Id, Id(march), "this", new { endsNever = true });
        var both = await group.Owner.UpdateExpenseAsync(group.Id, Id(march), "following",
            new { endsOn = Day(2030, 6, 15), endsNever = true });
        var beforeStart = await group.Owner.UpdateExpenseAsync(group.Id, Id(march), "following", new { endsOn = Day(2030, 3, 14) });
        var stopping = await group.Owner.UpdateExpenseAsync(group.Id, Id(march), "following",
            new { repeat = "never", endsOn = Day(2030, 6, 15) });

        await ErrorResponseAssertions.AssertErrorAsync(endsOnThis, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(neverThis, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(both, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(beforeStart, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(stopping, HttpStatusCode.BadRequest);
        Assert.Equal((3, 12), Installment(ExpenseOn(await group.ExpensesAsync(), Day(2030, 3, 15))));
    }

    // Listing the active ones.

    [Fact]
    public async Task The_recurring_list_shows_active_ones_with_their_progress()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        var fixedPlan = await group.CreateRecurringAsync("monthly", Now.UtcDateTime, endsOn: Day(2030, 12, 15));
        var open = await group.CreateRecurringAsync("weekly", Now.UtcDateTime);
        _factory.Clock.Set(Now.AddDays(10));
        await group.OpenAsync();

        var listed = (await RecurringAsync(group)).EnumerateArray().ToList();

        Assert.Equal(2, listed.Count);
        var plan = listed.Single(r => r.GetProperty("id").GetInt32() == fixedPlan.GetProperty("recurringExpenseId").GetInt32());
        Assert.Equal("Rent", plan.GetProperty("description").GetString());
        Assert.Equal(20m, plan.GetProperty("amount").GetDecimal());
        Assert.Equal("rent", plan.GetProperty("category").GetString());
        Assert.Equal(group.OwnerId, plan.GetProperty("paidBy").GetInt32());
        Assert.Equal("monthly", plan.GetProperty("frequency").GetString());
        Assert.Equal("2030-02-15", plan.GetProperty("nextDueOn").GetString());
        Assert.Equal("2030-12-15", plan.GetProperty("endsOn").GetString());
        Assert.Equal(1, plan.GetProperty("progress").GetProperty("added").GetInt32());
        Assert.Equal(12, plan.GetProperty("progress").GetProperty("total").GetInt32());

        var weekly = listed.Single(r => r.GetProperty("id").GetInt32() == open.GetProperty("recurringExpenseId").GetInt32());
        Assert.Equal("2030-01-29", weekly.GetProperty("nextDueOn").GetString());
        Assert.Equal(JsonValueKind.Null, weekly.GetProperty("endsOn").ValueKind);
        Assert.Equal(2, weekly.GetProperty("progress").GetProperty("added").GetInt32());
        Assert.Equal(JsonValueKind.Null, weekly.GetProperty("progress").GetProperty("total").ValueKind);
    }

    [Fact]
    public async Task The_recurring_list_drops_finished_and_stopped_ones()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime, endsOn: Day(2030, 1, 22));
        var stopped = await group.CreateRecurringAsync("weekly", Now.UtcDateTime);
        _factory.Clock.Set(Now.AddDays(14));
        await group.OpenAsync();
        (await group.Owner.UpdateExpenseAsync(group.Id, Id(stopped), "following", new { repeat = "never" }))
            .EnsureSuccessStatusCode();

        Assert.Empty((await RecurringAsync(group)).EnumerateArray());
        // Finished, not deleted: its expenses still read it for their numbers.
        Assert.True(await _factory.UseDbAsync(db => db.RecurringExpense.AnyAsync(r => r.GroupId == group.Id)));
    }

    [Fact]
    public async Task The_recurring_list_does_not_catch_up()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime);
        _factory.Clock.Set(Now.AddDays(14));

        var listed = Assert.Single((await RecurringAsync(group)).EnumerateArray());

        Assert.Equal(1, listed.GetProperty("progress").GetProperty("added").GetInt32());
        Assert.Single(await group.ExpensesAsync());
    }

    [Fact]
    public async Task The_recurring_list_refuses_non_members()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime);
        var outsider = await ApiClient.Create(_factory).SignInAsync(name: "Outsider");

        var response = await ApiClient.Create(_factory, outsider.Token).GetRecurringAsync(group.Id);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    // Helpers.

    private static DateOnly Day(int year, int month, int day) => new(year, month, day);

    private static DateOnly DayOf(JsonElement expense) =>
        DateOnly.FromDateTime(expense.GetProperty("date").GetDateTime());

    private static (int, int) Installment(JsonElement expense)
    {
        var installment = expense.GetProperty("installment");
        return (installment.GetProperty("number").GetInt32(), installment.GetProperty("total").GetInt32());
    }

    private static int Id(JsonElement expense) => expense.GetProperty("id").GetInt32();

    private static JsonElement ExpenseOn(IEnumerable<JsonElement> expenses, DateOnly day) =>
        expenses.Single(e => DayOf(e) == day);

    private static object[] Splits(GroupFixture group, decimal share) =>
    [
        new { userId = group.OwnerId, amount = share },
        new { userId = group.GuestId, amount = share }
    ];

    private static async Task<JsonElement> RecurringAsync(GroupFixture group) =>
        await group.Owner.ReadJsonAsync(await group.Owner.GetRecurringAsync(group.Id));

    /// A monthly rent in 12 installments from 15 January, opened on 20 April: four added.
    private async Task<GroupFixture> MonthlyTwelveOpenedInAprilAsync()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("monthly", Now.UtcDateTime, endsOn: Day(2030, 12, 15));
        _factory.Clock.Set(new DateTimeOffset(2030, 4, 20, 12, 0, 0, TimeSpan.Zero));
        await group.OpenAsync();
        return group;
    }
}
