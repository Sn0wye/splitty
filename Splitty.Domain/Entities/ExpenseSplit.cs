using System.ComponentModel.DataAnnotations.Schema;

namespace Splitty.Domain.Entities;

[Table("ExpenseSplit")]
public class ExpenseSplit
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    
    public int ExpenseId { get; init; }
    
    public int UserId { get; init; }
    
    public Decimal Amount { get; set; }
    
    public required Expense Expense { get; init; }
    
    public required User User { get; init; }
}