using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

public interface IBalanceService
{
    Task<List<Balance>> CalculateGroupBalances(int groupId);
    Task<List<Balance>> GetGroupUserBalance(int groupId, int userId);
    Task SettleUp(int groupId, int userId, int peerId, decimal amount);
}