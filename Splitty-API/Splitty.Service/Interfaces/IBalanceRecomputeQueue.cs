namespace Splitty.Service.Interfaces;

/// <summary>
/// The only supported way to request a balance recomputation.
/// </summary>
public interface IBalanceRecomputeQueue
{
    Task EnqueueAsync(int groupId, CancellationToken cancellationToken = default);
}
