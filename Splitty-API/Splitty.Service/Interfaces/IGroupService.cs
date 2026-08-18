using Splitty.Domain.Entities;
using Splitty.DTO.Internal;

namespace Splitty.Service.Interfaces;

public enum MembershipRemovalStatus
{
    Success,
    GroupNotFound,
    NotAMember,
    TargetNotAMember,
    OutstandingBalance
}

public interface IGroupService
{
    Task<Group> CreateAsync(int userId, string name, string? description);
    Task<GroupDTO?> GetGroupAsync(int groupId, int userId);
    Task<List<GroupDTO>> GetGroupsByUserId(int userId);
    Task<Group> UpdateAsync(int groupId, int userId, string name, string? description);
    Task<MembershipRemovalStatus> LeaveAsync(int groupId, int userId);
    Task<MembershipRemovalStatus> RemoveMemberAsync(int groupId, int actorId, int targetUserId);
    Task<bool> IsMemberAsync(int groupId, int userId);
}