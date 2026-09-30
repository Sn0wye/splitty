using Splitty.DTO.Internal;
using Splitty.DTO.Response;

namespace Splitty.Service.Interfaces;

public interface IGroupReadModel
{
    Task<List<GroupDTO>> GetGroupsByUserId(int userId);
    Task<GroupDTO?> GetGroupAsync(int groupId, int userId);
    Task<List<ExpenseResponse>> GetExpensesAsync(int groupId, int userId);
    Task<ExpenseResponse> GetExpenseAsync(int groupId, int expenseId, int userId);
    Task<bool> GroupExistsAsync(int groupId);
    Task<bool> IsMemberAsync(int groupId, int userId);
    Task<decimal> GetMemberNetAsync(int groupId, int userId);
}
