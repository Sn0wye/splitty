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
    
    /// <summary>
    /// The single row the settle cap is read from. No includes: the cap needs the amount,
    /// not the users behind it.
    /// </summary>
    public async Task<Balance?> GetPairwiseBalanceAsync(int userId, int peerId, int groupId)
    {
        return await context.Balance
            .FirstOrDefaultAsync(b => b.UserId == userId && b.PeerId == peerId && b.GroupId == groupId);
    }

    public async Task<List<Balance>> UpdateBalancesAsync(List<Balance> balances)
    {
        context.Balance.UpdateRange(balances);
        await context.SaveChangesAsync();
        return balances;
    }
}
