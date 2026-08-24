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

    /// <summary>
    /// The share this row was said to be, in percent units (<c>70.00</c>). Non-null on
    /// every row of a <see cref="SplitMode.Percentage"/> expense and null everywhere else,
    /// including on settlements. Never used to compute <see cref="Amount"/>.
    /// </summary>
    public Decimal? Percentage { get; set; }
    
    [JsonIgnore]
    public Expense Expense { get; init; }
    
    // [JsonIgnore]
    public User User { get; init; }
}