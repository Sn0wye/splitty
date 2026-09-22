# Debts are simplified

Clients receive only simplified debts, with no per-group toggle. Pairwise balances remain
internal bookkeeping. Greedy matching of the largest net debtor and creditor, breaking ties
by ascending user id, reduces payment chains with deterministic results and at most members
minus one payments. Exact minimum-transaction optimization is out of scope.

The background replay replaces the stored simplified rows after writing pairwise balances.
Reads never compute them. The summary returns `simplifiedDebts`, each with `from` and `to`
objects containing `id`, `name`, and `avatarUrl`, plus `amount`. It includes the whole group
and retains `balancesPending`. People aggregates these same debts with positive amounts
meaning the peer owes the caller. The migration marks existing groups pending; startup
queues pending groups through the existing worker to populate their simplified debts.

A settlement is capped at the smaller of the payer's net debt and the payee's net credit,
read from stored pairwise rows. Capping against a suggested pair would reject valid payments
when greedy matching changes the suggestions. Edits remove the payment's contribution from
both positions before applying the cap. Pending groups cap at zero. This remains an
eventually consistent read, so a refusal may require a refresh and retry. Payments still use
the settlement routes and two opposite splits described in ADR 0001.

Replacing `balances` is a breaking contract change. Coordinate deployment with the iOS
consumer ticket; this change does not update the client. ADR 0002 already records expense
categories, so this decision uses the next available number.
