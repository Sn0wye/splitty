using Splitty.Domain.Entities;

namespace Splitty.DTO.Request;

/// <summary>
/// Two shapes. <c>withUserId</c> alone records the caller paying that member, which is what
/// clients built before either side could record a payment still send. <c>fromUserId</c>
/// and <c>toUserId</c> together record one member paying another; the caller need not be
/// either of them. Sending both shapes, or only half of the second, is refused.
///
/// No category field: a settlement always carries ExpenseCategory.Payment. One sent anyway
/// is dropped as an unmapped member, which is the coercion ADR 0002 promises — a typed
/// property would refuse an unknown token with a 400 instead.
/// </summary>
public class SettleUpRequest
{
    public int? WithUserId { get; set; }
    public int? FromUserId { get; set; }
    public int? ToUserId { get; set; }
    public decimal Amount { get; set; }
    public DateTime? Date { get; set; }

    /// <summary>See <see cref="CreateExpenseRequest.ClientId"/>.</summary>
    public Guid? ClientId { get; set; }

    /// <summary>See <see cref="CreateExpenseRequest.Currency"/>.</summary>
    public Currency? Currency { get; set; }
}
