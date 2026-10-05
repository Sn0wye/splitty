# Account closure: deactivate, or tombstone the user

App Store Guideline 5.1.1(v) requires in-app account deletion. We follow Splitwise: a
reversible **deactivate** (`POST /profile/deactivate`) and an immediate, irreversible
**delete** (`DELETE /profile`). Deactivation ends every session and changes nothing else;
signing in again restores the same user. Deletion rewrites the `User` row as a `[removed]`
tombstone and removes the personal data. Shared expense history stays visible without the
user's name, email or picture, as Splitwise does.

A hard delete is impossible. `Expense.PaidBy` is a `Restrict` foreign key, so Postgres
refuses it for anyone who ever paid. `ExpenseSplit.UserId` cascades, so a participant's
expenses would be left with splits that no longer sum to their totals. Either way a member
with a nonzero balance disappearing breaks invariant 1.

There is no "settle up first" gate. Settling is always caller-as-debtor, and no route records
that someone paid *you*, so a creditor could never zero their own balance and would be
unable to delete. Apple also forbids holding deletion hostage.

Unsettled memberships are kept on the tombstone so the group still sums to zero and
debtors can still pay it. Settled memberships, outside pending groups, are dropped. A
tombstone is not a member for any purpose except carrying that balance.

Tokens are revoked by a per-request lookup of the user, which is cheap at this scale and
needs no refresh tokens. The lookup alone covers deletion, and deactivation while it
lasts. Reactivation clears `DeactivatedAt`, though, and would bring the old tokens back to
life on a lost phone. So the user carries a `TokenVersion`, issued as a claim and bumped
on deactivation, and the same lookup compares it.

## Consequences

- Signing in after deletion creates a fresh, empty user: the `OAuthAccount` rows are gone
  and the email unique index is filtered to `DeletedAt IS NULL`.
- Historical expenses that include a tombstone cannot be edited unless it is removed from
  them, the same as with departed members.
- Avatar objects are deleted after the commit, best effort. A failure leaves litter, not a
  half-deleted account.
- Every authenticated request now costs one primary-key lookup.
