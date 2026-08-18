namespace Splitty.DTO.Response;

public class InviteResponse
{
    public string Code { get; init; } = string.Empty;
    public int GroupId { get; init; }
    public DateTime CreatedAt { get; init; }
    public DateTime ExpiresAt { get; init; }
    public int? MaxUses { get; init; }
    public int UsedCount { get; init; }
}
