using Splitty.Domain.Entities;

namespace Splitty.DTO.Request;

public class UpdateSettlementRequest
{
    public Decimal Amount { get; set; }

    public DateTime? Date { get; set; }

    /// <summary>
    /// Accepted and ignored, for the reason given on
    /// <see cref="SettleUpRequest.Category"/>.
    /// </summary>
    public ExpenseCategory? Category { get; set; }
}
