using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;

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

internal sealed class GroupReplay(ApplicationDbContext context) : IGroupReplay
{
    public async Task ReplayAsync(int groupId, int generation, CancellationToken cancellationToken)
    {
        // Aggregated in the database, so the cost grows with pairs of members rather than
        // with the group's history. LedgerCore would drop self-splits and take magnitudes
        // itself; doing both here just keeps them out of the result set.
        var positions = await context.ExpenseSplit
            .Where(s => s.Expense.GroupId == groupId && s.UserId != s.Expense.PaidBy)
            .GroupBy(s => new { s.Expense.PaidBy, s.UserId })
            .Select(pair => new
            {
                pair.Key.PaidBy,
                pair.Key.UserId,
                Amount = pair.Sum(s => Math.Abs(s.Amount))
            })
            .ToListAsync(cancellationToken);

        var balances = LedgerCore.Balances(
            positions.Select(p => new PairwisePosition<int>(p.PaidBy, p.UserId, p.Amount)));
        var debts = LedgerCore.Simplify(LedgerCore.Nets(balances));

        await using var transaction = await context.Database.BeginTransactionAsync(cancellationToken);

        await StageBalancesAsync(groupId, balances, cancellationToken);

        await context.SimplifiedDebt.Where(d => d.GroupId == groupId).ExecuteDeleteAsync(cancellationToken);
        context.SimplifiedDebt.AddRange(debts.Select(d => new SimplifiedDebt
        {
            GroupId = groupId, FromUserId = d.From, ToUserId = d.To, Amount = d.Amount
        }));

        await context.SaveChangesAsync(cancellationToken);

        await context.Group
            .Where(g => g.Id == groupId && g.BalancesPendingGeneration == generation)
            .ExecuteUpdateAsync(setters => setters.SetProperty(g => g.BalancesPending, false), cancellationToken);

        await transaction.CommitAsync(cancellationToken);
    }

    /// <summary>
    /// Inserts pairs seen for the first time, updates pairs whose amount changed and zeroes
    /// pairs that disappeared; an unchanged row is left out of the save. No user navigation is
    /// loaded, so nothing saved can reach a member's user row.
    /// </summary>
    private async Task StageBalancesAsync(
        int groupId,
        IReadOnlyList<PairwiseBalance<int>> balances,
        CancellationToken cancellationToken)
    {
        var derived = balances.ToDictionary(b => (b.User, b.Peer), b => b.Amount);
        var stored = await context.Balance
            .Where(b => b.GroupId == groupId)
            .ToListAsync(cancellationToken);

        foreach (var pair in stored.GroupBy(b => (b.UserId, b.PeerId)))
        {
            // Without a unique index a legacy duplicate can exist; the first row carries the
            // amount and the rest hold zero, so the pair still sums correctly.
            var amount = derived.Remove(pair.Key, out var value) ? value : 0m;
            foreach (var row in pair)
            {
                row.Amount = amount;
                amount = 0m;
            }
        }

        context.Balance.AddRange(derived.Select(pair => new Balance
        {
            GroupId = groupId, UserId = pair.Key.User, PeerId = pair.Key.Peer, Amount = pair.Value
        }));
    }
}
