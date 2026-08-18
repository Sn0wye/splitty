namespace Splitty.DTO.Request;

public class CreateInviteRequest
{
    /// Null means unlimited uses.
    public int? MaxUses { get; set; }

    /// Null defaults to 7 days from now. Capped at 30 days from now.
    public DateTime? ExpiresAt { get; set; }
}
