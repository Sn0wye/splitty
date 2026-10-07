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

    public Task<List<Expense>> GetAddedAfterAsync(int recurringExpenseId, DateTime after) =>
        context.Expense
            .Include(e => e.Splits)
            .Where(e => e.RecurringExpenseId == recurringExpenseId && (e.Date ?? e.CreatedAt) > after)
            .ToListAsync();

    public Task<List<Expense>> GetAddedAsync(int recurringExpenseId) =>
        context.Expense.Where(e => e.RecurringExpenseId == recurringExpenseId).ToListAsync();

    public async Task SaveFollowingAsync(IEnumerable<Expense> removed, RecurringExpense? stopped)
    {
        context.Expense.RemoveRange(removed);

        // What it added before stays, unlinked by the foreign key's SET NULL.
        if (stopped is not null) context.RecurringExpense.Remove(stopped);

        await context.SaveChangesAsync();
    }

    public async Task InTransactionAsync(Func<Task> work)
    {
        await using var transaction = await context.Database.BeginTransactionAsync();
        await work();
        await transaction.CommitAsync();
    }
}
