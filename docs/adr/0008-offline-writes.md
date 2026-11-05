# Offline writes: client ids, row versions, and a delete that wins

The app is sold for trips, which is exactly when there is no network, yet every write needed
one. The iOS client now keeps each group on disk and queues expense and settlement writes
while offline, sending them when the network returns. A write sent hours later, perhaps
twice because an answer was lost, against a row another member has since changed, has to
stay correct. The server makes that possible with three columns on `Expense` and three error
codes, and the client decides the rest.

## What the server accepts

- **`ClientId`**, a UUID the client makes before sending a create or a settlement. Unique per
  group, through a partial unique index (`ClientId IS NOT NULL`). A create carrying a stored
  one answers with that row and writes nothing, so resending is always safe. The answer is
  the row as it is now, even if another member edited it since, and it is given before any
  check that might have changed since the first send (membership, currency, the settlement
  cap). Two sends racing each other are settled by the index: the loser saves nothing and
  reads the winner's row.
- **`Version`**, starting at 1 and going up by one on every edit, including the later rows a
  "this and following" edit rewrites. An edit may send `baseVersion`. If the row has moved on,
  the edit is refused with `409 version_conflict` and the current row in `expense`, so the
  client can merge without another read. `Version` is an EF concurrency token, so two edits
  racing between read and save cannot both win either.
- **`LastOpId`**, the `opId` of the last edit applied. An edit resent with the same `opId`
  answers with the row instead of refusing it as a conflict with itself.
- **`currency`** on a write, optional: the group currency the client believed it was writing
  in. Refused with `409 currency_changed` when the group has since been relabelled (ADR 0007),
  because the amounts would silently change meaning.
- `POST /settle` and the settlement edit answer with the row, like the expense routes, so the
  client can match its queued settlement by `clientId` instead of guessing.

## A delete wins

Deletion is permanent and any member may delete anything. When a delete and an edit cross,
the delete wins in both directions. A delete never sends a version, and one that loses the
concurrency race to an edit deletes the row anyway. An edit of a deleted row is a `404`.
Expense ids are never reused, so the client reads that `404` as "someone deleted this" and
offers to record its edit as a new expense, which is a new row and not a restore.

Asking the deleting member instead was considered. The question would reach them hours later,
when they no longer remember the row, and an edit made after a delete still loses.

## Why on the row and not in an idempotency table

A generic `Idempotency-Key` table written in an outer transaction around the write breaks the
group ledger. `RequestRecomputationAsync` marks the group pending and then queues its
message. Inside an uncommitted transaction, the worker can read the old generation before the
commit, skip the message as superseded, and leave the group pending until the next restart.
Writing the key after the commit instead leaves a window where a crash makes the resend look
like a conflict with itself. Columns on the row are written by the save that already exists,
so they commit or fail with the write.

## What the client does

Each signed-in user's groups, rows, last summary and queued writes are stored in SQLite (the
system `libsqlite3`, not a dependency). Writes go out in the order they were made, one at a
time. Queued writes to the same row are merged before they are sent. An edit carries the row
it was made against, so a `version_conflict` is merged by field group (money, description,
category, date) and resent on its own when the groups do not overlap. When they overlap, the
member chooses. Balances shown while writes are queued are an estimate: the server's
simplified debts give every member's net, each queued write adds its change, and the same
greedy simplification runs locally. Writes that cannot be queued safely stay online-only:
anything that repeats (a repeating expense may not start before today), group and membership
changes, invites, and profile changes.

## Consequences

- Rows written before this have no `ClientId` and start at version 1.
- There are no tombstones and no change feed yet. A client brings itself up to date by reading
  the whole group, as it did before. Delta sync is a later decision.
- The settlement cap is read from rows, not stored balances, because a client back online
  sends its expenses and then its settlement into a group that is still pending. See
  `0009-the-settlement-cap-reads-the-rows.md`.
- An edit that sends no `baseVersion` still applies to whatever is there, so older clients
  keep working unchanged.
