# The split mode is stored, and the amounts stay authoritative

Split mode — how the per-user amounts were derived — was a client-only concept: the API took
absolute amounts and stored nothing about where they came from, so reopening an expense could
not recover how it was split. The client lived with it by inferring *equal* when every stored
amount matched within a cent and *custom* otherwise. Percentage splits break that inference,
so `Expense` gains a `SplitMode` column (`equal | custom | percentage`) and `ExpenseSplit`
gains a nullable `Percentage`.

The inference cannot represent a ratio. A 70/30 percentage split and a hand-typed $70/$30
split are byte-identical once stored, so correcting a $100 total to $110 leaves $70/$30 —
failing the sum-to-total invariant — instead of re-deriving $77/$33. No heuristic over
absolute amounts recovers the intent, because the intent is not in the amounts.

**Absolute amounts remain the only money truth.** The balance replay is unchanged: it reads
split amounts and never reads the mode or the percentages. The mode is metadata for
re-editing, and the server does not check that it agrees with the amounts — an `equal`
expense whose amounts differ by more than a rounding cent is stored as sent.

## Considered options

- **Derive the mode from the data instead of storing it** — what the client does today.
  Rejected above: percentages are not recoverable from amounts.
- **Make the mode authoritative and have the server re-derive amounts from it.** Rejected
  because the server would then own the remainder-cent rule, which is a client decision
  (X4 in issue #18) precisely so that "splits sum exactly to the total" is a property the
  client can guarantee before it sends anything.

## Consequences

- Reverses X3 in issue #18 ("split computation is fully client-side, the API stores no
  mode"). The `CONTEXT.md` paragraph explaining why a mode never leaves the client is
  superseded by this ADR.
- The column is nullable in the schema but non-null for every `Type = Expense` row, enforced
  in the service rather than by a constraint, because a settlement has no split mode. Same
  arrangement `EnsurePayment` already uses for a payment's split shape. A later "fix" making
  the column `NOT NULL` breaks the settle path.
- Two invariants join `ExpenseSplitInvariants`: a `percentage` expense requires a
  `Percentage` on every split row, and those percentages must sum to exactly 100. Neither is
  checked against the amounts.
- Percentages are stored but never trusted to reproduce the amounts. A row whose percentages
  no longer re-derive to its stored amounts is possible, and the amounts win.
- The client's inference survives as the fallback for a row with a missing or unrecognised
  mode, rather than as the normal path.
