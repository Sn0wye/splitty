using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Splitty.Service;

namespace Splitty.API.Tests;

/// <summary>
/// The pending-generation protocol as a client and the database see it: how many replays a
/// burst costs, when settling opens again, and that the derived rows agree once drained.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class GroupLedgerTests(ApiFactory factory)
{
    private const int BurstSize = 3;

    [Fact]
    public async Task A_burst_of_writes_behind_a_held_replay_costs_one_further_replay()
    {
        var group = await SettledGroupAsync();
        using var gate = new RecomputeGate(group.Id);
        await using var gated = factory.WithGate(gate);
        var owner = ApiClient.Create(gated, group.OwnerToken);

        await HoldReplayThenBurstAsync(gated, gate, owner, group);

        gate.Release();
        await gated.WaitForProcessedAsync(1 + BurstSize);

        Assert.Equal(2, gate.Entries);
        var summary = await owner.ReadSummaryAsync(group.Id);
        Assert.False(summary.BalancesPending);
        Assert.Equal(10m * (2 + BurstSize), summary.AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task A_superseded_request_signals_processed_without_replaying()
    {
        var group = await SettledGroupAsync();
        using var gate = new RecomputeGate(group.Id);
        await using var gated = factory.WithGate(gate);
        var owner = ApiClient.Create(gated, group.OwnerToken);

        await HoldReplayThenBurstAsync(gated, gate, owner, group);
        gate.Release(1);

        // The held replay plus every superseded request completes while the last one is held.
        await gate.WaitForEntryAsync(2);
        await gated.WaitForProcessedAsync(BurstSize);
        Assert.Equal(2, gate.Entries);

        gate.Release(2);
        await gated.WaitForProcessedAsync();
    }

    [Fact]
    public async Task Settlement_is_refused_until_the_last_replay_finishes_and_accepted_right_after()
    {
        var group = await SettledGroupAsync();
        using var gate = new RecomputeGate(group.Id);
        await using var gated = factory.WithGate(gate);
        var owner = ApiClient.Create(gated, group.OwnerToken);
        var guest = ApiClient.Create(gated, group.GuestToken);

        await HoldReplayThenBurstAsync(gated, gate, owner, group);
        gate.Release(1);
        await gate.WaitForEntryAsync(2);

        Assert.True((await guest.ReadSummaryAsync(group.Id)).BalancesPending);
        await ErrorResponseAssertions.AssertErrorAsync(
            await guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 1m }),
            HttpStatusCode.BadRequest);

        // Releases the settlement's own replay too.
        gate.Release();
        await gated.WaitForProcessedAsync(1 + BurstSize);

        (await guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 1m }))
            .EnsureSuccessStatusCode();
        await gated.WaitForProcessedAsync();
    }

    [Fact]
    public async Task Balances_and_simplified_debts_agree_after_a_drain()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var third = await ApiClient.Create(factory).SignInAsync(name: "Third");
        (await ApiClient.Create(factory, third.Token).AcceptInviteAsync(await group.Owner.CreateInviteAsync(group.Id)))
            .EnsureSuccessStatusCode();
        await factory.DrainProcessedAsync();

        // Concurrent writes from different payers, so replays and requests interleave.
        await Task.WhenAll(
            group.CreateExpenseAsync(amount: 30m, share: 15m),
            Expense(group, payer: third.Id, participant: group.GuestId, amount: 12.5m),
            Expense(group, payer: group.GuestId, participant: group.OwnerId, amount: 7.25m),
            Expense(group, payer: third.Id, participant: group.OwnerId, amount: 4m));
        await factory.WaitForProcessedAsync(4);

        Assert.False((await group.Owner.ReadSummaryAsync(group.Id)).BalancesPending);

        var (balances, stored) = await factory.UseDbAsync(async db => (
            await db.Balance.Where(b => b.GroupId == group.Id)
                .Select(b => new PairwiseBalance<int>(b.UserId, b.PeerId, b.Amount)).ToListAsync(),
            await db.SimplifiedDebt.Where(d => d.GroupId == group.Id)
                .OrderBy(d => d.FromUserId).ThenBy(d => d.ToUserId)
                .Select(d => new SimplifiedPayment<int>(d.FromUserId, d.ToUserId, d.Amount)).ToListAsync()));

        var expected = LedgerCore.Simplify(LedgerCore.Nets(balances))
            .OrderBy(d => d.From).ThenBy(d => d.To).ToList();
        Assert.NotEmpty(expected);
        Assert.Equal(expected, stored);
    }

    /// The owner has paid 20 split evenly and it has been replayed: the guest owes 10.
    private async Task<GroupFixture> SettledGroupAsync()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();
        return group;
    }

    /// <summary>
    /// One write whose replay is held open, then <see cref="BurstSize"/> more queued behind it,
    /// each adding 10 to what the guest owes. Leaves nothing but this group's work unsignalled.
    /// </summary>
    private static async Task HoldReplayThenBurstAsync(
        WebApplicationFactory<Program> gated,
        RecomputeGate gate,
        ApiClient owner,
        GroupFixture group)
    {
        (await owner.CreateExpenseAsync(group.Id, Dinner(group))).EnsureSuccessStatusCode();
        await gate.WaitForEntryAsync(1);

        for (var i = 0; i < BurstSize; i++)
            (await owner.CreateExpenseAsync(group.Id, Dinner(group))).EnsureSuccessStatusCode();

        // Groups recovered at startup queue ahead of this group's first request, so they are
        // done by now; dropping their completions leaves only this group's to count.
        await gated.DrainProcessedAsync();
    }

    private static object Dinner(GroupFixture group) => new
    {
        paidBy = group.OwnerId,
        amount = 20m,
        description = "Dinner",
        splitMode = "equal",
        splits = new[]
        {
            new { userId = group.OwnerId, amount = 10m },
            new { userId = group.GuestId, amount = 10m }
        }
    };

    private static async Task Expense(GroupFixture group, int payer, int participant, decimal amount) =>
        (await group.Owner.CreateExpenseAsync(group.Id, new
        {
            paidBy = payer,
            amount,
            description = "Share",
            splitMode = "custom",
            splits = new[] { new { userId = participant, amount } }
        })).EnsureSuccessStatusCode();
}
