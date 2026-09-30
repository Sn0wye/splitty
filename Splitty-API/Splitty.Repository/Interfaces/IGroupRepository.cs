using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IGroupRepository
{
    Task CreateAsync(Group group);
    Task RenameAsync(int groupId, string? name, string? description);
    Task DeleteAsync(int groupId);
    Task MarkBalancesPendingAsync(int groupId);
    Task<int> GetBalancesPendingGenerationAsync(int groupId);

    /// <summary>
    /// Clears the pending flag only if the group is still at <paramref name="generation"/>,
    /// the value read before the replay loaded any rows.
    /// </summary>
    Task MarkBalancesRecomputedAsync(int groupId, int generation);
    Task<bool> GetBalancesPendingAsync(int groupId);
}