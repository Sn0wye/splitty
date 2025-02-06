using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IBalanceRepository
{
    Task<Balance> CreateAsync(Balance balance);
    Task<List<Balance>> GetGroupBalancesAsync(int groupId);
    Task<List<Balance>> GetUserGroupBalances(int userId, int groupId);
    Task<Balance> UpdateAsync(Balance balance);
    Task<List<Balance>> UpdateBalancesAsync(List<Balance> balances);
}