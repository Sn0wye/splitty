using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Service;

namespace Splitty.API.Tests;

/// <summary>
/// Wraps the group ledger's replay step, the one seam a recompute test needs: the ledger's
/// own skipping of superseded requests still runs in front of it, so what a wrapper sees is
/// exactly the replays the ledger performed.
/// </summary>
public static class ReplayOverride
{
    /// <summary>
    /// Runs <paramref name="around"/> in place of each replay, with the replayed group id and
    /// the real replay to call or not.
    /// </summary>
    public static WebApplicationFactory<Program> WithReplay(
        this WebApplicationFactory<Program> factory,
        Func<int, Func<Task>, Task> around) =>
        factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
                services.AddScoped<IGroupReplay>(provider => new WrappedReplay(
                    ActivatorUtilities.CreateInstance<GroupReplay>(provider),
                    around))));

    private sealed class WrappedReplay(IGroupReplay inner, Func<int, Func<Task>, Task> around) : IGroupReplay
    {
        public Task ReplayAsync(int groupId, int generation, CancellationToken cancellationToken) =>
            around(groupId, () => inner.ReplayAsync(groupId, generation, cancellationToken));
    }
}
