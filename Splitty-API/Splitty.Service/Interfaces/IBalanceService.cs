using Splitty.Domain.Entities;
using Splitty.DTO.Response;

namespace Splitty.Service.Interfaces;

public interface IBalanceService
{
    Task<List<SimplifiedDebtResponse>> GetGroupSimplifiedDebts(int groupId, int userId);
    Task<ExpenseResponse> SettleUp(
        int groupId,
        int userId,
        int peerId,
        decimal amount,
        DateTime? date,
        Guid? clientId = null,
        Currency? currency = null);

    Task<ExpenseResponse> UpdateSettlement(
        int groupId,
        int expenseId,
        int userId,
        decimal amount,
        DateTime? date,
        int? baseVersion = null,
        Guid? opId = null,
        Currency? currency = null);
    Task DeleteSettlement(int groupId, int expenseId, int userId);
}