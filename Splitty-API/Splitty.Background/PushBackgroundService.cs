using System.Threading.Channels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Splitty.Service;

namespace Splitty.Background;

/// <summary>
/// Sends the notices writes queued, one at a time, each in a fresh scope. A failure is logged
/// and dropped: notifications are best effort and never block or undo the write behind them.
/// </summary>
public class PushBackgroundService(
    ChannelReader<Notice> notices,
    IServiceScopeFactory serviceScopeFactory,
    ILogger<PushBackgroundService> logger
) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var notice in notices.ReadAllAsync(stoppingToken))
        {
            try
            {
                using var scope = serviceScopeFactory.CreateScope();
                await scope.ServiceProvider.GetRequiredService<PushDispatcher>().DispatchAsync(notice, stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogError(ex, "Failed to send {Message} to user {UserId}", notice.Message, notice.RecipientId);
            }
        }
    }
}
