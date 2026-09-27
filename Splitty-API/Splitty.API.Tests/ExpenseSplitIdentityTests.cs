namespace Splitty.API.Tests;

/// <summary>
/// The server owns split identity. An edit that sends splits replaces the expense's rows, so
/// a split id in the request can neither move another expense's row nor refuse a harmless
/// payload that echoes the rows the expense already has.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class ExpenseSplitIdentityTests(ApiFactory factory)
{
    [Fact]
    public async Task An_edit_cannot_move_a_split_out_of_another_groups_expense()
    {
        var victim = await GroupFixture.CreateAsync(factory);
        var attacker = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        var victimExpenseId = await victim.CreateExpenseAsync(amount: 20m, share: 10m);
        var attackerExpenseId = await attacker.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync(2);

        var victimSplitsBefore = await ReadSplitsAsync(victim, victimExpenseId);
        var victimSummaryBefore = await victim.Owner.ReadSummaryAsync(victim.Id);
        var stolenIds = victimSplitsBefore.Select(s => s.Id).ToArray();

        var response = await attacker.Owner.UpdateExpenseAsync(attacker.Id, attackerExpenseId, new
        {
            splitMode = "equal",
            splits = new[]
            {
                new { id = stolenIds[0], userId = attacker.OwnerId, amount = 10m },
                new { id = stolenIds[1], userId = attacker.GuestId, amount = 10m }
            }
        });

        if (response.IsSuccessStatusCode)
        {
            await factory.WaitForProcessedAsync();
        }

        Assert.Equal(victimSplitsBefore, await ReadSplitsAsync(victim, victimExpenseId));

        var victimSummaryAfter = await victim.Owner.ReadSummaryAsync(victim.Id);
        Assert.False(victimSummaryAfter.BalancesPending);
        Assert.Equal(victimSummaryBefore.SimplifiedDebts, victimSummaryAfter.SimplifiedDebts);
    }

    [Fact]
    public async Task An_edit_that_echoes_its_own_split_ids_replaces_the_splits()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        var ownIds = (await ReadSplitsAsync(group, expenseId)).Select(s => s.Id).ToArray();

        var response = await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new
        {
            amount = 30m,
            splitMode = "equal",
            splits = new[]
            {
                new { id = ownIds[0], userId = group.OwnerId, amount = 15m },
                new { id = ownIds[1], userId = group.GuestId, amount = 15m }
            }
        });
        response.EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();

        var splits = await ReadSplitsAsync(group, expenseId);
        Assert.Equal(
            [(group.OwnerId, 15m), (group.GuestId, 15m)],
            splits.Select(s => (s.UserId, s.Amount)).OrderBy(s => s.UserId == group.GuestId));
        Assert.Equal(15m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));
    }

    private static async Task<List<SplitRow>> ReadSplitsAsync(GroupFixture group, int expenseId)
    {
        var body = await group.Owner.ReadJsonAsync(await group.Owner.GetExpenseAsync(group.Id, expenseId));

        return body.GetProperty("splits")
            .EnumerateArray()
            .Select(s => new SplitRow(
                s.GetProperty("id").GetInt32(),
                s.GetProperty("userId").GetInt32(),
                s.GetProperty("amount").GetDecimal()))
            .OrderBy(s => s.Id)
            .ToList();
    }

    private readonly record struct SplitRow(int Id, int UserId, decimal Amount);
}
