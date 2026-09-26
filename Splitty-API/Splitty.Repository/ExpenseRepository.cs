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

    public async Task<Expense?> FindByIdAsync(int id)
    {
        return await context.Expense
            .Include(e => e.PaidByUser)
            .Include(e => e.Splits)
            .ThenInclude(es => es.User)
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

    /// Newest first by the date the user gave, falling back to the audit timestamp for rows
    /// written before the column existed. The client groups by the same expression.
    public async Task<List<Expense>> FindExpensesByGroupId(int groupId)
    {
        return await context.Expense
            .Include(e => e.Splits)
            .ThenInclude(es => es.User)
            .Include(e => e.PaidByUser)
            .Where(e => e.GroupId == groupId)
            .OrderByDescending(e => e.Date ?? e.CreatedAt)
            .ThenByDescending(e => e.Id)
            .ToListAsync();
    }

    /// <summary>
    /// The group's <see cref="ExpenseType.Expense"/> rows whose <c>Date ?? CreatedAt</c> falls
    /// in <c>[from, to)</c>, with their splits. A null bound leaves that end open. Settlements
    /// are left out: paying someone back is not spending.
    /// </summary>
    public async Task<List<Expense>> FindExpensesInRangeAsync(int groupId, DateTime? from, DateTime? to)
    {
        return await context.Expense
            .AsNoTracking()
            .Include(e => e.Splits)
            .Where(e => e.GroupId == groupId && e.Type == ExpenseType.Expense)
            .Where(e => from == null || (e.Date ?? e.CreatedAt) >= from)
            .Where(e => to == null || (e.Date ?? e.CreatedAt) < to)
            .ToListAsync();
    }
}
