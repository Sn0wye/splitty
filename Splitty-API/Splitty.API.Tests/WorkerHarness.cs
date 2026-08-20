using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Background;
using Splitty.Infrastructure;

namespace Splitty.API.Tests;

/// <summary>
/// Turns the worker's per-message completion signal into assertions that await a drain
/// instead of racing it.
/// </summary>
public static class WorkerHarness
{
    private static readonly TimeSpan DrainTimeout = TimeSpan.FromSeconds(15);

    /// <summary>
    /// Consumes completions left over from earlier tests sharing this host, so a later
    /// wait counts only the messages the calling test enqueued.
    /// </summary>
    public static async Task DrainProcessedAsync(this WebApplicationFactory<Program> factory)
    {
        var signal = factory.Services.GetRequiredService<TransactionProcessedSignal>();
        while (await signal.WaitAsync(TimeSpan.Zero))
        {
        }
    }

    public static async Task WaitForProcessedAsync(this WebApplicationFactory<Program> factory, int count = 1)
    {
        var signal = factory.Services.GetRequiredService<TransactionProcessedSignal>();

        for (var i = 0; i < count; i++)
        {
            Assert.True(
                await signal.WaitAsync(DrainTimeout),
                $"Timed out waiting for message {i + 1} of {count} to be processed.");
        }
    }

    public static async Task<T> UseDbAsync<T>(
        this WebApplicationFactory<Program> factory,
        Func<ApplicationDbContext, Task<T>> query)
    {
        using var scope = factory.Services.CreateScope();
        return await query(scope.ServiceProvider.GetRequiredService<ApplicationDbContext>());
    }
}
