using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IExpenseRepository
{
    Task<Expense> CreateAsync(Expense expense);

    /// <summary>
    /// Saves <paramref name="expense"/>, or returns false and saves nothing when the group
    /// already stores a row under its client id: a resent create lost a race to its first send.
    /// </summary>
    Task<bool> CreateOnceAsync(Expense expense);
    Task<List<Expense>> CreateExpenses(List<Expense> expenses);
    Task<Expense?> GetForUpdateAsync(int id);
    /// Throws <see cref="ConcurrentEditException"/> when the row's version moved since it was read.
    Task<Expense> UpdateAsync(Expense expense);

    /// Deletes the row even when an edit landed after it was read: a delete wins.
    Task DeleteAsync(Expense expense);

    /// <summary>
    /// The expenses <paramref name="recurringExpenseId"/> added that are dated after
    /// <paramref name="after"/>, tracked, with their splits.
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
