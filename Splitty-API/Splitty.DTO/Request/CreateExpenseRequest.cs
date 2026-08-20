using System.ComponentModel.DataAnnotations;
using Splitty.DTO.Internal;

namespace Splitty.DTO.Request;

public class CreateExpenseRequest
{
    public int PaidBy { get; set; }
    
    public Decimal Amount { get; set; }
    
    [Required(ErrorMessage = "Description is required")]
    public required string Description { get; set; }
    
    /// <summary>
    /// Required rather than nullable so a payload omitting it is rejected by the JSON
    /// deserializer, before any handler has to treat "absent" and "empty" the same way.
    /// </summary>
    public required List<ExpenseSplitDTO> Splits { get; set; }
}
