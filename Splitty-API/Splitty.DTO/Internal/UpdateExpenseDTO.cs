using Splitty.Domain.Entities;

namespace Splitty.DTO.Internal;

public class UpdateExpenseDTO
{
    public int Id { get; set; }
    public int? GroupId { get; set; }
    public int? PaidBy { get; set; }
    public Decimal? Amount { get; set; }
    public string? Description { get; set; }
    public DateTime? Date { get; set; }
    public ExpenseCategory? Category { get; set; }
    public SplitMode? SplitMode { get; set; }
    public List<UpdateExpenseSplitDTO>? ExpenseSplits { get; set; }
    public Repeat? Repeat { get; set; }
    public ExpenseScope Scope { get; set; } = ExpenseScope.This;
}

/// <summary>
/// What an edit or delete of an expense a recurring expense added applies to: that expense
/// only, or it and every one after it.
/// </summary>
public enum ExpenseScope
{
    This,
    Following
}

/// <summary>
/// Carries no id: the server owns split identity. An edit that sends splits replaces the
/// expense's rows, so a client-sent id — dropped on deserialization like any unknown
/// property — can never point the edit at a row of another expense.
/// </summary>
public partial class UpdateExpenseSplitDTO
{
    public int UserId { get; set; }
    public Decimal Amount { get; set; }

    /// Percent units (70.00). Required on a percentage expense, ignored on any other.
    public Decimal? Percentage { get; set; }
}