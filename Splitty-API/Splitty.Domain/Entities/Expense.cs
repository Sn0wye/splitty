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
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    
    [JsonIgnore]
    public virtual Group Group { get; init; }
    
    public virtual User PaidByUser { get; init; }
    
    public virtual IList<ExpenseSplit> Splits { get; set; } = new List<ExpenseSplit>();
}