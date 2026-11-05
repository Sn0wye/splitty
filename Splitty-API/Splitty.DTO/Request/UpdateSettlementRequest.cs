using Splitty.Domain.Entities;

namespace Splitty.DTO.Request;

public class UpdateSettlementRequest
{
    public Decimal Amount { get; set; }

    public DateTime? Date { get; set; }

    /// <summary>See <see cref="UpdateExpenseRequest.BaseVersion"/>.</summary>
    public int? BaseVersion { get; set; }

    /// <summary>See <see cref="UpdateExpenseRequest.OpId"/>.</summary>
    public Guid? OpId { get; set; }

    /// <summary>See <see cref="CreateExpenseRequest.Currency"/>.</summary>
    public Currency? Currency { get; set; }
}
