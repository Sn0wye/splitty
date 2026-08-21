using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

public interface IBalanceService
{
    Task<List<Balance>> CalculateGroupBalances(int groupId);
    Task<List<Balance>> GetGroupUserBalance(int groupId, int userId);
    Task SettleUp(int groupId, int userId, int peerId, decimal amount);
    Task UpdateSettlement(int groupId, int expenseId, int userId, decimal amount, DateTime? date);
    Task DeleteSettlement(int groupId, int expenseId, int userId);
}