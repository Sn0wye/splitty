using System.Threading.Channels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Splitty.Service.Interfaces;

namespace Splitty.Background;

public class TransactionBackgroundService(
    Channel<TransactionRequest> channel,
    IServiceScopeFactory serviceScopeFactory
) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var request in channel.Reader.ReadAllAsync(stoppingToken))
        {
            using var scope = serviceScopeFactory.CreateScope();
            var balanceService = scope.ServiceProvider.GetRequiredService<IBalanceService>();
            await balanceService.CalculateGroupBalances(request.groupId);
        }
    }
}

public record TransactionRequest(
    int groupId
    );
