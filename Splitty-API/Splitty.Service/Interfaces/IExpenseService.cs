using Splitty.DTO.Response;
using Splitty.DTO.Internal;

namespace Splitty.Service.Interfaces;

public interface IExpenseService
{
    Task<ExpenseResponse> CreateAsync(CreateExpenseDTO dto, int userId);
    Task DeleteAsync(int groupId, int expenseId, int userId);
    Task<ExpenseResponse> UpdateAsync(UpdateExpenseDTO dto, int userId);
}