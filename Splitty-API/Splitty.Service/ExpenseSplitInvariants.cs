using Splitty.Domain.Entities;

namespace Splitty.Service;

/// <summary>
/// The split shape each expense type is allowed to have. Scoped by type because the two
/// types are built from opposite directions: an <see cref="ExpenseType.Expense"/> carries
/// client-supplied splits and is validated as input, while an <see cref="ExpenseType.Payment"/>
/// is constructed internally by the settle path and is asserted, never accepted from a client.
/// </summary>
internal static class ExpenseSplitInvariants
{
    public static void Ensure(ExpenseType type, decimal amount, IEnumerable<decimal>? splitAmounts)
    {
        var splits = splitAmounts?.ToList();

        switch (type)
        {
            case ExpenseType.Expense:
                EnsureExpense(amount, splits);
                break;
            case ExpenseType.Payment:
                EnsurePayment(amount, splits);
                break;
        }
    }

    private static void EnsureExpense(decimal amount, List<decimal>? splits)
    {
        if (splits is null || splits.Count == 0)
        {
            throw new ArgumentException("An expense must have at least one split.");
        }

        if (amount <= 0)
        {
            throw new ArgumentException("Expense amount must be greater than zero.");
        }

        if (splits.Any(split => split <= 0))
        {
            throw new ArgumentException("Expense splits must be greater than zero.");
        }

        if (splits.Sum() != amount)
        {
            throw new ArgumentException("Expense splits must sum to the total.");
        }
    }

    /// <summary>
    /// A payment moves one amount between exactly two people, so its splits are exactly
    /// <c>[+Amount, -Amount]</c>. Checking them against <see cref="Expense.Amount"/> and not
    /// only against each other is what stops an amount-only edit from changing the number
    /// users read while moving no money: the balance replay reads the splits and never
    /// reads <c>Amount</c>. Violating this means the settle path built the expense wrong,
    /// which is why it throws rather than reporting a validation failure.
    /// </summary>
    private static void EnsurePayment(decimal amount, List<decimal>? splits)
    {
        if (splits is null || splits.Count != 2)
        {
            throw new InvalidOperationException("A payment must have exactly two splits.");
        }

        if (amount <= 0)
        {
            throw new InvalidOperationException("A payment's amount must be greater than zero.");
        }

        if (splits[0] + splits[1] != 0)
        {
            throw new InvalidOperationException(
                "A payment's splits must be equal in magnitude and opposite in sign.");
        }

        if (Math.Abs(splits[0]) != amount)
        {
            throw new InvalidOperationException(
                "A payment's splits must match its amount.");
        }
    }
}
