using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IExpenseRepository
{
    Task<Expense> CreateAsync(Expense expense);
    Task<Expense?> FindByIdAsync(int id);
    Task<Expense> UpdateAsync(Expense expense);
    Task<List<Expense>> FindExpensesByGroupId(int groupId);
}