using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IRecurringExpenseRepository
{
    /// <summary>
    /// The group's recurring expenses with their splits, tracked, so catch-up can advance
    /// <see cref="RecurringExpense.AddedThrough"/> and save it with what it added.
    /// </summary>
    Task<List<RecurringExpense>> GetByGroupAsync(int groupId);

    /// Tracked, with splits.
    Task<RecurringExpense?> GetForUpdateAsync(int id);

    /// Inserts <paramref name="added"/> and every tracked change to the recurring expenses
    /// that added them, in one save.
    Task SaveCatchUpAsync(List<Expense> added);

    /// Deletes every recurring expense in the group that <paramref name="userId"/> pays for
    /// or shares in.
    Task DeleteForMemberAsync(int groupId, int userId);
}
