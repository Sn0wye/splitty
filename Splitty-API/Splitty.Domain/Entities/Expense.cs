using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

public enum ExpenseType
{
    Expense,
    Payment
}

[Table("Expense")]
public class Expense
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    
    public int GroupId { get; set; }
    
    public int PaidBy { get; set; }
    
    public Decimal Amount { get; set; }
    
    public string Description { get; set; }

    public ExpenseType Type { get; set; } = ExpenseType.Expense;

    /// <summary>
    /// When the expense happened, as the user says it did. Nullable because rows written
    /// before the column existed have no user-supplied date; readers fall back to
    /// <see cref="CreatedAt"/>. Future dates are allowed.
    /// </summary>
    public DateTime? Date { get; set; }

    /// <summary>Audit timestamp, server-set, never client-supplied.</summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    
    [JsonIgnore]
    public virtual Group Group { get; init; }
    
    public virtual User PaidByUser { get; init; }
    
    public virtual IList<ExpenseSplit> Splits { get; set; } = new List<ExpenseSplit>();
}