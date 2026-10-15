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
    /// Omitted means unchanged, like every other field here. Clearing a category is setting
    /// it to <see cref="ExpenseCategory.General"/>, which is what a non-null column buys.
    /// <see cref="ExpenseCategory.Payment"/> is refused.
    /// </summary>
    public ExpenseCategory? Category { get; set; }
    
    /// <summary>
    /// Omitted means unchanged, except that an update supplying <see cref="Splits"/> must
    /// supply this too — the rows and the mode describing them are one fact, and letting
    /// half of it move would leave the other half lying about the rows it names.
    /// </summary>
    public SplitMode? SplitMode { get; set; }

    public List<UpdateExpenseSplitDTO>? Splits { get; set; }

    /// <summary>
    /// The new frequency of the recurring expense that added this expense, or
    /// <see cref="Domain.Entities.Repeat.Never"/> to stop it. Only accepted with
    /// <c>scope=following</c>; omitted keeps the current frequency.
    /// </summary>
    public Repeat? Repeat { get; set; }

    /// <summary>
    /// The IANA zone the recurring expense comes due in from this expense on, normally the
    /// device's current one. Only accepted with <c>scope=following</c>; omitted keeps the
    /// current zone.
    /// </summary>
    public string? TimeZone { get; set; }

    /// <summary>
    /// The new last day an installment may be due, from this expense on. Only accepted with
    /// <c>scope=following</c>, and never before this expense's day. Omitted keeps the current
    /// end, so clearing it is <see cref="EndsNever"/>, not a null here.
    /// </summary>
    public DateOnly? EndsOn { get; set; }

    /// <summary>
    /// <c>true</c> removes the end, so the recurring expense never ends. Only accepted with
    /// <c>scope=following</c>, and not together with <see cref="EndsOn"/>. Omitted or
    /// <c>false</c> leaves the end to <see cref="EndsOn"/>.
    /// </summary>
    public bool EndsNever { get; set; }
}
