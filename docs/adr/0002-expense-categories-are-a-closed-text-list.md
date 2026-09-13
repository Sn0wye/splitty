# Expense categories are a closed list, stored as text, defaulting to `general`

An `Expense` carries a user-chosen `Category` drawn from a fixed server-side list. The column
is `text`, `NOT NULL`, and defaults to `general` — even though the two enum columns beside it,
`ExpenseType` and `SplitMode`, are integers, and even though "the user has not chosen" is the
kind of absence a nullable column usually expresses.

Both deviations are deliberate.

## Text, not an integer

An integer enum column is only safe to append to: reordering a member or deleting one silently
relabels every stored row, and nothing fails loudly. That discipline is easy to hold over the
three values of `SplitMode`. It is not easy to hold over forty-four categories, a list whose
whole purpose is to be edited — a leaf split in two, a leaf moved under a different heading, a
leaf retired. Those are exactly the operations an ordinal punishes.

The column is mapped with `HasConversion<string>()` from a C# enum, so the DTO deserializer
still rejects an unknown token with a `400` before any handler runs, and `psql` shows
`groceries` rather than `17`. The cost is that renaming an enum *member* now orphans stored
rows — the same append-only discipline, moved from the ordinal to the name.

## `general`, not `NULL`

`UpdateExpenseRequest` is a patch: an omitted field means unchanged. With a nullable column
there is no way to say "remove the category I set by mistake" — only to replace it. Solving
that needs either a tri-state patch wrapper this codebase has nowhere else, or a write-only
sentinel token that never appears on a read.

A non-null column with `general` removes the question. Clearing a category is setting a value
like any other, every reader gets a category without a fallback expression, and `general`
claims nothing a user did not do: it is the value that means "nobody chose". This is why the
`Date ?? CreatedAt` precedent does not apply here — `Date` has a meaningful fallback to fall
back *to*, and a category does not.

## Consequences

- Category values are append-only by *name*. Renaming a member is a data migration.
- A settlement is an `Expense` row, so it cannot hold nothing either. It holds `payment`, a
  category no expense may take and the picker never offers. The settlement routes coerce any
  category to `payment`; the expense routes refuse `payment` with a `400`, matching the way
  those routes already refuse `Payment` rows.
- Because every row now has a category, the iOS expense row derives its glyph and tint from
  the category alone. The `switch expense.type` that produced them is deleted. The migration
  must therefore backfill `Payment` rows to `payment`, not to `general`, or every historic
  settlement renders as an uncategorized expense.
- The category is descriptive. No balance, invariant, or amount reads it.
