# Any member records a payment, in either direction

`POST /group/{groupId}/settle` used to record only the caller paying a peer, so a member who
was paid in cash or by Pix had to wait for the payer to open the app. It now also takes
`fromUserId` and `toUserId`: any member records one member paying another. The app offers
the two sides, "I paid" to a net debtor and "I was paid" to a net creditor, from the same
Balances row and settle-up sheet, with no extra step.

The caller does not have to be the payer or the payee. Membership is the only authorization
boundary (invariant 2), and any member could already edit the amount of any payment or delete
it. Requiring the caller to be a party would add a rule to document and test that protects
nothing. The payment's own payer and payee drive everything that follows, never the caller:
the cap of invariant 5 is the same `SettlementCapAsync(payer, payee)` read, and an edit reads
both sides off the stored row as before.

There is no counterparty confirmation, no record of who entered a payment, and no activity
feed. Splitty trusts its members: a wrong payment shows in the timeline, and anyone can edit
or delete it.

## Consequences

- `withUserId` alone still means the caller paid, so clients built before this change keep
  working. A body that sends both shapes, or only one of `fromUserId` and `toUserId`, is a
  `400`. No migration: a payment row already stored both sides.
- Both sides are checked by membership row, not liveness, so a tombstone can be either one.
  A creditor can now clear a debt a deleted member left behind, which nobody could record
  before, and then remove the tombstone through the zero-balance route.
- Both sides can record the same real-world payment. Recorded one after the other in full,
  the second is refused: the cap reads the rows the first one wrote (ADR 0009). Each client
  sends its own `clientId`, so offline dedup does not merge them. A partial payment recorded
  twice is not caught. It stays a trust problem: it shows in the timeline and any member
  deletes it.
- ADR 0001 is unchanged: payments still have their own routes.
