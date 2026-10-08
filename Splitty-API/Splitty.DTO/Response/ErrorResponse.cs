using System.Text.Json.Serialization;

namespace Splitty.DTO.Response;

public class ErrorResponse
{
    public int StatusCode { get; set; }
    public required string Message { get; set; }
    public string? Details { get; set; }

    /// <summary>
    /// Set only where a client must tell two refusals with the same status apart. The message
    /// is English prose for people; this is the part a client may branch on. Omitted otherwise.
    /// </summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public ErrorCode? Code { get; set; }
}

/// <summary>
/// Stable names for refusals a client handles differently. Append-only by name, like the
/// other enums on the wire.
/// </summary>
[JsonConverter(typeof(JsonStringEnumConverter<ErrorCode>))]
public enum ErrorCode
{
    /// Leaving or removal refused: the member's net in the group is not zero.
    [JsonStringEnumMemberName("outstanding_balance")]
    OutstandingBalance,

    /// Leaving or removal refused: a recomputation is outstanding, so the net cannot be
    /// trusted yet. Retryable.
    [JsonStringEnumMemberName("balances_pending")]
    BalancesPending
}
