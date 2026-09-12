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

    /// <summary>
    /// Every other member of every group the user is in, the membership-derived peer set:
    /// deriving it from balances instead would drop peers settled to exactly zero, who have
    /// no row. The group filter is the access control — only shared groups can appear.
    /// </summary>
    public async Task<List<GroupMembership>> GetPeerMembershipsAsync(int userId)
    {
        var groupIds = context.GroupMembership
            .Where(gm => gm.UserId == userId)
            .Select(gm => gm.GroupId);

        return await context.GroupMembership
            .Include(gm => gm.User)
            .Include(gm => gm.Group)
            .Where(gm => gm.UserId != userId && groupIds.Contains(gm.GroupId))
            .ToListAsync();
    }

    /// <summary>
    /// Whether the two are in at least one group together. The membership boundary the
    /// peer profile route is gated on.
    /// </summary>
    public async Task<bool> SharesGroupAsync(int userId, int peerId)
    {
        var groupIds = context.GroupMembership
            .Where(gm => gm.UserId == userId)
            .Select(gm => gm.GroupId);

        return await context.GroupMembership
            .AnyAsync(gm => gm.UserId == peerId && groupIds.Contains(gm.GroupId));
    }

    public async Task<List<GroupMembership>> GetGroupMembershipsAsync(int groupId)
    {
        return await context.GroupMembership
            .Where(gm => gm.GroupId == groupId)
            .ToListAsync();
    }
}