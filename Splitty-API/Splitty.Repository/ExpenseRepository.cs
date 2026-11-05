using Microsoft.EntityFrameworkCore;
using Npgsql;
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
    
    public async Task<bool> CreateOnceAsync(Expense expense)
    {
        await context.Expense.AddAsync(expense);

        try
        {
            await context.SaveChangesAsync();
            return true;
        }
        catch (DbUpdateException ex) when (ex.InnerException is PostgresException
                                           {
                                               SqlState: PostgresErrorCodes.UniqueViolation,
                                               ConstraintName: ClientIdIndex
                                           })
        {
            // A resend raced the first create and lost. Nothing of this attempt is kept.
            context.ChangeTracker.Clear();
            return false;
        }
    }

    private const string ClientIdIndex = "IX_Expense_GroupId_ClientId";

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
        await SaveOrThrowConcurrentAsync();

        return expense;
    }
    
    public async Task DeleteAsync(Expense expense)
    {
        context.Expense.Remove(expense);

        try
        {
            await context.SaveChangesAsync();
        }
        catch (DbUpdateConcurrencyException)
        {
            // An edit landed between the read and this delete. A delete wins over any edit
            // (docs/adr/0008-offline-writes.md), so the row goes whatever its version is now.
            // The splits go with it through the cascade.
            context.ChangeTracker.Clear();
            await context.Expense.Where(e => e.Id == expense.Id).ExecuteDeleteAsync();
        }
    }

    public Task<List<Expense>> GetAddedAfterAsync(int recurringExpenseId, DateTime after) =>
        context.Expense
            .Include(e => e.Splits)
            .Where(e => e.RecurringExpenseId == recurringExpenseId && (e.Date ?? e.CreatedAt) > after)
            .ToListAsync();

    public async Task SaveFollowingAsync(IEnumerable<Expense> removed, RecurringExpense? stopped)
    {
        context.Expense.RemoveRange(removed);

        // What it added before stays, unlinked by the foreign key's SET NULL.
        if (stopped is not null) context.RecurringExpense.Remove(stopped);

        await SaveOrThrowConcurrentAsync();
    }

    private async Task SaveOrThrowConcurrentAsync()
    {
        try
        {
            await context.SaveChangesAsync();
        }
        catch (DbUpdateConcurrencyException ex)
        {
            context.ChangeTracker.Clear();
            throw new ConcurrentEditException(ex);
        }
    }

    public async Task InTransactionAsync(Func<Task> work)
    {
        await using var transaction = await context.Database.BeginTransactionAsync();
        await work();
        await transaction.CommitAsync();
    }
}
