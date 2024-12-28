using System.ComponentModel.DataAnnotations;
using Splitty.DTO.Internal;

namespace Splitty.DTO.Request;

public class CreateExpenseRequest
{
    [Required(ErrorMessage = "Paid By is required")]
    public int PaidBy { get; set; }
    
    [Required(ErrorMessage = "Amount is required")]
    public Decimal Amount { get; set; }
    
    [Required(ErrorMessage = "Description is required")]
    public required string Description { get; set; }
    
    public required List<ExpenseSplitDTO> Splits { get; set; }
}
