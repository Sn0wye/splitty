using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class ExpenseRepository(ApplicationDbContext context): IExpenseRepository
{
    public async Task<Expense> CreateAsync(Expense expense)
    {
        await context.Expense.AddRangeAsync(expense);
        await context.SaveChangesAsync();

        return expense;
    }
    
    public async Task<List<Expense>> CreateExpenses(List<Expense> expenses)
    {
        await context.Expense.AddRangeAsync(expenses);
        await context.SaveChangesAsync();

        return expenses;
    }

    public async Task<Expense?> GetForUpdateAsync(int id)
    {
        return await context.Expense
            .Include(e => e.Splits)
            .FirstOrDefaultAsync(e => e.Id == id);
    }

    public async Task<Expense> UpdateAsync(Expense expense)
    {
        context.Expense.Update(expense);
        await context.SaveChangesAsync();

        return expense;
    }
    
    public async Task DeleteAsync(Expense expense)
    {
        context.Expense.Remove(expense);
        await context.SaveChangesAsync();
    }
}
