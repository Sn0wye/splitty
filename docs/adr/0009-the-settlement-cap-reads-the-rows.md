# The settlement cap reads the money rows

Invariant 5 caps a settlement at the smaller of the payer's net debt and the payee's net
credit. ADR 0003 read both from the stored pairwise balances, and a group whose balances
were pending capped at zero, refusing every settlement with a retryable `400` until the
worker caught up.

Offline writes (ADR 0008) turn that edge case into the common one. A client back online
sends its queued expenses and then its settlement, so the settlement nearly always lands on a
group that its own expenses just marked pending. Members online saw it too, whenever they
settled right after someone added an expense.

The cap now reads the group's money rows with the same aggregate query the replay uses
(`GetPositionsAsync`), and the same `LedgerCore` math: `Balances`, `Nets`, `Cap`. Pending no
longer matters. The stored balances still serve every read, and the replay is still the only
thing that writes them. This read writes nothing, so invariant 4 holds.

## Consequences

- An over-cap settlement is `400 settlement_exceeds_cap`, carrying the current `cap`, so a
  client can offer the largest amount it may record.
- The cap costs one aggregate query per settlement, grouped by pairs of members rather than
  by the group's history.
- Two settlements racing between their cap reads and their saves can still both pass, the
  same window as before. A settlement saved earlier is already in the rows the next one
  reads, where before the next one was refused for the pending flag.
- `ILedgerRepository.GetBalancesAsync` had no other caller and is removed.
