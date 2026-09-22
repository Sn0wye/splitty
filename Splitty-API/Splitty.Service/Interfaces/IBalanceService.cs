using Splitty.Domain.Entities;
using Splitty.DTO.Response;

namespace Splitty.Service.Interfaces;

public interface IBalanceService
{
    Task<List<Balance>> CalculateGroupBalances(int groupId);
    Task<List<SimplifiedDebtResponse>> GetGroupSimplifiedDebts(int groupId, int userId);
    Task SettleUp(int groupId, int userId, int peerId, decimal amount, DateTime? date);
    Task UpdateSettlement(int groupId, int expenseId, int userId, decimal amount, DateTime? date);
    Task DeleteSettlement(int groupId, int expenseId, int userId);
}