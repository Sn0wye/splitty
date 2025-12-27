using Splitty.Domain.Entities;
using Splitty.DTO.Internal;

namespace Splitty.Service.Interfaces;

public interface IGroupService
{
    Task<Group> CreateAsync(int userId, string name, string? description);
    Task<GroupDTO?> GetGroupAsync(int groupId, int userId);
    Task<List<GroupDTO>> GetGroupsByUserId(int userId);
    Task<Group> UpdateAsync(int groupId, int userId, string name, string? description);
    Task<Group> JoinGroupAsync(int groupId, int userId);
}