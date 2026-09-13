namespace Splitty.DTO.Request;

/// <summary>
/// No category field: a settlement always carries ExpenseCategory.Payment. One sent anyway
/// is dropped as an unmapped member, which is the coercion ADR 0002 promises — a typed
/// property would refuse an unknown token with a 400 instead.
/// </summary>
public class SettleUpRequest
{
    public int WithUserId { get; set; }
    public decimal Amount { get; set; }
    public DateTime? Date { get; set; }
}