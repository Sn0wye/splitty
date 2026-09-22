namespace Splitty.DTO.Response;

public class SimplifiedDebtResponse
{
    public DebtMemberResponse From { get; init; } = new();
    public DebtMemberResponse To { get; init; } = new();
    public decimal Amount { get; init; }
}

public class DebtMemberResponse
{
    public int Id { get; init; }
    public string Name { get; init; } = string.Empty;
    public string AvatarUrl { get; init; } = string.Empty;
}
