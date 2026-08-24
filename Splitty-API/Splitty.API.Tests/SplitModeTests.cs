using System.Net;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;

namespace Splitty.API.Tests;

/// <summary>
/// How the user said an expense was divided, stored alongside the division itself. The
/// mode is descriptive: nothing here re-derives an amount from a percentage, which is why
/// a percentage expense whose shares do not divide evenly is still accepted.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class SplitModeTests(ApiFactory factory)
{
    [Fact]
    public async Task A_mode_supplied_on_create_is_stored_and_returned()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m, splitMode: "custom");

        Assert.Equal(SplitMode.Custom, await StoredModeAsync(expenseId));

        var body = await group.Owner.ReadJsonAsync(await group.Owner.GetExpenseAsync(group.Id, expenseId));
        Assert.Equal("custom", body.GetProperty("splitMode").GetString());
    }

    [Fact]
    public async Task Create_rejects_a_request_that_omits_the_mode()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var response = await group.Owner.CreateExpenseAsync(group.Id, new
        {
            paidBy = group.OwnerId,
            amount = 20m,
            description = "Dinner",
            splits = new[]
            {
                new { userId = group.OwnerId, amount = 10m },
                new { userId = group.GuestId, amount = 10m }
            }
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        await ErrorResponseAssertions.ReadErrorAsync(response);
    }

    [Fact]
    public async Task A_percentage_expense_stores_a_percentage_on_every_split()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var expenseId = await CreatePercentageExpenseAsync(group, ownerPercentage: 70m, guestPercentage: 30m);

        var percentages = await StoredPercentagesAsync(expenseId);
        Assert.Equal([30m, 70m], percentages.Order());
    }

    /// <summary>
    /// The percentages say 70/30 while the amounts are split evenly. Nothing rejects the
    /// mismatch because the amounts are the only money truth — checking the two against
    /// each other would put the remainder cent on the server.
    /// </summary>
    [Fact]
    public async Task Percentages_are_not_checked_against_the_amounts()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var response = await group.Owner.CreateExpenseAsync(group.Id, Expense(
            group,
            amount: 20m,
            mode: "percentage",
            ownerSplit: new { userId = group.OwnerId, amount = 10m, percentage = 70m },
            guestSplit: new { userId = group.GuestId, amount = 10m, percentage = 30m }));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task A_percentage_expense_is_rejected_when_a_split_has_no_percentage()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var response = await group.Owner.CreateExpenseAsync(group.Id, Expense(
            group,
            amount: 20m,
            mode: "percentage",
            ownerSplit: new { userId = group.OwnerId, amount = 14m, percentage = 70m },
            guestSplit: new { userId = group.GuestId, amount = 6m }));

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task A_percentage_expense_is_rejected_when_the_percentages_do_not_sum_to_100()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var response = await group.Owner.CreateExpenseAsync(group.Id, Expense(
            group,
            amount: 20m,
            mode: "percentage",
            ownerSplit: new { userId = group.OwnerId, amount = 14m, percentage = 70m },
            guestSplit: new { userId = group.GuestId, amount = 6m, percentage = 40m }));

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Percentages_sent_with_a_non_percentage_mode_are_nulled_rather_than_rejected()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var response = await group.Owner.CreateExpenseAsync(group.Id, Expense(
            group,
            amount: 20m,
            mode: "equal",
            ownerSplit: new { userId = group.OwnerId, amount = 10m, percentage = 50m },
            guestSplit: new { userId = group.GuestId, amount = 10m, percentage = 50m }));

        response.EnsureSuccessStatusCode();
        var expenseId = (await group.Owner.ReadJsonAsync(response)).GetProperty("id").GetInt32();

        Assert.All(await StoredPercentagesAsync(expenseId), Assert.Null);
    }

    [Fact]
    public async Task Leaving_percentage_mode_nulls_the_percentages()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await CreatePercentageExpenseAsync(group, ownerPercentage: 70m, guestPercentage: 30m);

        (await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new
        {
            splitMode = "equal",
            splits = new[]
            {
                new { userId = group.OwnerId, amount = 10m, percentage = 70m },
                new { userId = group.GuestId, amount = 10m, percentage = 30m }
            }
        })).EnsureSuccessStatusCode();

        Assert.Equal(SplitMode.Equal, await StoredModeAsync(expenseId));
        Assert.All(await StoredPercentagesAsync(expenseId), Assert.Null);
    }

    /// <summary>
    /// A mode-only edit off percentage never resupplies the rows, so the percentages have
    /// to be cleared on the rows already stored or the expense keeps shares its mode no
    /// longer claims.
    /// </summary>
    [Fact]
    public async Task A_mode_only_edit_off_percentage_nulls_the_stored_percentages()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await CreatePercentageExpenseAsync(group, ownerPercentage: 70m, guestPercentage: 30m);

        (await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new { splitMode = "custom" }))
            .EnsureSuccessStatusCode();

        Assert.Equal(SplitMode.Custom, await StoredModeAsync(expenseId));
        Assert.All(await StoredPercentagesAsync(expenseId), Assert.Null);
    }

    [Fact]
    public async Task An_edit_sending_splits_without_a_mode_is_rejected()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        var response = await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new
        {
            splits = new[]
            {
                new { userId = group.OwnerId, amount = 10m },
                new { userId = group.GuestId, amount = 10m }
            }
        });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task An_edit_may_change_the_mode_alone()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        (await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new { splitMode = "custom" }))
            .EnsureSuccessStatusCode();

        Assert.Equal(SplitMode.Custom, await StoredModeAsync(expenseId));
    }

    /// <summary>
    /// A settlement is an Expense row with no split mode, which is what makes a null mode
    /// mean exactly one thing.
    /// </summary>
    [Fact]
    public async Task A_settlement_stores_no_mode()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        var settlementId = await group.SettleAsync(5m);

        Assert.Null(await StoredModeAsync(settlementId));
    }

    private Task<SplitMode?> StoredModeAsync(int expenseId) =>
        factory.UseDbAsync(db => db.Expense
            .Where(e => e.Id == expenseId)
            .Select(e => e.SplitMode)
            .FirstAsync());

    private Task<List<decimal?>> StoredPercentagesAsync(int expenseId) =>
        factory.UseDbAsync(db => db.ExpenseSplit
            .Where(s => s.ExpenseId == expenseId)
            .Select(s => s.Percentage)
            .ToListAsync());

    private async Task<int> CreatePercentageExpenseAsync(
        GroupFixture group,
        decimal ownerPercentage,
        decimal guestPercentage)
    {
        var response = await group.Owner.CreateExpenseAsync(group.Id, Expense(
            group,
            amount: 20m,
            mode: "percentage",
            ownerSplit: new { userId = group.OwnerId, amount = 10m, percentage = ownerPercentage },
            guestSplit: new { userId = group.GuestId, amount = 10m, percentage = guestPercentage }));
        response.EnsureSuccessStatusCode();

        return (await group.Owner.ReadJsonAsync(response)).GetProperty("id").GetInt32();
    }

    private static object Expense(
        GroupFixture group,
        decimal amount,
        string mode,
        object ownerSplit,
        object guestSplit) => new
    {
        paidBy = group.OwnerId,
        amount,
        description = "Dinner",
        splitMode = mode,
        splits = new[] { ownerSplit, guestSplit }
    };
}
