# Settlements are mutated through their own routes, not the expense routes

A settlement is stored as an `Expense` with `Type = Payment`, so the obvious move is to let
the expense `PUT`/`DELETE` routes handle both row types and branch on `Type`. We decided
against it: settlements get `PUT`/`DELETE /group/{groupId}/settlements/{expenseId}`, and the
expense `PUT` and `DELETE` routes refuse `Payment` rows outright.

Sharing a route would mean the same request shape behaves under different rules depending on
a field the client never sent — the settlement cap applies, splits are rebuilt from `Amount`
rather than accepted, and `EnsurePayment` replaces `EnsureExpense`. Splitting the routes
keeps one delete path per row type and keeps the cap somewhere a reader can find it.

## Consequences

- The expense `PUT` route refused nothing before this and would happily edit a settlement's
  amount, which is a way around the cap. It refuses `Payment` rows now, for the same reason
  the delete does.
- The cap re-check on a settlement edit must exclude the settlement's own contribution to the
  pairwise balance, or every edit fails against a balance that already counts it.
- `ExpenseSplitInvariants.EnsurePayment` previously asserted only "two splits, opposite sign,
  nonzero" and never that they matched `Amount`. Because the balance replay reads splits and
  ignores `Expense.Amount`, an amount-only edit would have changed the displayed number and
  moved no money. Tightened to assert `splits == [+Amount, -Amount]` as part of this work.
