namespace Splitty.Service;

/// <summary>
/// The user-supplied expense date, forced to UTC before it reaches Npgsql, which rejects a
/// non-UTC <see cref="DateTime"/> for a <c>timestamptz</c> column. A payload without an
/// offset arrives as <see cref="DateTimeKind.Unspecified"/> and is read as already-UTC
/// rather than as server-local time, so the stored instant does not depend on where the
/// API happens to run.
/// </summary>
internal static class ExpenseDate
{
    public static DateTime? Normalize(DateTime? date) => date switch
    {
        null => null,
        { Kind: DateTimeKind.Utc } => date,
        { Kind: DateTimeKind.Unspecified } => DateTime.SpecifyKind(date.Value, DateTimeKind.Utc),
        _ => date.Value.ToUniversalTime()
    };
}
