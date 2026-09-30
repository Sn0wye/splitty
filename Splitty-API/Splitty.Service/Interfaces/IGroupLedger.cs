namespace Splitty.Service.Interfaces;

/// <summary>
/// The only way to ask for a group's balances to be derived from its money rows, and the
/// only reader of whether that derivation is outstanding. See <see cref="GroupLedger"/> for
/// the pending-generation protocol behind it.
/// </summary>
public interface IGroupLedger
{
    /// <summary>
    /// Marks the group pending and queues its recomputation, in that order. Every money write
    /// calls this after it saves; a rejected write calls nothing.
    /// </summary>
    Task RequestRecomputationAsync(int groupId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Reads the pending flag, then runs <paramref name="read"/> over the derived rows. The
    /// flag goes first so a replay landing between the two reports fresh figures as pending,
    /// never stale figures as settled.
    /// </summary>
    Task<LedgerRead<T>> ReadAsync<T>(int groupId, Func<Task<T>> read);

    /// <summary>
    /// The most <paramref name="payerId"/> may settle with <paramref name="payeeId"/> right
    /// now (invariant 5): zero while the group is pending, otherwise the smaller of the payer's
    /// net debt and the payee's net credit over stored balances, with an edited payment's own
    /// contribution passed as <paramref name="excluding"/>.
    /// </summary>
    Task<decimal> SettlementCapAsync(int groupId, int payerId, int payeeId, decimal excluding = 0m);

    /// <summary>
    /// Handles one queued request. Called only by the background worker, once per message it
    /// reads; a request superseded by a newer write returns without replaying.
    /// </summary>
    Task ProcessAsync(LedgerRequest request, CancellationToken cancellationToken = default);
}

/// <summary>
/// A queued recomputation: the group and the pending generation its request produced. Only
/// the ledger creates one, so the worker can hand the ledger nothing it did not queue.
/// </summary>
public sealed class LedgerRequest
{
    internal LedgerRequest(int groupId, int generation)
    {
        GroupId = groupId;
        Generation = generation;
    }

    public int GroupId { get; }
    public int Generation { get; }
}

/// <param name="Value">What the read returned.</param>
/// <param name="Pending">Whether a recomputation was outstanding before the read began.</param>
public sealed record LedgerRead<T>(T Value, bool Pending);
