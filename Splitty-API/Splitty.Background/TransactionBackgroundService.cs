using System.Threading.Channels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Splitty.Service;
using Splitty.Service.Interfaces;

namespace Splitty.Background;

public class TransactionBackgroundService: BackgroundService
{
    private readonly Channel<TransactionRequest> _channel;
    private readonly IBalanceService _balanceService;
    
    public TransactionBackgroundService(Channel<TransactionRequest> channel,
        IServiceScopeFactory serviceScopeFactory
        )
    {
        _channel = channel;
        var scope = serviceScopeFactory.CreateScope();
        _balanceService = scope.ServiceProvider.GetRequiredService<IBalanceService>();
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (await _channel.Reader.WaitToReadAsync(stoppingToken))
        {
            var request = await _channel.Reader.ReadAsync(stoppingToken);
            await _balanceService.CalculateGroupBalances(request.groupId);
        }
    }
}

public record TransactionRequest(
    int groupId
    );