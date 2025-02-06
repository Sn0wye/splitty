using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

[Table("ExpenseSplit")]
public class ExpenseSplit
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    
    public int ExpenseId { get; init; }
    
    public int UserId { get; init; }
    
    public Decimal Amount { get; set; }
    
    [JsonIgnore]
    public Expense Expense { get; init; }
    
    // [JsonIgnore]
    public User User { get; init; }
}