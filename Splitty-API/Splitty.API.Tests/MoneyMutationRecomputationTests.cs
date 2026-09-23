using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Splitty.DTO.Internal;
using Splitty.Service.Interfaces;

namespace Splitty.API.Tests;

/// <summary>
/// Every money write owns its request to recompute. Each accepted mutation leaves the group
/// pending until the worker drains, then serves debts that follow from the saved rows; a
/// rejected one leaves the group settled.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class MoneyMutationRecomputationTests(ApiFactory factory)
{
    /// The owner pays 20 split evenly and the guest settles 4, leaving the guest owing 6.
    private async Task<(GroupFixture Group, int ExpenseId, int SettlementId)> SettledAsync()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        var settlementId = await group.SettleAsync(4m);
        await factory.WaitForProcessedAsync();

        return (group, expenseId, settlementId);
    }

    /// <summary>
    /// Runs <paramref name="mutate"/> as the guest against a host whose worker is held open,
    /// asserting the group is pending while it is held and settled once it drains.
    /// </summary>
    private async Task MutateWhileGatedAsync(GroupFixture group, Func<ApiClient, Task<HttpResponseMessage>> mutate)
    {
        using var gate = new RecomputeGate();
        await using var gated = factory.WithGate(gate);
        await gated.DrainProcessedAsync();

        (await mutate(ApiClient.Create(gated, group.GuestToken))).EnsureSuccessStatusCode();

        await gate.WaitForEntryAsync();
        Assert.True((await group.Owner.ReadSummaryAsync(group.Id)).BalancesPending);

        gate.Release();
        await gated.WaitForProcessedAsync();

        Assert.False((await group.Owner.ReadSummaryAsync(group.Id)).BalancesPending);
    }

    [Fact]
    public async Task Editing_an_expense_is_pending_until_the_worker_drains()
    {
        var (group, expenseId, _) = await SettledAsync();

        await MutateWhileGatedAsync(group, guest => guest.UpdateExpenseAsync(group.Id, expenseId, new
        {
            amount = 30m,
            splitMode = "equal",
            splits = new[]
            {
                new { userId = group.OwnerId, amount = 15m },
                new { userId = group.GuestId, amount = 15m }
            }
        }));

        Assert.Equal(11m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task Deleting_an_expense_is_pending_until_the_worker_drains()
    {
        var (group, expenseId, _) = await SettledAsync();

        await MutateWhileGatedAsync(group, guest => guest.DeleteExpenseAsync(group.Id, expenseId));

        // Only the settlement is left, so the owner now owes back what the guest paid.
        Assert.Equal(-4m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task Editing_a_settlement_is_pending_until_the_worker_drains()
    {
        var (group, _, settlementId) = await SettledAsync();

        await MutateWhileGatedAsync(group, guest => guest.UpdateSettlementAsync(group.Id, settlementId, new { amount = 9m }));

        Assert.Equal(1m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task Deleting_a_settlement_is_pending_until_the_worker_drains()
    {
        var (group, _, settlementId) = await SettledAsync();

        await MutateWhileGatedAsync(group, guest => guest.DeleteSettlementAsync(group.Id, settlementId));

        Assert.Equal(10m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task An_expense_with_a_nonmember_split_is_rejected_without_a_recomputation()
    {
        var (group, _, _) = await SettledAsync();

        await AssertRejectedAsync(group, host => Guest(host, group).CreateExpenseAsync(group.Id,
            Dinner(group, (group.GuestId, 10m), (int.MaxValue, 10m))));
    }

    [Fact]
    public async Task An_expense_filed_as_a_payment_is_rejected_without_a_recomputation()
    {
        var (group, _, _) = await SettledAsync();

        await AssertRejectedAsync(group, host => Guest(host, group).CreateExpenseAsync(group.Id,
            Dinner(group, (group.OwnerId, 10m), (group.GuestId, 10m), category: "payment")));
    }

    [Fact]
    public async Task An_expense_edited_through_the_settlement_route_is_rejected_without_a_recomputation()
    {
        var (group, expenseId, _) = await SettledAsync();

        await AssertRejectedAsync(group, host =>
            Guest(host, group).UpdateSettlementAsync(group.Id, expenseId, new { amount = 1m }));
    }

    [Fact]
    public async Task A_settlement_deleted_through_the_expense_route_is_rejected_without_a_recomputation()
    {
        var (group, _, settlementId) = await SettledAsync();

        await AssertRejectedAsync(group, host => Guest(host, group).DeleteExpenseAsync(group.Id, settlementId));
    }

    [Fact]
    public async Task A_settlement_over_the_cap_is_rejected_without_a_recomputation()
    {
        var (group, _, _) = await SettledAsync();

        await AssertRejectedAsync(group, host =>
            Guest(host, group).SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 7m }));
    }

    [Fact]
    public async Task A_settlement_edited_over_the_cap_is_rejected_without_a_recomputation()
    {
        var (group, _, settlementId) = await SettledAsync();

        await AssertRejectedAsync(group, host =>
            Guest(host, group).UpdateSettlementAsync(group.Id, settlementId, new { amount = 11m }));
    }

    [Fact]
    public async Task A_nonmember_write_is_rejected_without_a_recomputation()
    {
        var (group, expenseId, settlementId) = await SettledAsync();

        await AssertRejectedAsync(group, async host =>
        {
            var outsider = ApiClient.Create(host, (await ApiClient.Create(host).SignInAsync(name: "Outsider")).Token);

            Assert.Equal(HttpStatusCode.Forbidden, (await outsider.DeleteExpenseAsync(group.Id, expenseId)).StatusCode);
            return await outsider.DeleteSettlementAsync(group.Id, settlementId);
        });
    }

    /// <summary>
    /// Sends <paramref name="write"/> against a host whose worker is held, so a recomputation
    /// the rejected write wrongly requested would still read as pending instead of racing the
    /// worker to clear it.
    /// </summary>
    private async Task AssertRejectedAsync(
        GroupFixture group,
        Func<WebApplicationFactory<Program>, Task<HttpResponseMessage>> write)
    {
        var before = await group.Owner.ReadSummaryAsync(group.Id);
        var expensesBefore = await ReadExpensesAsync(group);

        using var gate = new RecomputeGate();
        await using var gated = factory.WithGate(gate);
        await gated.DrainProcessedAsync();

        Assert.False((await write(gated)).IsSuccessStatusCode);

        var after = await group.Owner.ReadSummaryAsync(group.Id);
        Assert.False(after.BalancesPending);
        Assert.Equal(before.SimplifiedDebts, after.SimplifiedDebts);
        Assert.Equal(expensesBefore, await ReadExpensesAsync(group));
    }

    private static ApiClient Guest(WebApplicationFactory<Program> host, GroupFixture group) =>
        ApiClient.Create(host, group.GuestToken);

    private static object Dinner(GroupFixture group, (int UserId, decimal Amount) first, (int UserId, decimal Amount) second, string? category = null) => new
    {
        paidBy = group.GuestId,
        amount = first.Amount + second.Amount,
        description = "Dinner",
        category,
        splitMode = "equal",
        splits = new[]
        {
            new { userId = first.UserId, amount = first.Amount },
            new { userId = second.UserId, amount = second.Amount }
        }
    };

    private static async Task<string> ReadExpensesAsync(GroupFixture group) =>
        await (await group.Owner.GetExpensesAsync(group.Id)).Content.ReadAsStringAsync();

    /// <summary>
    /// The request to recompute belongs to the mutation, not to the route in front of it, so
    /// a caller that is not the controller still leaves the group consistent.
    /// </summary>
    [Fact]
    public async Task Money_mutations_request_recomputation_without_the_controller()
    {
        var (group, _, _) = await SettledAsync();

        await using (var scope = factory.Services.CreateAsyncScope())
        {
            await scope.ServiceProvider.GetRequiredService<IExpenseService>().CreateAsync(new CreateExpenseDTO
            {
                Amount = 8m,
                Description = "Taxi",
                GroupId = group.Id,
                PaidBy = group.OwnerId,
                SplitMode = Domain.Entities.SplitMode.Equal,
                ExpenseSplits =
                [
                    new ExpenseSplitDTO { UserId = group.OwnerId, Amount = 4m },
                    new ExpenseSplitDTO { UserId = group.GuestId, Amount = 4m }
                ]
            }, group.OwnerId);
        }

        // The timed wait, so a missing request fails instead of hanging.
        await WorkerHarness.WaitForProcessedAsync(factory);
        Assert.Equal(10m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));

        await using (var scope = factory.Services.CreateAsyncScope())
        {
            await scope.ServiceProvider.GetRequiredService<IBalanceService>()
                .SettleUp(group.Id, group.GuestId, group.OwnerId, 10m, null);
        }

        // The timed wait, so a missing request fails instead of hanging.
        await WorkerHarness.WaitForProcessedAsync(factory);
        Assert.Empty((await group.Owner.ReadSummaryAsync(group.Id)).SimplifiedDebts);
    }
}
