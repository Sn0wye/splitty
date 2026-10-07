namespace Splitty.Service.Interfaces;

/// <summary>
/// Adds the expenses recurring expenses have come due for, and ends recurring expenses
/// whose people leave. See docs/adr/0006-recurring-expenses-add-rows-on-group-read.md.
/// </summary>
public interface IRecurringExpenseService
{
    /// <summary>
    /// Adds every expense the group's recurring expenses came due for since they last added
    /// one, saves once, and requests a recomputation if anything was added. Returns whether
    /// anything was. Runs only on the routes ADR 0006 lists: two triggers on one screen
    /// would add the same expense twice.
    /// </summary>
    Task<bool> CatchUpAsync(int groupId);

    /// <summary>
    /// <see cref="CatchUpAsync"/> without the recomputation request, for a caller that adds
    /// inside its own transaction. The caller requests it after committing: a request made
    /// before the commit carries a generation the worker cannot see yet, so it is skipped
    /// and the group stays pending.
    /// </summary>
    Task<bool> AddDueAsync(int groupId);

    /// <summary>
    /// Deletes every recurring expense in the group that <paramref name="userId"/> pays for
    /// or shares in, so nothing is billed to someone outside the group. What they already
    /// added stays, as plain expenses.
    /// </summary>
    Task EndForMemberAsync(int groupId, int userId);
}
