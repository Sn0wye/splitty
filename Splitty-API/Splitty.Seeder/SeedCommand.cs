using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Splitty.Background;
using Splitty.Infrastructure;

namespace Splitty.Seeder;

/// <summary>
/// What a seeded group looked like when the command gave up or finished.
/// </summary>
/// <param name="GroupIds">The groups written, in seed order.</param>
/// <param name="Drained">
/// True once every seeded group's balances have been recomputed. False means the wait
/// timed out with groups still pending, which the command reports as a failure: a seed
/// that half-finished leaves the client greying numbers that will never change.
/// </param>
public sealed record SeedOutcome(IReadOnlyList<int> GroupIds, bool Drained);

/// <summary>
/// `dotnet run --project Splitty-API/Splitty.API seed`.
///
/// The command starts the host rather than seeding and returning, because the recomputation
/// it requests is performed by a hosted service. Enqueueing without a running worker would
/// mark every group pending and then drop the messages on exit, which is worse than seeding
/// nothing at all.
/// </summary>
public static class SeedCommand
{
    private static readonly TimeSpan DefaultDrainTimeout = TimeSpan.FromSeconds(60);

    public static async Task<int> RunAsync(IHost host, CancellationToken cancellationToken = default)
    {
        var logger = host.Services.GetRequiredService<ILoggerFactory>().CreateLogger(nameof(SeedCommand));

        await host.StartAsync(cancellationToken);

        try
        {
            var outcome = await SeedAndDrainAsync(host.Services, DefaultDrainTimeout, cancellationToken);

            if (!outcome.Drained)
            {
                logger.LogError(
                    "Seeded {Count} groups but their balances were not recomputed within {Seconds}s.",
                    outcome.GroupIds.Count,
                    DefaultDrainTimeout.TotalSeconds);

                return 1;
            }

            logger.LogInformation(
                "Seeded {Count} groups with balances computed. Sign in with {Email}.",
                outcome.GroupIds.Count,
                DatabaseSeeder.PrimaryUserEmail);

            return 0;
        }
        finally
        {
            await host.StopAsync(cancellationToken);
        }
    }

    /// <summary>
    /// Seeds, then waits until no seeded group is pending. The wait is driven by the
    /// worker's own completion signal rather than by polling on a timer, and is bounded:
    /// the caller gets an answer either way instead of hanging.
    /// </summary>
    public static async Task<SeedOutcome> SeedAndDrainAsync(
        IServiceProvider services,
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        IReadOnlyList<int> groupIds;

        using (var scope = services.CreateScope())
        {
            var seeder = ActivatorUtilities.CreateInstance<DatabaseSeeder>(scope.ServiceProvider);
            groupIds = await seeder.SeedAsync(cancellationToken);
        }

        return new SeedOutcome(groupIds, await WaitForDrainAsync(services, groupIds, timeout, cancellationToken));
    }

    private static async Task<bool> WaitForDrainAsync(
        IServiceProvider services,
        IReadOnlyList<int> groupIds,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var signal = services.GetRequiredService<TransactionProcessedSignal>();
        var deadline = DateTime.UtcNow + timeout;

        // The signal says "a message was processed", not "yours was", so it paces the loop
        // and the pending flags decide when to stop. Counting signals instead would let a
        // message enqueued by something else end the wait early.
        while (await PendingCountAsync(services, groupIds, cancellationToken) > 0)
        {
            var remaining = deadline - DateTime.UtcNow;

            if (remaining <= TimeSpan.Zero || !await signal.WaitAsync(remaining, cancellationToken))
            {
                return await PendingCountAsync(services, groupIds, cancellationToken) == 0;
            }
        }

        return true;
    }

    private static async Task<int> PendingCountAsync(
        IServiceProvider services,
        IReadOnlyList<int> groupIds,
        CancellationToken cancellationToken)
    {
        using var scope = services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        return await context.Group
            .Where(group => groupIds.Contains(group.Id) && group.BalancesPending)
            .CountAsync(cancellationToken);
    }
}
