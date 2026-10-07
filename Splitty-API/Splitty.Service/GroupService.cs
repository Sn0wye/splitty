using Splitty.Domain.Entities;
using Splitty.DTO.Internal;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class GroupService(
    IGroupRepository groupRepository,
    IGroupMembershipRepository groupMembershipRepository,
    IGroupReadModel readModel,
    IRecurringExpenseService recurringExpenseService,
    IGroupLedger groupLedger
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

    public async Task<GroupDTO?> OpenAsync(int groupId, int userId)
    {
        if (!await IsMemberAsync(groupId, userId)) return null;

        await recurringExpenseService.CatchUpAsync(groupId);

        return await readModel.GetGroupAsync(groupId, userId);
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

        // A repeat that came due counts before anyone leaves, and makes the group pending,
        // which the check below then refuses until the replay has seen it.
        await recurringExpenseService.CatchUpAsync(groupId);

        var net = await groupLedger.ReadAsync(groupId, () => readModel.GetMemberNetAsync(groupId, targetUserId));

        if (net.Pending) return MembershipRemovalStatus.BalancesPending;

        // Flat permissions: any member may remove any settled member, including themselves.
        if (net.Value != 0) return MembershipRemovalStatus.OutstandingBalance;

        // Catch-up copies splits without checking membership, so nothing may keep billing
        // someone who is no longer in the group.
        await recurringExpenseService.EndForMemberAsync(groupId, targetUserId);
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
