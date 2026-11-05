using System.Text.Json.Serialization;

namespace Splitty.DTO.Response;

public class ErrorResponse
{
    public int StatusCode { get; set; }
    public required string Message { get; set; }
    public string? Details { get; set; }

    /// <summary>
    /// The request's id, also sent as the <c>X-Trace-Id</c> header on every response. Quote it to
    /// find the request's log events in Seq. Set on responses from the exception middleware.
    /// </summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? TraceId { get; set; }

    /// <summary>
    /// Set only where a client must tell two refusals with the same status apart. The message
    /// is English prose for people; this is the part a client may branch on. Omitted otherwise.
    /// </summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public ErrorCode? Code { get; set; }

    /// <summary>
    /// The row as it is now, on <c>version_conflict</c>, so the client can merge without
    /// another read. Omitted otherwise.
    /// </summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public ExpenseResponse? Expense { get; set; }

    /// <summary>
    /// The most the settlement could be right now, on <c>settlement_exceeds_cap</c>. Omitted
    /// otherwise.
    /// </summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public decimal? Cap { get; set; }
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
    BalancesPending,

    /// An edit named a version the row has moved past. The body carries the current row.
    [JsonStringEnumMemberName("version_conflict")]
    VersionConflict,

    /// A settlement is larger than the cap of invariant 5. The body carries the cap.
    [JsonStringEnumMemberName("settlement_exceeds_cap")]
    SettlementExceedsCap,

    /// A write named a currency the group no longer has (ADR 0007).
    [JsonStringEnumMemberName("currency_changed")]
    CurrencyChanged
}
