using System.Net;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace Splitty.API.Tests;

/// <summary>
/// The date the user says an expense happened on, which is not the audit timestamp. Rows
/// without one — everything written before the column existed — read as <c>CreatedAt</c>.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class ExpenseDateTests(ApiFactory factory)
{
    private static readonly DateTime March = new(2026, 3, 1, 12, 0, 0, DateTimeKind.Utc);

    private Task<DateTime?> StoredDateAsync(int expenseId) =>
        factory.UseDbAsync(db => db.Expense.Where(e => e.Id == expenseId).Select(e => e.Date).FirstAsync());

    [Fact]
    public async Task A_date_supplied_on_create_is_stored_and_returned()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m, date: March);

        Assert.Equal(March, await StoredDateAsync(expenseId));

        var body = await group.Guest.ReadJsonAsync(await group.Guest.GetExpenseAsync(group.Id, expenseId));
        Assert.Equal(March, body.GetProperty("date").GetDateTime());
    }

    [Fact]
    public async Task An_omitted_date_is_left_null_rather_than_guessed()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        Assert.Null(await StoredDateAsync(expenseId));
    }

    [Fact]
    public async Task A_future_date_is_accepted()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var future = DateTime.UtcNow.AddYears(1);

        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m, date: future);

        Assert.Equal(future, await StoredDateAsync(expenseId));
    }

    [Fact]
    public async Task A_date_can_be_changed_by_an_update()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m, date: March);
        var moved = March.AddDays(9);

        (await group.Guest.UpdateExpenseAsync(group.Id, expenseId, new { date = moved }))
            .EnsureSuccessStatusCode();

        Assert.Equal(moved, await StoredDateAsync(expenseId));
    }

    [Fact]
    public async Task An_update_that_omits_the_date_leaves_it_alone()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m, date: March);

        (await group.Guest.UpdateExpenseAsync(group.Id, expenseId, new { description = "Lunch" }))
            .EnsureSuccessStatusCode();

        Assert.Equal(March, await StoredDateAsync(expenseId));
    }

    /// <summary>
    /// <c>CreatedAt</c> is the audit timestamp and stays server-set: a client that supplies
    /// one is writing to a field the request shape does not have.
    /// </summary>
    [Fact]
    public async Task A_client_supplied_created_at_is_ignored()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var before = DateTime.UtcNow.AddSeconds(-5);

        var response = await group.Owner.CreateExpenseAsync(group.Id, new
        {
            paidBy = group.OwnerId,
            amount = 20m,
            description = "Dinner",
            createdAt = new DateTime(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc),
            splits = new[]
            {
                new { userId = group.OwnerId, amount = 10m },
                new { userId = group.GuestId, amount = 10m }
            }
        });

        var body = await group.Owner.ReadJsonAsync(response);
        Assert.True(body.GetProperty("createdAt").GetDateTime() >= before);
    }

    /// <summary>
    /// Ordering keys off the user's date where there is one and the audit timestamp where
    /// there is not, so a backdated expense sorts under its date and not its insert order.
    /// </summary>
    [Fact]
    public async Task The_list_is_ordered_newest_first_by_date_falling_back_to_created_at()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var backdated = await group.CreateExpenseAsync(amount: 20m, share: 10m, date: March);
        var undated = await group.CreateExpenseAsync(amount: 20m, share: 10m);
        var recent = await group.CreateExpenseAsync(amount: 20m, share: 10m, date: DateTime.UtcNow.AddDays(1));

        var body = await group.Guest.ReadJsonAsync(await group.Guest.GetExpensesAsync(group.Id));
        var ids = body.EnumerateArray().Select(e => e.GetProperty("id").GetInt32()).ToList();

        Assert.Equal(new[] { recent, undated, backdated }, ids);
    }
}
