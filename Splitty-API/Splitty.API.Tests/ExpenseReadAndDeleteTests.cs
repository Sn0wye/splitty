using System.Net;
using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;

namespace Splitty.API.Tests;

/// <summary>
/// Reading and deleting a single expense. Both are group sub-resources, so both answer a
/// non-member with 403 (invariant 3), and the delete leaves balances that no longer follow
/// from the surviving rows until a recomputation runs (invariant 1).
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class ExpenseReadAndDeleteTests(ApiFactory factory)
{
    private async Task<ApiClient> StrangerAsync()
    {
        var user = await ApiClient.Create(factory).SignInAsync(name: "Stranger");
        return ApiClient.Create(factory, user.Token);
    }

    [Fact]
    public async Task An_expense_can_be_read_one_at_a_time()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        var body = await group.Guest.ReadJsonAsync(await group.Guest.GetExpenseAsync(group.Id, expenseId));

        Assert.Equal(expenseId, body.GetProperty("id").GetInt32());
        Assert.Equal(20m, body.GetProperty("amount").GetDecimal());
        Assert.Equal(2, body.GetProperty("splits").GetArrayLength());
    }

    // Opening a group sends the group read, which adds due repeats (ADR 0006), alongside the
    // expense list. An expense written between the list's statements stands in for that
    // catch-up: the list must still read every expense together with its own splits.
    [Fact]
    public async Task An_expense_written_mid_list_does_not_strip_the_others_of_their_splits()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var earlier = await group.CreateExpenseAsync(amount: 20m, share: 10m, date: DateTime.UtcNow.AddDays(-2));
        var later = await group.CreateExpenseAsync(amount: 40m, share: 20m, date: DateTime.UtcNow.AddDays(-1));

        var interceptor = new CommandInterceptor();
        await using var host = factory.WithInterceptor(interceptor);
        var guest = ApiClient.Create(host, group.GuestToken);
        interceptor.Before(
            sql => sql.Contains("JOIN \"ExpenseSplit\"", StringComparison.Ordinal),
            () => group.CreateExpenseAsync(amount: 60m, share: 30m, date: DateTime.UtcNow));

        var list = await guest.ReadJsonAsync(await guest.GetExpensesAsync(group.Id));
        await interceptor.Fired;

        var expenses = list.EnumerateArray().ToList();
        Assert.Contains(expenses, e => e.GetProperty("id").GetInt32() == earlier);
        Assert.Contains(expenses, e => e.GetProperty("id").GetInt32() == later);
        foreach (var expense in expenses)
        {
            var splits = expense.GetProperty("splits").EnumerateArray().ToList();
            Assert.Equal(2, splits.Count);
            Assert.All(splits, split =>
                Assert.Equal(expense.GetProperty("id").GetInt32(), split.GetProperty("expenseId").GetInt32()));
        }
    }

    [Fact]
    public async Task Reading_an_expense_of_another_group_is_not_found()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var other = await GroupFixture.CreateAsync(factory);
        var expenseId = await other.CreateExpenseAsync(amount: 20m, share: 10m);

        // The caller is a member of the group in the path, so this is a lookup failure and
        // not an authorization one — the expense simply is not in that group.
        var response = await group.Owner.GetExpenseAsync(group.Id, expenseId);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task A_non_member_can_neither_read_nor_delete_an_expense()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);
        var stranger = await StrangerAsync();

        Assert.Equal(HttpStatusCode.Forbidden, (await stranger.GetExpenseAsync(group.Id, expenseId)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await stranger.DeleteExpenseAsync(group.Id, expenseId)).StatusCode);
    }

    [Fact]
    public async Task Deleting_an_expense_removes_it_and_the_debt_it_created()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        var response = await group.Guest.DeleteExpenseAsync(group.Id, expenseId);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        await factory.WaitForProcessedAsync();

        Assert.Equal(HttpStatusCode.NotFound, (await group.Guest.GetExpenseAsync(group.Id, expenseId)).StatusCode);
        Assert.Equal(0m, (await group.Guest.ReadSummaryAsync(group.Id)).AmountOwedBy(group.GuestId, group.OwnerId));
    }

    [Fact]
    public async Task Deleting_a_fully_settled_expense_reverses_the_debt()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();
        await group.SettleAsync(10m);
        await factory.WaitForProcessedAsync();

        var response = await group.Guest.DeleteExpenseAsync(group.Id, expenseId);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        await factory.WaitForProcessedAsync();

        var guestSummary = await group.Guest.ReadSummaryAsync(group.Id);
        var ownerSummary = await group.Owner.ReadSummaryAsync(group.Id);
        var guestBalance = guestSummary.AmountOwedBy(group.GuestId, group.OwnerId);
        var ownerBalance = ownerSummary.AmountOwedBy(group.OwnerId, group.GuestId);

        Assert.Equal(10m, guestBalance);
        Assert.Equal(-10m, ownerBalance);
        Assert.Equal(0m, guestBalance + ownerBalance);
    }

    [Fact]
    public async Task Deleting_an_expense_takes_its_splits_with_it()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        (await group.Owner.DeleteExpenseAsync(group.Id, expenseId)).EnsureSuccessStatusCode();

        Assert.Empty(await factory.UseDbAsync(db => db.ExpenseSplit
            .Where(s => s.ExpenseId == expenseId)
            .ToListAsync()));
    }

    /// <summary>
    /// The route refuses settlements outright rather than branching on <c>Type</c>, per
    /// docs/adr/0001-settlements-have-their-own-routes.md.
    /// </summary>
    [Fact]
    public async Task The_expense_delete_route_refuses_a_settlement()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();
        var settlementId = await group.SettleAsync(6m);

        var response = await group.Guest.DeleteExpenseAsync(group.Id, settlementId);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
        Assert.NotNull(await factory.UseDbAsync(db => db.Expense.FirstOrDefaultAsync(e => e.Id == settlementId)));
    }

    /// <summary>
    /// A settlement's splits are rebuilt from its amount and capped, neither of which the
    /// expense edit path does — so it refuses them too, and the cap has one home.
    /// </summary>
    [Fact]
    public async Task The_expense_edit_route_refuses_a_settlement()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();
        var settlementId = await group.SettleAsync(6m);

        var response = await group.Guest.UpdateExpenseAsync(group.Id, settlementId, new { amount = 999m });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);

        var amount = await factory.UseDbAsync(db => db.Expense
            .Where(e => e.Id == settlementId)
            .Select(e => e.Amount)
            .FirstAsync());
        Assert.Equal(6m, amount);
    }

    [Fact]
    public async Task Deleting_an_expense_twice_is_not_found_the_second_time()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        (await group.Owner.DeleteExpenseAsync(group.Id, expenseId)).EnsureSuccessStatusCode();
        var second = await group.Owner.DeleteExpenseAsync(group.Id, expenseId);

        await ErrorResponseAssertions.AssertErrorAsync(second, HttpStatusCode.NotFound);
    }
}
