using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

public interface IGroupService
{
    Task<Group> CreateAsync(int userId, string name, string? description);
    Task<Group?> GetGroupAsync(int groupId, int userId);
    Task<List<Group>> GetGroupsByUserId(int userId);
    Task<Group> UpdateAsync(int groupId, int userId, string name, string? description);
    Task<Group> JoinGroupAsync(int groupId, int userId);
}