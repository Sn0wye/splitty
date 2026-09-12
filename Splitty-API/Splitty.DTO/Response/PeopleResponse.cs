namespace Splitty.DTO.Response;

public class PeopleResponse
{
    public List<PeerResponse> Peers { get; init; } = [];

    /// <summary>
    /// True while a recomputation is queued or in flight for any group behind these numbers.
    /// A display hint only: nothing branches on it for correctness.
    /// </summary>
    public bool BalancesPending { get; init; }
}

public class PeerResponse
{
    public int UserId { get; init; }

    public string Name { get; init; } = string.Empty;

    public string AvatarUrl { get; init; } = string.Empty;

    /// <summary>
    /// Sum of the caller's own balance rows for this peer, so the sign points the same way
    /// as the per-group balance reads.
    /// </summary>
    public decimal NetAmount { get; init; }

    public List<PeerGroupResponse> Groups { get; init; } = [];
}

public class PeerGroupResponse
{
    public int GroupId { get; init; }

    public string GroupName { get; init; } = string.Empty;

    public decimal Amount { get; init; }
}
