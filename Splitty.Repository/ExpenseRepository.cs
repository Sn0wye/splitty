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
    
    public async Task<List<Expense>> FindExpensesByGroupId(int groupId)
    {
        return await context.Expense
            .Include(e => e.Splits)
            .Include(e => e.PaidByUser)
            .Where(e => e.GroupId == groupId)
            .ToListAsync();
    }
}