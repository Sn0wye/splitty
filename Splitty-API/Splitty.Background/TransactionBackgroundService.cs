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
                var groupRepository = scope.ServiceProvider.GetRequiredService<IGroupRepository>();

                // Read before the replay loads any rows: a write that lands after this bumps
                // the generation, so the clear below misses and that write's replay clears it.
                var generation = await groupRepository.GetBalancesPendingGenerationAsync(request.groupId);

                var balanceService = scope.ServiceProvider.GetRequiredService<IBalanceService>();
                await balanceService.CalculateGroupBalances(request.groupId);

                await groupRepository.MarkBalancesRecomputedAsync(request.groupId, generation);
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
