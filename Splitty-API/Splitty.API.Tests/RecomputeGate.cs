using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Domain.Entities;
using Splitty.Service;
using Splitty.Service.Interfaces;

namespace Splitty.API.Tests;

/// <summary>
/// Holds a recomputation open so a test can observe the window in which balances are
/// pending, instead of guessing whether the worker has already drained.
/// </summary>
public sealed class RecomputeGate : IDisposable
{
    private static readonly TimeSpan EntryTimeout = TimeSpan.FromSeconds(15);

    private readonly TaskCompletionSource _entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly TaskCompletionSource _released = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public Task WaitForEntryAsync() => _entered.Task.WaitAsync(EntryTimeout);

    public void Release() => _released.TrySetResult();

    // Releasing on dispose keeps a failed assertion from stranding the worker.
    public void Dispose() => Release();

    internal void SignalEntered() => _entered.TrySetResult();

    internal Task WaitForReleaseAsync() => _released.Task;
}

public static class RecomputeGateExtensions
{
    public static WebApplicationFactory<Program> WithGate(
        this WebApplicationFactory<Program> factory,
        RecomputeGate gate) =>
        factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
                services.AddScoped<IBalanceService>(provider => new GatedBalanceService(
                    ActivatorUtilities.CreateInstance<BalanceService>(provider),
                    gate))));

    private sealed class GatedBalanceService(IBalanceService inner, RecomputeGate gate)
        : BalanceServiceDecorator(inner)
    {
        public override async Task<List<Balance>> CalculateGroupBalances(int groupId)
        {
            gate.SignalEntered();
            await gate.WaitForReleaseAsync();
            return await base.CalculateGroupBalances(groupId);
        }
    }
}
