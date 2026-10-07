using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IExpenseRepository
{
    Task<Expense> CreateAsync(Expense expense);
    Task<List<Expense>> CreateExpenses(List<Expense> expenses);
    Task<Expense?> GetForUpdateAsync(int id);
    Task<Expense> UpdateAsync(Expense expense);
    Task DeleteAsync(Expense expense);

    /// <summary>
    /// The expenses <paramref name="recurringExpenseId"/> added that are dated after
    /// <paramref name="after"/>, tracked.
    /// </summary>
    Task<List<Expense>> GetAddedAfterAsync(int recurringExpenseId, DateTime after);

    /// <summary>
    /// Deletes <paramref name="removed"/> and <paramref name="stopped"/>, and saves every other
    /// tracked change, in one save. A "this and following" edit or delete is one write.
    /// </summary>
    Task SaveFollowingAsync(IEnumerable<Expense> removed, RecurringExpense? stopped);

    /// Runs <paramref name="work"/> in one transaction: every save it makes commits or none does.
    Task InTransactionAsync(Func<Task> work);
}
