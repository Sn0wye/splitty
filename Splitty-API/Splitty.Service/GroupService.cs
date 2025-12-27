using Splitty.Domain.Entities;
using Splitty.DTO.Internal;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class GroupService(
    IGroupRepository groupRepository,
    IGroupMembershipRepository groupMembershipRepository,
    IBalanceRepository balanceRepository
) : IGroupService
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

    public async Task<GroupDTO?> GetGroupAsync(int groupId, int userId)
    {
        var group = await groupRepository.GetGroupByIdAsync(groupId);

        if (group is null) return null;
        
        var netBalance = group.Balances.Where(b => b.UserId == userId).ToList().Sum(b => b.Amount);
        
        return group.Members.Any(gm => gm.UserId == userId) ? 
            new GroupDTO
            {
                Id = group.Id,
                Name = group.Name,
                Description = group.Description,
                CreatedAt = group.CreatedAt,
                NetBalance = netBalance,
                Members = group.Members.Select(gm => new MemberDTO
                {
                    Id = gm.Id,
                    UserId = gm.UserId,
                    Name = gm.User.Name,
                    Email = gm.User.Email,
                    AvatarUrl = gm.User.AvatarUrl,
                }).ToList(),
            }
            : null;
    }

    public async Task<List<GroupDTO>> GetGroupsByUserId(int userId)
    {
        var results = new List<GroupDTO>();
        var groups = await groupRepository.GetGroupsByUserId(userId);

        foreach (var group in groups)
        {
            var netBalance = group.Balances.Where(b => b.UserId == userId).ToList().Sum(b => b.Amount);
            
            results.Add(new GroupDTO
            {
                Id = group.Id,
                Name = group.Name,
                Description = group.Description,
                CreatedAt = group.CreatedAt,
                NetBalance = netBalance,
                Members = group.Members.Select(gm => new MemberDTO
                {
                    Id = gm.Id,
                    UserId = gm.UserId,
                    Name = gm.User.Name,
                    Email = gm.User.Email,
                    AvatarUrl = gm.User.AvatarUrl,
                }).ToList(),
            });
        }

        return results;
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