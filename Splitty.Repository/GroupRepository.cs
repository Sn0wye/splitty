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
            .Include(g => g.Memberships)
            .FirstOrDefaultAsync(g => g.Id == groupId);
    }

    public async Task<List<Group>> GetGroupsByUserId(int userId)
    {
        // return await context.Group
        //     .Where(g => g.Memberships.Any(gm => gm.UserId == userId))
        //     .Include(g => g.CreatedByUser)
        //     .ToListAsync();
        
        return await context.Group
            .Join(context.GroupMembership, g => g.Id, gm => gm.GroupId, (g, gm) => new { g, gm })
            .Where(joined => joined.gm.UserId == userId)
            .Select(joined => joined.g)
            .Include(g => g.CreatedByUser)
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
}