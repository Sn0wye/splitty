using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IGroupMembershipRepository
{
    Task<GroupMembership> CreateAsync(GroupMembership groupMembership);
    Task<GroupMembership?> GetGroupMembershipByUserIdAndGroupId(int userId, int groupId);
    Task<List<GroupMembership>> GetGroupMembershipsAsync(int groupId);
}