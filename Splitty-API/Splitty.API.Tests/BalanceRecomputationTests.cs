using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Splitty.Domain.Entities;
using Splitty.Service;
using Splitty.Service.Interfaces;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class BalanceRecomputationTests(ApiFactory factory)
{
    [Fact]
    public async Task Editing_an_expense_amount_changes_the_balance_derived_from_it()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        var afterCreate = await group.Owner.ReadSummaryAsync(group.Id);
        Assert.Equal(10m, afterCreate.AmountOwedBy(group.OwnerId, group.GuestId));

        // The second recomputation in the same process is the one a captive scope breaks:
        // a context living for the process lifetime replays the amounts it first loaded.
        (await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new
        {
            amount = 50m,
            splits = new[]
            {
                new { userId = group.OwnerId, amount = 25m },
                new { userId = group.GuestId, amount = 25m }
            }
        })).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();

        var afterEdit = await group.Owner.ReadSummaryAsync(group.Id);
        Assert.Equal(25m, afterEdit.AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task Manual_refresh_returns_202_with_no_body()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        var response = await group.Owner.RequestSummaryRefreshAsync(group.Id);

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.Empty(await response.Content.ReadAsByteArrayAsync());

        await factory.WaitForProcessedAsync();
    }

    [Fact]
    public async Task Manual_refresh_updates_balances_once_the_worker_drains()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        // Write the expense straight to the database so the only thing that can produce a
        // balance for it is the recomputation the refresh request enqueues.
        await group.InsertExpenseDirectlyAsync(amount: 30m, share: 15m);

        Assert.Empty((await group.Owner.ReadSummaryAsync(group.Id)).Balances);

        (await group.Owner.RequestSummaryRefreshAsync(group.Id)).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();

        var summary = await group.Owner.ReadSummaryAsync(group.Id);
        Assert.Equal(15m, summary.AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task Summary_reports_balances_pending_until_the_worker_drains()
    {
        using var gate = new RecomputeGate();
        await using var gated = factory.WithGate(gate);

        var group = await GroupFixture.CreateAsync(gated);
        await gated.DrainProcessedAsync();

        await group.CreateExpenseAsync(amount: 20m, share: 10m);

        await gate.WaitForEntryAsync();
        Assert.True((await group.Owner.ReadSummaryAsync(group.Id)).BalancesPending);

        gate.Release();
        await gated.WaitForProcessedAsync();

        Assert.False((await group.Owner.ReadSummaryAsync(group.Id)).BalancesPending);
    }

    [Fact]
    public async Task Settling_up_marks_balances_pending()
    {
        using var gate = new RecomputeGate();
        await using var gated = factory.WithGate(gate);

        var group = await GroupFixture.CreateAsync(gated);
        await gated.DrainProcessedAsync();

        (await group.Owner.SettleUpAsync(group.Id, new { withUserId = group.GuestId, amount = 5m }))
            .EnsureSuccessStatusCode();

        await gate.WaitForEntryAsync();
        Assert.True((await group.Owner.ReadSummaryAsync(group.Id)).BalancesPending);

        gate.Release();
        await gated.WaitForProcessedAsync();
    }

    [Fact]
    public async Task A_failed_recomputation_is_logged_with_its_group_id_and_the_worker_keeps_serving()
    {
        var logs = new CapturingLoggerProvider();
        var poisonedGroup = new PoisonedGroup();

        await using var host = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.AddSingleton<ILoggerProvider>(logs);
                services.AddScoped<IBalanceService>(provider => new PoisonedBalanceService(
                    ActivatorUtilities.CreateInstance<BalanceService>(provider),
                    poisonedGroup));
            }));

        var poisoned = await GroupFixture.CreateAsync(host);
        var healthy = await GroupFixture.CreateAsync(host);
        poisonedGroup.Id = poisoned.Id;
        await host.DrainProcessedAsync();

        await poisoned.CreateExpenseAsync(amount: 20m, share: 10m);
        await host.WaitForProcessedAsync();

        Assert.Contains(logs.Errors, entry => entry.Contains(poisoned.Id.ToString()));

        // The host is still up: another endpoint serves, and another group still recomputes.
        Assert.Equal(HttpStatusCode.OK, (await healthy.Owner.GetGroupAsync(healthy.Id)).StatusCode);

        await healthy.CreateExpenseAsync(amount: 40m, share: 20m);
        await host.WaitForProcessedAsync();

        Assert.Equal(20m, (await healthy.Owner.ReadSummaryAsync(healthy.Id))
            .AmountOwedBy(healthy.OwnerId, healthy.GuestId));
    }

    [Fact]
    public async Task Concurrent_mutations_and_refreshes_leave_one_balance_row_per_ordered_pair()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        const int rounds = 8;

        for (var i = 0; i < rounds; i++)
        {
            await Task.WhenAll(
                group.CreateExpenseAsync(amount: 10m, share: 5m),
                group.Owner.RequestSummaryRefreshAsync(group.Id));
        }

        await factory.WaitForProcessedAsync(rounds * 2);

        var duplicated = await factory.UseDbAsync(db => db.Balance
            .Where(b => b.GroupId == group.Id)
            .GroupBy(b => new { b.UserId, b.PeerId })
            .Where(g => g.Count() > 1)
            .CountAsync());

        Assert.Equal(0, duplicated);
    }

    /// <summary>
    /// Skipping a unique index on the balance triple is only safe while the worker is the sole
    /// replayer. Nothing at the call site enforces that, so it is enforced here.
    /// </summary>
    [Fact]
    public void The_balance_replay_has_exactly_one_caller()
    {
        var callers = SolutionSource.FilesCalling("CalculateGroupBalances")
            .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}Splitty.API.Tests{Path.DirectorySeparatorChar}"))
            .Where(path => !path.EndsWith("IBalanceService.cs", StringComparison.Ordinal))
            .Where(path => !path.EndsWith("BalanceService.cs", StringComparison.Ordinal))
            .ToList();

        Assert.Equal(
            ["TransactionBackgroundService.cs"],
            callers.Select(Path.GetFileName).Order().ToList());
    }

    /// <summary>
    /// The group under test is chosen after the host is built, so the worker thread reads
    /// what the test thread wrote.
    /// </summary>
    private sealed class PoisonedGroup
    {
        private int _id;

        public int Id
        {
            get => Volatile.Read(ref _id);
            set => Volatile.Write(ref _id, value);
        }
    }

    private sealed class PoisonedBalanceService(IBalanceService inner, PoisonedGroup poisoned)
        : BalanceServiceDecorator(inner)
    {
        public override Task<List<Balance>> CalculateGroupBalances(int groupId) =>
            groupId == poisoned.Id
                ? throw new InvalidOperationException("recompute failed")
                : base.CalculateGroupBalances(groupId);
    }
}
