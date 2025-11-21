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
}