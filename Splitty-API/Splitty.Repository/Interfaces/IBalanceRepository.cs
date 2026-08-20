using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IBalanceRepository
{
    Task<List<Balance>> GetGroupBalancesAsync(int groupId);
    Task<List<Balance>> GetUserGroupBalances(int userId, int groupId);
    Task<Balance?> GetPairwiseBalanceAsync(int userId, int peerId, int groupId);
    Task<List<Balance>> UpdateBalancesAsync(List<Balance> balances);
}
