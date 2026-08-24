using System.ComponentModel.DataAnnotations;
using Splitty.Domain.Entities;
using Splitty.DTO.Internal;

namespace Splitty.DTO.Request;

public class UpdateExpenseRequest
{
    public int? PaidBy { get; set; }
    
    public Decimal? Amount { get; set; }
    
    public string? Description { get; set; }
    
    public DateTime? Date { get; set; }
    
    /// <summary>
    /// Omitted means unchanged, except that an update supplying <see cref="Splits"/> must
    /// supply this too — the rows and the mode describing them are one fact, and letting
    /// half of it move would leave the other half lying about the rows it names.
    /// </summary>
    public SplitMode? SplitMode { get; set; }

    public List<UpdateExpenseSplitDTO>? Splits { get; set; }
}
