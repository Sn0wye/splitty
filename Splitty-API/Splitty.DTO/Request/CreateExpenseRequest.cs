using System.ComponentModel.DataAnnotations;
using Splitty.Domain.Entities;
using Splitty.DTO.Internal;

namespace Splitty.DTO.Request;

public class CreateExpenseRequest
{
    public int PaidBy { get; set; }
    
    public Decimal Amount { get; set; }
    
    [Required(ErrorMessage = "Description is required")]
    public required string Description { get; set; }

    /// <summary>
    /// When the expense happened. Omitted means "now": the server falls back to the audit
    /// timestamp rather than guessing. Future dates are allowed.
    /// </summary>
    public DateTime? Date { get; set; }
    
    /// <summary>
    /// Required for the same reason <see cref="Splits"/> is: a stored <c>null</c> then
    /// means exactly one thing — a settlement — rather than "an expense whose client
    /// forgot to say".
    /// </summary>
    public required SplitMode SplitMode { get; set; }

    /// <summary>
    /// Required rather than nullable so a payload omitting it is rejected by the JSON
    /// deserializer, before any handler has to treat "absent" and "empty" the same way.
    /// </summary>
    public required List<ExpenseSplitDTO> Splits { get; set; }
}
