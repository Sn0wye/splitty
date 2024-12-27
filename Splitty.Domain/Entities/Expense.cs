using System.ComponentModel.DataAnnotations.Schema;

namespace Splitty.Domain.Entities;

[Table("Expense")]
public class Expense
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    
    public int GroupId { get; set; }
    
    public int PaidBy { get; set; }
    
    public Decimal Amount { get; set; }
    
    public string Description { get; set; }
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    
    public virtual Group Group { get; init; }
    
    public virtual User PaidByUser { get; init; }
}