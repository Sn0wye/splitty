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
}