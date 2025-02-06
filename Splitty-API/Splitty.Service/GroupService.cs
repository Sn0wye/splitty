using Splitty.Domain.Entities;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class GroupService(
    IGroupRepository groupRepository,
    IGroupMembershipRepository groupMembershipRepository
    ): IGroupService
{
    public async Task<Group> CreateAsync(int userId, string name, string? description)
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

        return await groupRepository.GetGroupByIdAsync(group.Id);
    }

    public async Task<Group?> GetGroupAsync(int groupId, int userId)
    {
        var group = await groupRepository.GetGroupByIdAsync(groupId);

        if (group is null) return null;
        
        return group.Members.Any(gm => gm.UserId == userId) ? group : null;
    }

    public async Task<List<Group>> GetGroupsByUserId(int userId)
    {
        return await groupRepository.GetGroupsByUserId(userId);
    }

    public async Task<Group> UpdateAsync(int groupId, int userId, string? name, string? description)
    {
        var group = await groupRepository.GetGroupByIdAsync(groupId);

        if (group is null)
        {
            throw new ArgumentException("Group not found");
        }

        if (group.Members.All(gm => gm.UserId != userId))
        {
            throw new UnauthorizedAccessException("User is not a member of the group");
        }

        if (!string.IsNullOrEmpty(name))
        {
            group.Name = name;
        }
        
        if (!string.IsNullOrEmpty(description))
        {
            group.Description = description;
        }

        await groupRepository.UpdateAsync(group);

        return group;
    }

    public async Task<Group> JoinGroupAsync(int groupId, int userId)
    {
        var group = await groupRepository.GetGroupByIdAsync(groupId);

        if (group is null)
        {
            throw new ArgumentException("Group not found");
        }
        
        if (group.Members.Any(gm => gm.UserId == userId))
        {
            throw new InvalidOperationException("User is already a member of the group");
        }

        var groupMembership = new GroupMembership
        {
            UserId = userId,
            GroupId = groupId,
        };

        await groupMembershipRepository.CreateAsync(groupMembership);

        return group;
    }
}