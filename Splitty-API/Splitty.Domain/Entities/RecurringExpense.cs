using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

/// <summary>
/// How often a recurring expense adds an expense. Stored as the member name, like
/// <see cref="ExpenseCategory"/> (ADR 0002). Values are append-only by name.
/// </summary>
public enum RepeatFrequency
{
    Weekly,
    Fortnightly,
    Monthly,
    Yearly
}

/// <summary>
/// What a client may ask an expense to do: <see cref="Never"/> repeat, or repeat at one of
/// the <see cref="RepeatFrequency"/> values. Request-only; nothing stores it.
/// </summary>
public enum Repeat
{
    Never,
    Weekly,
    Fortnightly,
    Monthly,
    Yearly
}

/// <summary>
/// The rule that adds an ordinary <see cref="Expense"/> to a group each time it comes due.
/// The expenses it adds copy its values and link back to it. Nothing reads this row for
/// money: balances, stats and the settlement cap read the expenses it added. See
/// docs/adr/0006-recurring-expenses-add-rows-on-group-read.md.
/// </summary>
[Table("RecurringExpense")]
public class RecurringExpense
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }

    public int GroupId { get; set; }

    public int PaidBy { get; set; }

    public decimal Amount { get; set; }

    public required string Description { get; set; }

    public ExpenseCategory Category { get; set; } = ExpenseCategory.General;

    public SplitMode SplitMode { get; set; }

    public RepeatFrequency Frequency { get; set; }

    /// <summary>
    /// The anchor every due day is computed from, as a calendar day in
    /// <see cref="TimeZone"/>. Computing from here rather than from the last expense added
    /// is what lets a monthly expense started on the 31st go 31 → 28 → 31.
    /// </summary>
    public DateOnly StartDate { get; set; }

    /// <summary>The IANA zone whose local midnight makes a day due.</summary>
    public required string TimeZone { get; set; }

    /// <summary>
    /// The due day of the last expense this added. Catch-up adds only days after it, which
    /// is why an added expense that was deleted is never added again.
    /// </summary>
    public DateOnly AddedThrough { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    [JsonIgnore]
    public virtual Group Group { get; init; } = null!;

    public virtual IList<RecurringExpenseSplit> Splits { get; set; } = new List<RecurringExpenseSplit>();
}

/// <summary>
/// One row of the split every added expense copies. Fixed: a member who joins later is not
/// in it until the recurring expense is edited.
/// </summary>
[Table("RecurringExpenseSplit")]
public class RecurringExpenseSplit
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }

    public int RecurringExpenseId { get; init; }

    public int UserId { get; init; }

    public decimal Amount { get; set; }

    /// Percent units, non-null exactly when the recurring expense is a percentage split.
    public decimal? Percentage { get; set; }

    [JsonIgnore]
    public RecurringExpense RecurringExpense { get; init; } = null!;
}
