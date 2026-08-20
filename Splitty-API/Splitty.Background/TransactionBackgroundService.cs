using System.Threading.Channels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Background;

public class TransactionBackgroundService(
    Channel<TransactionRequest> channel,
    IServiceScopeFactory serviceScopeFactory,
    TransactionProcessedSignal processed,
    ILogger<TransactionBackgroundService> logger
) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var request in channel.Reader.ReadAllAsync(stoppingToken))
        {
            try
            {
                using var scope = serviceScopeFactory.CreateScope();
                var balanceService = scope.ServiceProvider.GetRequiredService<IBalanceService>();
                await balanceService.CalculateGroupBalances(request.groupId);

                var groupRepository = scope.ServiceProvider.GetRequiredService<IGroupRepository>();
                await groupRepository.SetBalancesPendingAsync(request.groupId, false);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogError(ex, "Failed to recompute balances for group {GroupId}", request.groupId);
            }
            finally
            {
                processed.Notify();
            }
        }
    }
}

public record TransactionRequest(
    int groupId
    );
