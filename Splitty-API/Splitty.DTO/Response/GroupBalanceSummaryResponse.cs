namespace Splitty.DTO.Response;

public class GroupBalanceSummaryResponse
{
    public List<SimplifiedDebtResponse> SimplifiedDebts { get; init; } = [];

    /// <summary>
    /// True while a recomputation is queued or in flight, so the client can offer a refresh
    /// instead of silently presenting figures that predate the last write.
    /// </summary>
    public bool BalancesPending { get; init; }
}
