using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class GroupMembershipRepository(ApplicationDbContext context): IGroupMembershipRepository
{
    public async Task<GroupMembership> CreateAsync(GroupMembership groupMembership)
    {
        await context.GroupMembership.AddAsync(groupMembership);
        await context.SaveChangesAsync();

        return groupMembership;
    }
    
    /// Persists the membership. Returns false when the (UserId, GroupId) pair already exists.
    public async Task<bool> TryCreateAsync(GroupMembership groupMembership)
    {
        var entry = await context.GroupMembership.AddAsync(groupMembership);

        try
        {
            await context.SaveChangesAsync();
        }
        catch (DbUpdateException ex) when (ex.IsUniqueViolation())
        {
            // Leaving the failed insert tracked would replay it on the next save.
            entry.State = EntityState.Detached;

            return false;
        }

        return true;
    }

    public async Task<GroupMembership?> GetGroupMembershipByUserIdAndGroupId(int userId, int groupId)
    {
        return await context.GroupMembership
            .FirstOrDefaultAsync(gm => gm.UserId == userId && gm.GroupId == groupId);
    }

    public async Task DeleteAsync(GroupMembership groupMembership)
    {
        context.GroupMembership.Remove(groupMembership);
        await context.SaveChangesAsync();
    }

    public async Task<int> CountByGroupIdAsync(int groupId)
    {
        return await context.GroupMembership.CountAsync(gm => gm.GroupId == groupId);
    }

    public async Task<List<GroupMembership>> GetGroupMembershipsAsync(int groupId)
    {
        return await context.GroupMembership
            .Where(gm => gm.GroupId == groupId)
            .ToListAsync();
    }
}