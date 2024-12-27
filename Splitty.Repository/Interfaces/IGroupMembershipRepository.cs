using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IGroupMembershipRepository
{
    Task<GroupMembership> CreateAsync(GroupMembership groupMembership);
    Task<GroupMembership?> GetGroupMembershipByUserIdAndGroupId(int userId, int groupId);
}