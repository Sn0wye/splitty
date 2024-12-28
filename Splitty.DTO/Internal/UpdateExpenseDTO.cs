using Splitty.Domain.Entities;

namespace Splitty.DTO.Internal;

public class UpdateExpenseDTO
{
    public int Id { get; set; }
    public int? GroupId { get; set; }
    public int? PaidBy { get; set; }
    public Decimal? Amount { get; set; }
    public string? Description { get; set; }
    public List<UpdateExpenseSplitDTO>? ExpenseSplits { get; set; }
}

public partial class UpdateExpenseSplitDTO
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public Decimal Amount { get; set; }
}