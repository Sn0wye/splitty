using System.Threading.Channels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Splitty.Service.Interfaces;

namespace Splitty.Background;

/// <summary>
/// Drains the group ledger's queue, handing each request to the ledger in a fresh scope. The
/// protocol, including which requests are skipped, lives in the ledger; this loop only keeps
/// one failed group from stopping the rest and signals every message it read.
/// </summary>
public class TransactionBackgroundService(
    ChannelReader<LedgerRequest> requests,
    IServiceScopeFactory serviceScopeFactory,
    TransactionProcessedSignal processed,
    ILogger<TransactionBackgroundService> logger
) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var request in requests.ReadAllAsync(stoppingToken))
        {
            try
            {
                using var scope = serviceScopeFactory.CreateScope();
                await scope.ServiceProvider.GetRequiredService<IGroupLedger>().ProcessAsync(request, stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogError(ex, "Failed to recompute balances for group {GroupId}", request.GroupId);
            }
            finally
            {
                processed.Notify();
            }
        }
    }
}
