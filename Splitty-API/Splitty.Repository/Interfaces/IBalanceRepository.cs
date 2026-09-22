using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IBalanceRepository
{
    Task<List<Balance>> GetGroupBalancesAsync(int groupId);
    Task<List<Balance>> GetUserGroupBalances(int userId, int groupId);
    Task<List<Balance>> GetUserBalancesAsync(int userId);
    Task<List<SimplifiedDebt>> GetSimplifiedDebtsAsync(int groupId);
    Task<List<SimplifiedDebt>> GetUserSimplifiedDebtsAsync(int userId);
    Task ReplaceSimplifiedDebtsAsync(int groupId, List<SimplifiedDebt> debts);
    Task<List<Balance>> UpdateBalancesAsync(List<Balance> balances);
}
