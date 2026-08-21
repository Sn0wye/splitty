using System.Net;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Background;
using Splitty.Domain.Entities;
using Splitty.Service.Interfaces;

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
        await using var factory = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                services.AddScoped<IBalanceService, ThrowingCalculateBalanceService>();
            });
        });

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
            splits = new[]
            {
                new { userId = ownerUser.Id, amount = 10m },
                new { userId = guestUser.Id, amount = 10m }
            }
        });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await factory.Services.GetRequiredService<TransactionProcessedSignal>().WaitAsync(cts.Token);
    }

    private sealed class ThrowingCalculateBalanceService : IBalanceService
    {
        public Task<List<Balance>> CalculateGroupBalances(int groupId) =>
            throw new InvalidOperationException("recompute failed");

        public Task<List<Balance>> GetGroupUserBalance(int groupId, int userId) =>
            throw new NotSupportedException();

        public Task SettleUp(int groupId, int userId, int peerId, decimal amount) =>
            throw new NotSupportedException();

        public Task UpdateSettlement(int groupId, int expenseId, int userId, decimal amount, DateTime? date) =>
            throw new NotSupportedException();

        public Task DeleteSettlement(int groupId, int expenseId, int userId) =>
            throw new NotSupportedException();
    }
}
