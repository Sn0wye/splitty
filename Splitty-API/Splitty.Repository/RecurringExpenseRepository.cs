using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class RecurringExpenseRepository(ApplicationDbContext context) : IRecurringExpenseRepository
{
    public Task<List<RecurringExpense>> GetByGroupAsync(int groupId) =>
        context.RecurringExpense
            .Include(r => r.Splits)
            .Where(r => r.GroupId == groupId)
            .ToListAsync();

    public Task<RecurringExpense?> GetForUpdateAsync(int id) =>
        context.RecurringExpense
            .Include(r => r.Splits)
            .FirstOrDefaultAsync(r => r.Id == id);

    public async Task SaveCatchUpAsync(List<Expense> added)
    {
        await context.Expense.AddRangeAsync(added);
        await context.SaveChangesAsync();
    }

    public Task DeleteForMemberAsync(int groupId, int userId) =>
        context.RecurringExpense
            .Where(r => r.GroupId == groupId
                && (r.PaidBy == userId || r.Splits.Any(s => s.UserId == userId)))
            .ExecuteDeleteAsync();
}
