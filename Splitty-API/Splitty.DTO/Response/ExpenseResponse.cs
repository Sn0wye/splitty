using Splitty.Domain.Entities;

namespace Splitty.DTO.Response;

public sealed class ExpenseResponse
{
    public int Id { get; init; }
    public int GroupId { get; init; }
    public int PaidBy { get; init; }
    public decimal Amount { get; init; }
    public required string Description { get; init; }
    public ExpenseType Type { get; init; }
    public SplitMode? SplitMode { get; init; }
    public ExpenseCategory Category { get; init; }
    public DateTime? Date { get; init; }
    public DateTime CreatedAt { get; init; }
    public DateTime UpdatedAt { get; init; }
    public ExpenseUserResponse PaidByUser { get; set; } = null!;
    public List<ExpenseSplitResponse> Splits { get; init; } = [];
}

public sealed class ExpenseSplitResponse
{
    public int Id { get; init; }
    public int ExpenseId { get; init; }
    public int UserId { get; init; }
    public decimal Amount { get; init; }
    public decimal? Percentage { get; init; }
    public ExpenseUserResponse User { get; set; } = null!;
}

public sealed class ExpenseUserResponse
{
    public int Id { get; init; }
    public required string Name { get; init; }
    public required string Email { get; init; }
    public required string AvatarUrl { get; init; }
    public DateTime CreatedAt { get; init; }
    public DateTime UpdatedAt { get; init; }
}
