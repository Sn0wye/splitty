# Recurring expenses add rows on group read

A recurring expense is a rule row. Each repeat becomes an ordinary `Expense` row, added only
once it is due and only when `GET group` (or a leave or member removal) notices that it is due.
There is no timer and no virtual repeat. Replay, stats, the settlement cap, and the expense list
therefore read real rows and stay unchanged. Repeats are normal expenses that can be edited or
deleted one at a time. One row per repeat matches what manual entry would write; the waste
avoided is rows created ahead of time.

Catch-up runs on `GET group` alone because opening a group sends the group, expense, and summary
reads in parallel. If all three triggered catch-up, each due repeat would be added three times.
Two members opening the group in the same second can still double-add. No claim or lock guards
that yet: add a conditional `AddedThrough` update when it shows up as a bug.

## Considered Options

- **Timer (Splitwise).** A scheduled job adds repeats as they come due. Rejected: no scheduler
  exists, and the app does not need one.
- **Virtual repeats.** Store only the rule, and expand repeats in every money reader. Rejected:
  each reader needs expansion code, stored balances go stale without a write, rule edits need
  revisions to remember past amounts, and editing one repeat needs a skip table.

## Consequences

A group nobody opens adds nothing. When it is next opened, every repeat due since then is added,
with no limit. On that first open, the parallel expense and summary reads may miss the new
expenses until the next refresh.
