using Microsoft.EntityFrameworkCore;

namespace Splitty.API.Tests;

/// <summary>
/// A rename is cosmetic. Each test runs a statement in the gap between the rename's read and
/// its write, standing in for the worker or another member, and asserts the rename did not
/// write back what it read.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class GroupRenameTests(ApiFactory factory)
{
    private static bool IsRename(string sql) =>
        sql.Contains("UPDATE \"Group\"", StringComparison.Ordinal) &&
        sql.Contains("\"Name\"", StringComparison.Ordinal);

    private static Task<HttpResponseMessage> CreateExpenseAsync(ApiClient owner, GroupFixture group) =>
        owner.CreateExpenseAsync(group.Id, new
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
        });

    [Fact]
    public async Task A_replay_that_clears_the_flag_mid_rename_leaves_the_group_settled()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        using var gate = new RecomputeGate(group.Id);
        var interceptor = new CommandInterceptor();
        await using var host = factory.WithGate(gate).WithInterceptor(interceptor);
        await host.DrainProcessedAsync();
        var owner = ApiClient.Create(host, group.OwnerToken);

        (await CreateExpenseAsync(owner, group)).EnsureSuccessStatusCode();
        await gate.WaitForEntryAsync();

        interceptor.Before(IsRename, async () =>
        {
            gate.Release();
            await host.WaitForProcessedAsync();
        });

        (await owner.UpdateGroupAsync(group.Id, new { name = "Renamed" })).EnsureSuccessStatusCode();
        await interceptor.Fired;

        Assert.False((await group.Owner.ReadSummaryAsync(group.Id)).BalancesPending);
        (await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 10m }))
            .EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
    }

    [Fact]
    public async Task A_write_that_marks_pending_mid_rename_stays_pending_until_its_replay_drains()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        using var gate = new RecomputeGate(group.Id);
        var interceptor = new CommandInterceptor();
        await using var host = factory.WithGate(gate).WithInterceptor(interceptor);
        await host.DrainProcessedAsync();
        var owner = ApiClient.Create(host, group.OwnerToken);

        interceptor.Before(IsRename, async () =>
        {
            (await CreateExpenseAsync(owner, group)).EnsureSuccessStatusCode();
            await gate.WaitForEntryAsync();
        });

        (await owner.UpdateGroupAsync(group.Id, new { description = "Redescribed" })).EnsureSuccessStatusCode();
        await interceptor.Fired;

        Assert.True((await group.Owner.ReadSummaryAsync(group.Id)).BalancesPending);

        gate.Release();
        await host.WaitForProcessedAsync();

        var summary = await group.Owner.ReadSummaryAsync(group.Id);
        Assert.False(summary.BalancesPending);
        Assert.Equal(10m, summary.AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task A_balance_changed_mid_rename_is_not_restored()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        var interceptor = new CommandInterceptor();
        await using var host = factory.WithInterceptor(interceptor);
        var owner = ApiClient.Create(host, group.OwnerToken);

        interceptor.Before(IsRename, () => factory.UseDbAsync(db => db.Balance
            .Where(b => b.GroupId == group.Id)
            .ExecuteUpdateAsync(setters => setters.SetProperty(b => b.Amount, b => b.Amount / 2))));

        (await owner.UpdateGroupAsync(group.Id, new { name = "Renamed" })).EnsureSuccessStatusCode();
        await interceptor.Fired;

        var owed = await factory.UseDbAsync(db => db.Balance
            .Where(b => b.GroupId == group.Id && b.UserId == group.OwnerId && b.PeerId == group.GuestId)
            .Select(b => b.Amount)
            .SingleAsync());
        Assert.Equal(5m, owed);
    }

    [Fact]
    public async Task A_rename_keeps_the_fields_it_was_not_given()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var body = await group.Owner.ReadJsonAsync(
            await group.Owner.UpdateGroupAsync(group.Id, new { name = "Renamed", description = "" }));

        Assert.Equal("Renamed", body.GetProperty("name").GetString());
        Assert.Equal("test", body.GetProperty("description").GetString());
    }

    [Fact]
    public async Task The_replay_writes_no_user_row()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        // A second replay updates the balance rows the first one inserted, which is the path
        // that hands tracked rows, and whatever they reach, back to the context.
        using var gate = new RecomputeGate(group.Id);
        var interceptor = new CommandInterceptor();
        await using var host = factory.WithGate(gate).WithInterceptor(interceptor);
        await host.DrainProcessedAsync();

        (await CreateExpenseAsync(ApiClient.Create(host, group.OwnerToken), group)).EnsureSuccessStatusCode();
        await gate.WaitForEntryAsync();
        interceptor.Clear();

        gate.Release();
        await host.WaitForProcessedAsync();

        Assert.Contains(interceptor.Commands, sql => sql.Contains("UPDATE \"Balance\"", StringComparison.Ordinal));
        Assert.DoesNotContain(interceptor.Commands, sql => sql.Contains("UPDATE \"User\"", StringComparison.Ordinal));
        Assert.Equal(20m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));
    }
}
