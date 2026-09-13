using Splitty.Domain.Entities;

namespace Splitty.DTO.Request;

public class SettleUpRequest
{
    public int WithUserId { get; set; }
    public decimal Amount { get; set; }
    public DateTime? Date { get; set; }

    /// <summary>
    /// Accepted and ignored: a settlement's category is always
    /// <see cref="ExpenseCategory.Payment"/>. Coerced rather than refused, the way
    /// percentages are nulled under a non-percentage mode — a client sending one here is
    /// noisy, not confused about what it is writing.
    /// </summary>
    public ExpenseCategory? Category { get; set; }
}