using Splitty.Domain.Entities;

namespace Splitty.Service;

/// <summary>
/// One split row as the invariants read it: the money, and the percentage the user said
/// that money was. The two travel together because the percentage rules are scoped by the
/// expense's mode and have to be checked against the same rows the amounts are.
/// </summary>
internal readonly record struct SplitShape(decimal Amount, decimal? Percentage);

/// <summary>
/// The split shape each expense type is allowed to have. Scoped by type because the two
/// types are built from opposite directions: an <see cref="ExpenseType.Expense"/> carries
/// client-supplied splits and is validated as input, while an <see cref="ExpenseType.Payment"/>
/// is constructed internally by the settle path and is asserted, never accepted from a client.
/// </summary>
internal static class ExpenseSplitInvariants
{
    public static void Ensure(
        ExpenseType type,
        SplitMode? mode,
        decimal amount,
        IEnumerable<SplitShape>? splitShapes)
    {
        var splits = splitShapes?.ToList();

        switch (type)
        {
            case ExpenseType.Expense:
                EnsureExpense(mode, amount, splits);
                break;
            case ExpenseType.Payment:
                EnsurePayment(mode, amount, splits);
                break;
        }
    }

    private static void EnsureExpense(SplitMode? mode, decimal amount, List<SplitShape>? splits)
    {
        if (splits is null || splits.Count == 0)
        {
            throw new ArgumentException("An expense must have at least one split.");
        }

        if (amount <= 0)
        {
            throw new ArgumentException("Expense amount must be greater than zero.");
        }

        if (splits.Any(split => split.Amount <= 0))
        {
            throw new ArgumentException("Expense splits must be greater than zero.");
        }

        if (splits.Sum(split => split.Amount) != amount)
        {
            throw new ArgumentException("Expense splits must sum to the total.");
        }

        if (mode is null)
        {
            throw new ArgumentException("An expense must have a split mode.");
        }

        // Deliberately not checked against the amounts. The mode says how the user divided
        // the bill, not what the division has to come out to: re-deriving amounts from
        // percentages here would move the remainder cent onto the server and break every
        // client that already placed it.
        if (mode is SplitMode.Percentage)
        {
            if (splits.Any(split => split.Percentage is null))
            {
                throw new ArgumentException(
                    "A percentage expense must have a percentage on every split.");
            }

            if (splits.Sum(split => split.Percentage!.Value) != 100m)
            {
                throw new ArgumentException("Expense split percentages must sum to 100.");
            }
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
    private static void EnsurePayment(SplitMode? mode, decimal amount, List<SplitShape>? splits)
    {
        if (splits is null || splits.Count != 2)
        {
            throw new InvalidOperationException("A payment must have exactly two splits.");
        }

        if (mode is not null)
        {
            throw new InvalidOperationException("A payment must not have a split mode.");
        }

        if (amount <= 0)
        {
            throw new InvalidOperationException("A payment's amount must be greater than zero.");
        }

        if (splits[0].Amount + splits[1].Amount != 0)
        {
            throw new InvalidOperationException(
                "A payment's splits must be equal in magnitude and opposite in sign.");
        }

        if (Math.Abs(splits[0].Amount) != amount)
        {
            throw new InvalidOperationException(
                "A payment's splits must match its amount.");
        }
    }
}
