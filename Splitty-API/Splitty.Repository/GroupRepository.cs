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
}