using Splitty.DTO.Response;

namespace Splitty.Service;

/// <summary>
/// A refusal a client must tell apart from others with the same status, so it carries an
/// <see cref="ErrorCode"/> and whatever the client needs to act on it without another read.
/// The exception middleware turns it into an <see cref="ErrorResponse"/>.
/// </summary>
public sealed class RefusalException(int statusCode, ErrorCode code, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
    public ErrorCode Code { get; } = code;

    /// The row as it is now, for <see cref="ErrorCode.VersionConflict"/>.
    public ExpenseResponse? Expense { get; init; }

    /// The current cap, for <see cref="ErrorCode.SettlementExceedsCap"/>.
    public decimal? Cap { get; init; }

    public static RefusalException CurrencyChanged(Domain.Entities.Currency current) =>
        new(409, ErrorCode.CurrencyChanged,
            $"The group's currency is now {current}. Amounts are not converted, so check them before saving again.");

    public static RefusalException VersionConflict(ExpenseResponse current) =>
        new(409, ErrorCode.VersionConflict, "Someone else changed this since it was opened.")
        {
            Expense = current
        };
}
