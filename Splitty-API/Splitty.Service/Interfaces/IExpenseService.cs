using Splitty.Domain.Entities;
using Splitty.DTO.Internal;

namespace Splitty.Service.Interfaces;

public interface IExpenseService
{
    Task<Expense> CreateAsync(CreateExpenseDTO dto);
    Task<Expense?> FindByIdAsync(int id);
    // Task<Expense> UpdateAsync(Expense expense); 
    Task<List<Expense>> FindExpensesByGroupId(int groupId, int userId);
    Task<Expense> UpdateAsync(UpdateExpenseDTO dto);
}