using Splitty.Domain.Entities;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

/// <summary>
/// The checks a client that writes offline relies on: a resent create finds the row its
/// first send made, and a write made against a currency the group no longer has is refused
/// rather than relabelled. See docs/adr/0008-offline-writes.md.
/// </summary>
internal static class ClientWrites
{
    /// <summary>
    /// The id of the row the group already stores under <paramref name="clientId"/>, or null.
    /// A client id that names a row of the other type is a client bug, so it is refused.
    /// </summary>
    public static async Task<int?> ExistingAsync(
        IGroupReadModel readModel,
        int groupId,
        Guid? clientId,
        ExpenseType type)
    {
        if (clientId is not { } id) return null;

        if (await readModel.FindByClientIdAsync(groupId, id) is not { } row) return null;

        if (row.Type != type)
        {
            throw new ArgumentException(type == ExpenseType.Payment
                ? "This clientId already names an expense, not a settlement."
                : "This clientId already names a settlement, not an expense.");
        }

        return row.Id;
    }

    public static async Task EnsureCurrencyAsync(IGroupReadModel readModel, int groupId, Currency? expected)
    {
        if (expected is not { } currency) return;

        var current = await readModel.GetCurrencyAsync(groupId);

        if (current != currency) throw RefusalException.CurrencyChanged(current);
    }
}
