using Splitty.Domain.Entities;
using Splitty.DTO.Internal;

namespace Splitty.Repository.Interfaces;

/// <summary>
/// The group ledger's queries: the pending flag, its generation, and the rows the replay reads
/// and writes. Internal, and visible only to Splitty.Service, so nothing but the ledger can
/// mark a group pending or clear it.
/// </summary>
internal interface ILedgerRepository
{
    /// <summary>
    /// Sets the pending flag and bumps the generation in one statement. Returns the new
    /// generation, or null when the group does not exist.
    /// </summary>
    Task<int?> MarkPendingAsync(int groupId, CancellationToken cancellationToken);

    /// <summary>The group's current generation, or null when the group does not exist.</summary>
    Task<int?> GetPendingGenerationAsync(int groupId, CancellationToken cancellationToken);

    Task<bool> IsPendingAsync(int groupId, CancellationToken cancellationToken);

    Task<List<int>> GetPendingGroupIdsAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Per (payer, participant) pair with participant ≠ payer, the sum of absolute split
    /// amounts over every expense and payment in the group. Untracked.
    /// </summary>
    Task<List<PairwisePosition<int>>> GetPositionsAsync(int groupId, CancellationToken cancellationToken);

    /// <summary>The group's stored pairwise balances. Untracked.</summary>
    Task<List<PairwiseBalance<int>>> GetBalancesAsync(int groupId, CancellationToken cancellationToken);

    /// <summary>
    /// Writes a replay's result in one transaction: inserts new pairs, updates changed pairs,
    /// zeroes pairs that disappeared, replaces the simplified debts, and clears the pending
    /// flag only if the group is still at <paramref name="generation"/>. A throw writes nothing.
    /// </summary>
    Task WriteReplayAsync(
        int groupId,
        int generation,
        IReadOnlyCollection<PairwiseBalance<int>> balances,
        IReadOnlyCollection<SimplifiedDebt> debts,
        CancellationToken cancellationToken);
}
