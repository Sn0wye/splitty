using System.Threading.Channels;
using Splitty.Repository.Interfaces;

namespace Splitty.Background;

/// <summary>
/// The only supported way to request a balance recomputation.
/// </summary>
public interface IBalanceRecomputeQueue
{
    Task EnqueueAsync(int groupId, CancellationToken cancellationToken = default);
}

/// <summary>
/// Marks the group's balances pending and hands the recomputation to the worker.
///
/// The pending flag is written before the message is queued: queueing first would let the
/// worker clear a flag this call has not set yet, leaving the group pending forever.
/// </summary>
public sealed class BalanceRecomputeQueue(
    Channel<TransactionRequest> channel,
    IGroupRepository groupRepository
) : IBalanceRecomputeQueue
{
    public async Task EnqueueAsync(int groupId, CancellationToken cancellationToken = default)
    {
        await groupRepository.SetBalancesPendingAsync(groupId, true);
        await channel.Writer.WriteAsync(new TransactionRequest(groupId), cancellationToken);
    }
}
