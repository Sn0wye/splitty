using Splitty.Domain.Entities;
using Splitty.DTO.Internal;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class GroupService(
    IGroupRepository groupRepository,
    IGroupMembershipRepository groupMembershipRepository,
    IGroupReadModel readModel
) : IGroupService
{
    public async Task<GroupDTO> CreateAsync(int userId, string name, string? description)
    {
        var group = new Group
        {
            Name = name,
            Description = description,
            CreatedBy = userId,
        };

        await groupRepository.CreateAsync(group);

        var groupMembership = new GroupMembership
        {
            UserId = userId,
            GroupId = group.Id,
        };

        await groupMembershipRepository.CreateAsync(groupMembership);

        return await readModel.GetGroupAsync(group.Id, userId)
            ?? throw new KeyNotFoundException("Group not found");
    }

    public async Task<GroupDTO> UpdateAsync(int groupId, int userId, string? name, string? description)
    {
        if (!await IsMemberAsync(groupId, userId))
        {
            if (!await readModel.GroupExistsAsync(groupId))
            {
                throw new KeyNotFoundException("Group not found");
            }

            throw new UnauthorizedAccessException("User is not a member of the group");
        }

        await groupRepository.RenameAsync(
            groupId,
            string.IsNullOrEmpty(name) ? null : name,
            string.IsNullOrEmpty(description) ? null : description);

        return await readModel.GetGroupAsync(groupId, userId)
            ?? throw new KeyNotFoundException("Group not found");
    }

    public async Task<MembershipRemovalStatus> LeaveAsync(int groupId, int userId)
    {
        return await RemoveMemberAsync(groupId, userId, userId);
    }

    public async Task<MembershipRemovalStatus> RemoveMemberAsync(int groupId, int actorId, int targetUserId)
    {
        if (!await readModel.GroupExistsAsync(groupId)) return MembershipRemovalStatus.GroupNotFound;

        if (!await IsMemberAsync(groupId, actorId)) return MembershipRemovalStatus.NotAMember;

        var membership = await groupMembershipRepository.GetGroupMembershipByUserIdAndGroupId(targetUserId, groupId);

        if (membership is null) return MembershipRemovalStatus.TargetNotAMember;

        // Flat permissions: any member may remove any settled member, including themselves.
        if (await readModel.GetMemberNetAsync(groupId, targetUserId) != 0) return MembershipRemovalStatus.OutstandingBalance;

        await groupMembershipRepository.DeleteAsync(membership);

        if (await groupMembershipRepository.CountByGroupIdAsync(groupId) == 0)
        {
            await groupRepository.DeleteAsync(groupId);
        }

        return MembershipRemovalStatus.Success;
    }

    public Task<bool> IsMemberAsync(int groupId, int userId) =>
        readModel.IsMemberAsync(groupId, userId);
}
