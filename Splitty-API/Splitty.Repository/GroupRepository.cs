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

    // Written in the database, so a rename never saves back the pending columns or the
    // balances it would have read alongside them. A null field keeps its stored value.
    public async Task RenameAsync(int groupId, string? name, string? description)
    {
        await context.Group
            .Where(g => g.Id == groupId)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(g => g.Name, g => name ?? g.Name)
                .SetProperty(g => g.Description, g => description ?? g.Description));
    }

    public async Task DeleteAsync(int groupId)
    {
        await context.Group.Where(g => g.Id == groupId).ExecuteDeleteAsync();
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