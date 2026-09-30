using Splitty.Domain.Entities;
using Splitty.Repository.Interfaces;

namespace Splitty.Service;

/// <summary>
/// The balance replay. Internal, and reached only through <see cref="GroupLedger"/>: a second
/// caller racing it would insert the pairwise row neither found (invariant 4).
/// </summary>
internal interface IGroupReplay
{
    /// <summary>
    /// Derives the group's balances and simplified debts from every expense and payment, and
    /// writes both with the pending clear in one transaction. The clear matches only
    /// <paramref name="generation"/>. A throw leaves the group pending and nothing written.
    /// </summary>
    Task ReplayAsync(int groupId, int generation, CancellationToken cancellationToken);
}

internal sealed class GroupReplay(ILedgerRepository ledgerRepository) : IGroupReplay
{
    public async Task ReplayAsync(int groupId, int generation, CancellationToken cancellationToken)
    {
        var positions = await ledgerRepository.GetPositionsAsync(groupId, cancellationToken);

        var balances = LedgerCore.Balances(positions);
        var debts = LedgerCore.Simplify(LedgerCore.Nets(balances));

        await ledgerRepository.WriteReplayAsync(
            groupId,
            generation,
            balances,
            debts.Select(d => new SimplifiedDebt
            {
                GroupId = groupId, FromUserId = d.From, ToUserId = d.To, Amount = d.Amount
            }).ToList(),
            cancellationToken);
    }
}
