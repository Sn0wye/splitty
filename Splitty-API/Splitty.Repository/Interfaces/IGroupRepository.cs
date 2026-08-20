using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IGroupRepository
{
    Task CreateAsync(Group group);
    Task<Group?> GetGroupByIdAsync(int groupId);
    Task<List<Group>> GetGroupsByUserId(int userId);
    Task UpdateAsync(Group group);
    Task DeleteAsync(Group group);
    Task SetBalancesPendingAsync(int groupId, bool pending);
    Task<bool> GetBalancesPendingAsync(int groupId);
}