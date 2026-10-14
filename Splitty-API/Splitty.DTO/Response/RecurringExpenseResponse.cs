using Splitty.Domain.Entities;

namespace Splitty.DTO.Response;

/// An active recurring expense: one that is neither finished nor stopped.
public sealed class RecurringExpenseResponse
{
    public int Id { get; init; }
    public required string Description { get; init; }
    public decimal Amount { get; init; }
    public ExpenseCategory Category { get; init; }
    public int PaidBy { get; init; }
    public RepeatFrequency Frequency { get; init; }

    /// The day the next expense will be added, in the recurring expense's zone.
    public DateOnly NextDueOn { get; init; }

    /// The last day an installment may be due, null when it never ends.
    public DateOnly? EndsOn { get; init; }

    public required InstallmentProgressResponse Progress { get; init; }
}

/// <summary>
/// <see cref="Added"/> of <see cref="Total"/> installments, counted from the expenses that
/// exist. <see cref="Total"/> is null when the recurring expense never ends.
/// </summary>
public sealed class InstallmentProgressResponse
{
    public int Added { get; init; }
    public int? Total { get; init; }
}
