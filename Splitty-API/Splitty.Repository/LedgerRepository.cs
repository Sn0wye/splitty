using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.DTO.Internal;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

internal sealed class LedgerRepository(ApplicationDbContext context) : ILedgerRepository
{
    // One statement, so the generation returned is the one this call produced even when
    // requests for the group race. Written in the database: a Group already tracked in this
    // scope keeps its old values, so callers must not save one back after marking it.
    public async Task<int?> MarkPendingAsync(int groupId, CancellationToken cancellationToken)
    {
        var generations = await context.Database.SqlQuery<int>($"""
            UPDATE "Group"
            SET "BalancesPending" = TRUE,
                "BalancesPendingGeneration" = "BalancesPendingGeneration" + 1
            WHERE "Id" = {groupId}
            RETURNING "BalancesPendingGeneration" AS "Value"
            """).ToListAsync(cancellationToken);

        return generations.Count == 0 ? null : generations[0];
    }

    public Task<int?> GetPendingGenerationAsync(int groupId, CancellationToken cancellationToken) =>
        context.Group
            .Where(g => g.Id == groupId)
            .Select(g => (int?)g.BalancesPendingGeneration)
            .FirstOrDefaultAsync(cancellationToken);

    public Task<bool> IsPendingAsync(int groupId, CancellationToken cancellationToken) =>
        context.Group
            .Where(g => g.Id == groupId)
            .Select(g => g.BalancesPending)
            .FirstOrDefaultAsync(cancellationToken);

    public Task<List<int>> GetPendingGroupIdsAsync(CancellationToken cancellationToken) =>
        context.Group
            .Where(g => g.BalancesPending)
            .Select(g => g.Id)
            .ToListAsync(cancellationToken);

    // Aggregated in the database, so the cost grows with pairs of members rather than with
    // the group's history.
    public Task<List<PairwisePosition<int>>> GetPositionsAsync(int groupId, CancellationToken cancellationToken) =>
        context.ExpenseSplit
            .Where(s => s.Expense.GroupId == groupId && s.UserId != s.Expense.PaidBy)
            .GroupBy(s => new { s.Expense.PaidBy, s.UserId })
            .Select(pair => new PairwisePosition<int>(pair.Key.PaidBy, pair.Key.UserId, pair.Sum(s => Math.Abs(s.Amount))))
            .ToListAsync(cancellationToken);

    public Task<List<PairwiseBalance<int>>> GetBalancesAsync(int groupId, CancellationToken cancellationToken) =>
        context.Balance.AsNoTracking()
            .Where(b => b.GroupId == groupId)
            .Select(b => new PairwiseBalance<int>(b.UserId, b.PeerId, b.Amount))
            .ToListAsync(cancellationToken);

    public async Task WriteReplayAsync(
        int groupId,
        int generation,
        IReadOnlyCollection<PairwiseBalance<int>> balances,
        IReadOnlyCollection<SimplifiedDebt> debts,
        CancellationToken cancellationToken)
    {
        await using var transaction = await context.Database.BeginTransactionAsync(cancellationToken);

        await StageBalancesAsync(groupId, balances, cancellationToken);

        await context.SimplifiedDebt.Where(d => d.GroupId == groupId).ExecuteDeleteAsync(cancellationToken);
        context.SimplifiedDebt.AddRange(debts);

        await context.SaveChangesAsync(cancellationToken);

        // Matches no row once a newer write has bumped the generation, leaving the flag set
        // for that write's own replay to clear.
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
        IReadOnlyCollection<PairwiseBalance<int>> balances,
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
