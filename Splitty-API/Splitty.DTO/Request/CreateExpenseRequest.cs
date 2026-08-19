using System.ComponentModel.DataAnnotations;
using Splitty.DTO.Internal;

namespace Splitty.DTO.Request;

public class CreateExpenseRequest
{
    public int PaidBy { get; set; }
    
    public Decimal Amount { get; set; }
    
    [Required(ErrorMessage = "Description is required")]
    public required string Description { get; set; }
    
    public List<ExpenseSplitDTO>? Splits { get; set; }
}
