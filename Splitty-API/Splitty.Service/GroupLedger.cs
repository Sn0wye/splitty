using System.Threading.Channels;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Splitty.Infrastructure;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

/// <summary>
/// Owns deriving balances from money rows, and the pending-generation protocol that says
/// when the derived rows are current. The whole protocol:
///
/// <list type="number">
/// <item>A request marks the group pending and bumps its generation in one statement, then
/// queues a message carrying the new generation. Marking first matters: queueing first would
/// let the worker clear a flag this request has not set yet, leaving the group pending
/// forever.</item>
/// <item>The worker hands each message to <see cref="ProcessAsync"/>. A message whose
/// generation is behind the group's was superseded by a newer write whose own message is
/// already queued, so it is skipped — a burst of writes costs the replay already running plus
/// one.</item>
/// <item>Otherwise the replay reads the rows (every write up to that generation has saved),
/// then writes balances, simplified debts and the clear in one transaction. The clear matches
/// only the message's generation, so a write landing mid-replay keeps the group pending for
/// its own message.</item>
/// <item>Groups still pending when the API stopped are re-requested on start.</item>
/// </list>
///
/// The replay is internal to this assembly and reached only through here, which is what keeps
/// it single-caller (invariant 4) without a unique index on the balance triple.
/// </summary>
internal sealed class GroupLedger(
    ApplicationDbContext context,
    LedgerQueue queue,
    IGroupReplay replay
) : IGroupLedger
{
    public async Task RequestRecomputationAsync(int groupId, CancellationToken cancellationToken = default)
    {
        var generation = await MarkPendingAsync(groupId, cancellationToken);

        // A deleted group has nothing left to derive.
        if (generation is null) return;

        await queue.Writer.WriteAsync(new LedgerRequest(groupId, generation.Value), cancellationToken);
    }

    public async Task<LedgerRead<T>> ReadAsync<T>(int groupId, Func<Task<T>> read)
    {
        var pending = await IsPendingAsync(groupId);
        return new LedgerRead<T>(await read(), pending);
    }

    public async Task<decimal> SettlementCapAsync(int groupId, int payerId, int payeeId, decimal excluding = 0m)
    {
        if (await IsPendingAsync(groupId)) return 0m;

        var balances = await context.Balance.AsNoTracking()
            .Where(b => b.GroupId == groupId)
            .Select(b => new PairwiseBalance<int>(b.UserId, b.PeerId, b.Amount))
            .ToListAsync();

        return LedgerCore.Cap(LedgerCore.Nets(balances), payerId, payeeId, excluding);
    }

    public async Task ProcessAsync(LedgerRequest request, CancellationToken cancellationToken = default)
    {
        var current = await context.Group
            .Where(g => g.Id == request.GroupId)
            .Select(g => (int?)g.BalancesPendingGeneration)
            .FirstOrDefaultAsync(cancellationToken);

        // Superseded, or the group is gone.
        if (current != request.Generation) return;

        await replay.ReplayAsync(request.GroupId, request.Generation, cancellationToken);
    }

    /// <summary>Re-requests every group left pending, by a stop mid-replay or a migration backfill.</summary>
    public async Task RequeuePendingAsync(CancellationToken cancellationToken)
    {
        var pending = await context.Group
            .Where(g => g.BalancesPending)
            .Select(g => g.Id)
            .ToListAsync(cancellationToken);

        foreach (var groupId in pending)
            await RequestRecomputationAsync(groupId, cancellationToken);
    }

    // One statement, so the generation returned is the one this request produced even when
    // requests for the group race. Written in the database: a Group already tracked in this
    // scope keeps its old values, so callers must not save one back after requesting.
    private async Task<int?> MarkPendingAsync(int groupId, CancellationToken cancellationToken)
    {
        var generations = await context.Database.SqlQuery<int>($"""
            UPDATE "Group"
            SET "BalancesPending" = TRUE,
                "BalancesPendingGeneration" = "BalancesPendingGeneration" + 1
            WHERE "Id" = {groupId}
            RETURNING "BalancesPendingGeneration" AS "Value"
            """).ToListAsync(cancellationToken);

        return generations.Count == 0 ? null : generations[0];
    }

    private Task<bool> IsPendingAsync(int groupId) =>
        context.Group
            .Where(g => g.Id == groupId)
            .Select(g => g.BalancesPending)
            .FirstOrDefaultAsync();
}

/// <summary>
/// Requests queued for the worker. The writer stays in this assembly; the worker gets only
/// the reader.
/// </summary>
internal sealed class LedgerQueue
{
    private readonly Channel<LedgerRequest> _channel = Channel.CreateUnbounded<LedgerRequest>(
        new UnboundedChannelOptions
        {
            SingleReader = true,
            AllowSynchronousContinuations = false
        });

    public ChannelReader<LedgerRequest> Reader => _channel.Reader;
    public ChannelWriter<LedgerRequest> Writer => _channel.Writer;
}

/// <summary>
/// The ledger's hosted start. It runs after migrations, which are applied before the host
/// starts, so backfilled pending flags are picked up too.
/// </summary>
internal sealed class GroupLedgerRecovery(IServiceScopeFactory serviceScopeFactory) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        using var scope = serviceScopeFactory.CreateScope();
        await scope.ServiceProvider.GetRequiredService<GroupLedger>().RequeuePendingAsync(cancellationToken);
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}

public static class GroupLedgerServiceCollectionExtensions
{
    /// <summary>
    /// Registers the ledger, its queue and its startup recovery. The worker that drains the
    /// queue reads <see cref="ChannelReader{T}"/> of <see cref="LedgerRequest"/>.
    /// </summary>
    public static IServiceCollection AddGroupLedger(this IServiceCollection services)
    {
        services.AddSingleton<LedgerQueue>();
        services.AddSingleton(provider => provider.GetRequiredService<LedgerQueue>().Reader);
        services.AddScoped<IGroupReplay, GroupReplay>();
        services.AddScoped<GroupLedger>();
        services.AddScoped<IGroupLedger>(provider => provider.GetRequiredService<GroupLedger>());
        services.AddHostedService<GroupLedgerRecovery>();
        return services;
    }
}
