using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

public enum ExpenseType
{
    Expense,
    Payment
}

/// <summary>
/// How the user said an expense should be divided. Descriptive, not authoritative: the
/// split amounts are the only money truth and are never re-derived from the mode, so a
/// client is free to place a remainder cent wherever it likes.
/// </summary>
public enum SplitMode
{
    Equal,
    Custom,
    Percentage
}

[Table("Expense")]
public class Expense
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    
    public int GroupId { get; set; }
    
    public int PaidBy { get; set; }
    
    public Decimal Amount { get; set; }
    
    public required string Description { get; set; }

    public ExpenseType Type { get; set; } = ExpenseType.Expense;

    /// <summary>
    /// Nullable in the schema because a settlement has no split mode, but non-null for
    /// every <see cref="ExpenseType.Expense"/> row — the service is what holds that line.
    /// Making the column <c>NOT NULL</c> would break the settle path.
    /// </summary>
    public SplitMode? SplitMode { get; set; }

    /// <summary>
    /// What the expense was for. Non-null with <see cref="ExpenseCategory.General"/> as the
    /// value meaning "nobody chose", so clearing a category is an ordinary write and every
    /// reader gets one without a fallback. A settlement holds
    /// <see cref="ExpenseCategory.Payment"/>. Descriptive: no amount or balance reads it.
    /// </summary>
    public ExpenseCategory Category { get; set; } = ExpenseCategory.General;

    /// <summary>
    /// When the expense happened, as the user says it did. Nullable because rows written
    /// before the column existed have no user-supplied date; readers fall back to
    /// <see cref="CreatedAt"/>. Future dates are allowed.
    /// </summary>
    public DateTime? Date { get; set; }

    /// <summary>
    /// The recurring expense that added this one, if any. Nulled when the recurring
    /// expense is deleted, which turns what it left behind into plain expenses.
    /// </summary>
    public int? RecurringExpenseId { get; set; }

    /// <summary>
    /// The id the creating client gave this row before the server saw it, unique within the
    /// group. A create that carries one already stored answers with that row instead of
    /// adding a second, so a client may resend a create whose answer it never received.
    /// Null for rows written without one, and for rows a recurring expense added.
    /// See docs/adr/0008-offline-writes.md.
    /// </summary>
    public Guid? ClientId { get; set; }

    /// <summary>
    /// Starts at 1 and goes up by one on every edit. An edit that names the version it was
    /// made against is refused when the row has moved on, so a stale client cannot silently
    /// overwrite a newer edit. A concurrency token, so two edits racing between read and save
    /// cannot both win either.
    /// </summary>
    [ConcurrencyCheck]
    public int Version { get; set; } = 1;

    /// <summary>
    /// The operation id of the last edit applied. An edit resent with the same id after it
    /// succeeded answers with the row as it is, rather than as a conflict with itself.
    /// </summary>
    public Guid? LastOpId { get; set; }

    /// <summary>Audit timestamp, server-set, never client-supplied.</summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    
    [JsonIgnore]
    public virtual Group Group { get; init; } = null!;
    
    public virtual User PaidByUser { get; init; } = null!;

    [JsonIgnore]
    public virtual RecurringExpense? RecurringExpense { get; set; }

    public virtual IList<ExpenseSplit> Splits { get; set; } = new List<ExpenseSplit>();
}