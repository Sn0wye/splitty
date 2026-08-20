using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IGroupRepository
{
    Task CreateAsync(Group group);
    Task<Group?> GetGroupByIdAsync(int groupId);
    Task<List<Group>> GetGroupsByUserId(int userId);
    Task UpdateAsync(Group group);
    Task DeleteAsync(Group group);
    Task MarkBalancesPendingAsync(int groupId);
    Task MarkBalancesRecomputedAsync(int groupId);
    Task<bool> GetBalancesPendingAsync(int groupId);
}