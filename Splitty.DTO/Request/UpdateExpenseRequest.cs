using System.ComponentModel.DataAnnotations;
using Splitty.DTO.Internal;

namespace Splitty.DTO.Request;

public class UpdateExpenseRequest
{
    public int? PaidBy { get; set; }
    
    public Decimal? Amount { get; set; }
    
    public string? Description { get; set; }
    
    public List<UpdateExpenseSplitDTO>? Splits { get; set; }
}
