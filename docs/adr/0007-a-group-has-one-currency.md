# A group has one currency, from a closed list, and amounts are never converted

A `Group` carries a `Currency` drawn from a fixed server-side list: `USD`, `CAD`, `AUD`, `MXN`,
`GBP`, `BRL`, `EUR`, `CHF`. Every amount in the group, whether an expense, split, settlement,
recurring expense or balance, is in that currency. None of those rows stores a currency of its
own. The column is `text`, `NOT NULL`, and defaults to `USD`.

## One currency per group, not per expense

Splitting a bill only works when every share is in the same unit. A per-expense currency would
put conversion inside the debt simplification, the split invariants and every balance read.
Each of those would need a rate source, a rate date and a rounding rule. A trip abroad is a
second group, not a second currency inside one.

## Changing the currency relabels, it does not convert

A member can change a group's currency at any time. The stored numbers stay exactly as they are:
`42.50 USD` becomes `42.50 BRL`. The common reason to change it is that the group was created
with the wrong one, and in that case relabelling is the correct fix. Converting would need a rate
nobody in the group agreed on, and would leave amounts that no receipt shows. The client warns
before the change that nothing is converted.

## A closed list of currencies with two decimal places

Every listed currency has two minor-unit digits. The cent arithmetic on the client, the
`decimal(18,2)` columns, and the rule that splits sum exactly to the total all assume two digits.
A currency with zero digits (`JPY`, `CLP`) or three (`KWD`) would need all of those reworked.
Splitting ¥1000 three ways into ¥333.33 is not a split anyone can pay. The list follows the
languages the app ships in. Adding a two-digit currency is a one-line change. Adding one with a
different number of digits is not.

Like `ExpenseCategory` (ADR 0002), the column stores the member name through
`HasConversion<string>()`. On the wire the value is the uppercase ISO 4217 code, so the DTO
deserializer rejects an unlisted code with a `400` before any handler runs.

## Consequences

- No query may sum amounts across groups unless it buckets them by currency. The groups list
  totals each currency separately and colours each line by direction. The People screen still
  sums across groups. It predates this decision and is due to be removed.
- The client formats each currency from its own fixed table: symbol, symbol position, spacing,
  and separators. `R$ 1.234,50` reads the same whatever the app language, because the format
  belongs to the money, not to the reader. The decimal key on the expense keypad shows that
  currency's separator, and the typed text still stores a `.`.
- Existing groups were backfilled to `USD`, which is what they displayed before the column
  existed.
- Currency values are append-only by name. Renaming a member is a data migration.
