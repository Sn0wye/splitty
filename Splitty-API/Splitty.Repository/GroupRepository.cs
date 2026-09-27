using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class GroupRepository(ApplicationDbContext context): IGroupRepository
{
    public async Task CreateAsync(Group group)
    {
        await context.Group.AddAsync(group);
        await context.SaveChangesAsync();
    }

    public async Task<Group?> GetGroupByIdAsync(int groupId)
    {
        return await context.Group
            .Include(g => g.CreatedByUser)
            .Include(g => g.Members)
            .ThenInclude(gm => gm.User)
            .Include(g => g.Balances)
            .FirstOrDefaultAsync(g => g.Id == groupId);
    }

    public async Task<List<Group>> GetGroupsByUserId(int userId)
    {
        return await context.Group
            .Where(g => g.Members.Any(gm => gm.UserId == userId))
            .Include(g => g.CreatedByUser)
            .Include(g => g.Members)
            .ThenInclude(gm => gm.User)
            .Include(g => g.Balances)
            .ToListAsync();
    }

    public async Task UpdateAsync(Group group)
    {
        if (group == null)
        {
            throw new ArgumentNullException(nameof(group));
        }
        
        context.Group.Update(group);
        await context.SaveChangesAsync();
    }

    public async Task DeleteAsync(Group group)
    {
        context.Group.Remove(group);
        await context.SaveChangesAsync();
    }

    // Written in the database rather than through a tracked entity, so the flag can be set
    // without loading the group's members and balances. The tracker is left untouched: a Group
    // already loaded in this scope keeps its old values, so callers must not save one back
    // after marking it.
    public async Task MarkBalancesPendingAsync(int groupId)
    {
        await context.Group
            .Where(g => g.Id == groupId)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(g => g.BalancesPending, true)
                .SetProperty(g => g.BalancesPendingGeneration, g => g.BalancesPendingGeneration + 1));
    }

    public async Task<int> GetBalancesPendingGenerationAsync(int groupId)
    {
        return await context.Group
            .Where(g => g.Id == groupId)
            .Select(g => g.BalancesPendingGeneration)
            .FirstOrDefaultAsync();
    }

    // Matches no row once a newer write has bumped the generation, leaving the flag set for
    // that write's own replay to clear.
    public async Task MarkBalancesRecomputedAsync(int groupId, int generation)
    {
        await context.Group
            .Where(g => g.Id == groupId && g.BalancesPendingGeneration == generation)
            .ExecuteUpdateAsync(setters => setters.SetProperty(g => g.BalancesPending, false));
    }

    public async Task<bool> GetBalancesPendingAsync(int groupId)
    {
        return await context.Group
            .Where(g => g.Id == groupId)
            .Select(g => g.BalancesPending)
            .FirstOrDefaultAsync();
    }
}