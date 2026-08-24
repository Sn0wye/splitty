using Splitty.Domain.Entities;

namespace Splitty.DTO.Internal;

public class CreateExpenseDTO
{
    public int GroupId { get; set; }
    public int PaidBy { get; set; }
    public Decimal Amount { get; set; }
    public string Description { get; set; }
    public DateTime? Date { get; set; }
    public required SplitMode SplitMode { get; set; }
    public required List<ExpenseSplitDTO> ExpenseSplits { get; set; }
}

public partial class ExpenseSplitDTO
{
    public int UserId { get; set; }
    public Decimal Amount { get; set; }

    /// Percent units (70.00). Required on a percentage expense, ignored on any other.
    public Decimal? Percentage { get; set; }
}