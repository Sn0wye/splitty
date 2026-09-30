using System.Net;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Background;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class TransactionDrainTests
{
    private readonly ApiFactory _factory;

    public TransactionDrainTests(ApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Worker_signals_completion_when_recompute_throws()
    {
        await using var factory = _factory.WithReplay((_, _) =>
            Task.FromException(new InvalidOperationException("recompute failed")));

        var owner = ApiClient.Create(factory);
        var ownerUser = await owner.SignInAsync();
        owner = ApiClient.Create(factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync();
        var code = await owner.CreateInviteAsync(groupId);

        var guest = ApiClient.Create(factory);
        var guestUser = await guest.SignInAsync();
        guest = ApiClient.Create(factory, guestUser.Token);
        (await guest.AcceptInviteAsync(code)).EnsureSuccessStatusCode();

        var response = await owner.CreateExpenseAsync(groupId, new
        {
            paidBy = ownerUser.Id,
            amount = 20m,
            description = "Dinner",
            splitMode = "equal",
            splits = new[]
            {
                new { userId = ownerUser.Id, amount = 10m },
                new { userId = guestUser.Id, amount = 10m }
            }
        });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await factory.Services.GetRequiredService<TransactionProcessedSignal>().WaitAsync(cts.Token);

        // Recover this deliberately failed request so later hosts have no unrelated backlog.
        await _factory.DrainProcessedAsync();
        var recovery = ApiClient.Create(_factory, ownerUser.Token);
        (await recovery.RequestSummaryRefreshAsync(groupId)).EnsureSuccessStatusCode();
        await _factory.WaitForProcessedAsync();
    }
}
