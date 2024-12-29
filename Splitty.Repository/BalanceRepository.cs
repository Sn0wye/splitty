using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class BalanceRepository(ApplicationDbContext context) : IBalanceRepository
{
    public async Task<Balance> CreateAsync(Balance balance)
    {
        await context.Balance.AddAsync(balance);
        await context.SaveChangesAsync();
        return balance;
    }

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

    public async Task<Balance> UpdateAsync(Balance balance)
    {
        context.Balance.Update(balance);
        await context.SaveChangesAsync();
        return balance;
    }
    
    public async Task<List<Balance>> UpdateBalancesAsync(List<Balance> balances)
    {
        context.Balance.UpdateRange(balances);
        await context.SaveChangesAsync();
        return balances;
    }
}