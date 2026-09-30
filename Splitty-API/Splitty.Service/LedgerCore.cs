namespace Splitty.Service;

/// <summary>What one participant's split puts on the payer's side: the payer is owed it.</summary>
public readonly record struct PairwisePosition<TMember>(TMember Payer, TMember Participant, decimal Amount);

/// <summary>One side of a pairwise balance, positive when <see cref="Peer"/> owes <see cref="User"/>.</summary>
public readonly record struct PairwiseBalance<TMember>(TMember User, TMember Peer, decimal Amount);

/// <summary>A directed amount from one debtor to one creditor.</summary>
public readonly record struct SimplifiedPayment<TMember>(TMember From, TMember To, decimal Amount);

/// <summary>
/// The group ledger's math, free of the database. Members are an opaque identity the caller
/// picks — user ids in the API, emails in the seeder — ordered by their default comparer,
/// which is what simplification breaks ties on.
/// </summary>
public static class LedgerCore
{
    /// <summary>
    /// Every debt stored twice, once from each side with opposite signs, ordered by user then
    /// peer. A position whose payer is its own participant owes nothing and is dropped; split
    /// amounts count by magnitude, so a settlement's negative payee split pays down its debt.
    /// </summary>
    public static IReadOnlyList<PairwiseBalance<TMember>> Balances<TMember>(
        IEnumerable<PairwisePosition<TMember>> positions) where TMember : notnull
    {
        var comparer = EqualityComparer<TMember>.Default;
        var amounts = new Dictionary<(TMember User, TMember Peer), decimal>();

        foreach (var position in positions)
        {
            if (comparer.Equals(position.Payer, position.Participant)) continue;

            var amount = Math.Abs(position.Amount);
            var owed = (position.Payer, position.Participant);
            var owing = (position.Participant, position.Payer);
            amounts[owed] = amounts.GetValueOrDefault(owed) + amount;
            amounts[owing] = amounts.GetValueOrDefault(owing) - amount;
        }

        return amounts
            .Select(pair => new PairwiseBalance<TMember>(pair.Key.User, pair.Key.Peer, pair.Value))
            .OrderBy(balance => balance.User)
            .ThenBy(balance => balance.Peer)
            .ToList();
    }

    /// <summary>Each member's net position: what the group owes them, negative when they owe.</summary>
    public static IReadOnlyDictionary<TMember, decimal> Nets<TMember>(
        IEnumerable<PairwiseBalance<TMember>> balances) where TMember : notnull =>
        balances
            .GroupBy(balance => balance.User)
            .ToDictionary(members => members.Key, members => members.Sum(balance => balance.Amount));

    /// <summary>
    /// Greedy matching of the largest net debtor and the largest net creditor, ties broken by
    /// member, repeated until one side runs out. At most members minus one payments; a settled
    /// group has none. See docs/adr/0003-debts-are-simplified.md.
    /// </summary>
    public static IReadOnlyList<SimplifiedPayment<TMember>> Simplify<TMember>(
        IReadOnlyDictionary<TMember, decimal> nets) where TMember : notnull
    {
        var remaining = nets.ToDictionary();
        var payments = new List<SimplifiedPayment<TMember>>();

        while (true)
        {
            var debtors = remaining.Where(n => n.Value < 0).OrderBy(n => n.Value).ThenBy(n => n.Key).ToList();
            var creditors = remaining.Where(n => n.Value > 0).OrderByDescending(n => n.Value).ThenBy(n => n.Key).ToList();
            if (debtors.Count == 0 || creditors.Count == 0) break;

            var (debtor, debt) = debtors[0];
            var (creditor, credit) = creditors[0];
            var amount = Math.Min(-debt, credit);
            payments.Add(new SimplifiedPayment<TMember>(debtor, creditor, amount));
            remaining[debtor] += amount;
            remaining[creditor] -= amount;
        }

        return payments;
    }

    /// <summary>
    /// The most <paramref name="payer"/> may settle with <paramref name="payee"/>: the smaller
    /// of the payer's net debt and the payee's net credit (invariant 5). Excluding an existing
    /// payment restores the payer's debt and the payee's credit it paid down, so re-saving it
    /// is measured against the debt it was recorded for.
    /// </summary>
    public static decimal Cap<TMember>(
        IReadOnlyDictionary<TMember, decimal> nets,
        TMember payer,
        TMember payee,
        decimal excluding = 0m) where TMember : notnull
    {
        var payerNet = nets.GetValueOrDefault(payer) - excluding;
        var payeeNet = nets.GetValueOrDefault(payee) + excluding;
        return Math.Min(Math.Max(0m, -payerNet), Math.Max(0m, payeeNet));
    }
}
