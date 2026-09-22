using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class BalanceRepository(ApplicationDbContext context) : IBalanceRepository
{
    public async Task<List<Balance>> GetGroupBalancesAsync(int groupId)
    {
        return await context.Balance
            .Include(b => b.User)
            .Include(b => b.Peer)
            .Where(b => b.GroupId == groupId)
            .ToListAsync();
    }

    public async Task<List<Balance>> GetUserGroupBalances(int userId, int groupId)
    {
        return await context.Balance
            .Include(b => b.User)
            .Include(b => b.Peer)
            .Where(b => b.UserId == userId && b.GroupId == groupId)
            .ToListAsync();
    }
    
    public async Task<List<Balance>> GetUserBalancesAsync(int userId)
    {
        return await context.Balance
            .Where(b => b.UserId == userId)
            .ToListAsync();
    }

    public Task<List<SimplifiedDebt>> GetSimplifiedDebtsAsync(int groupId) =>
        context.SimplifiedDebt.AsNoTracking()
            .Include(d => d.FromUser).Include(d => d.ToUser)
            .Where(d => d.GroupId == groupId)
            .OrderBy(d => d.FromUserId).ThenBy(d => d.ToUserId).ToListAsync();

    public Task<List<SimplifiedDebt>> GetUserSimplifiedDebtsAsync(int userId) =>
        context.SimplifiedDebt.AsNoTracking()
            .Where(d => d.FromUserId == userId || d.ToUserId == userId).ToListAsync();

    public async Task ReplaceSimplifiedDebtsAsync(int groupId, List<SimplifiedDebt> debts)
    {
        await using var transaction = await context.Database.BeginTransactionAsync();
        await context.SimplifiedDebt.Where(d => d.GroupId == groupId).ExecuteDeleteAsync();
        context.SimplifiedDebt.AddRange(debts);
        await context.SaveChangesAsync();
        await transaction.CommitAsync();
    }

    public async Task<List<Balance>> UpdateBalancesAsync(List<Balance> balances)
    {
        context.Balance.UpdateRange(balances);
        await context.SaveChangesAsync();
        return balances;
    }
}
