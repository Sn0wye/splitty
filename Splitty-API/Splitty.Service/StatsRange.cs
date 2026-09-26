using System.Diagnostics.CodeAnalysis;
using System.Globalization;

namespace Splitty.Service;

/// <summary>
/// <c>[Start, End)</c> as instants, resolved from local calendar dates in the caller's time
/// zone. A null bound leaves that end open. The server never names a range: "this month" is
/// two dates the client computes in its own zone.
/// </summary>
public readonly record struct StatsRange(DateTime? Start, DateTime? End)
{
    /// <summary>
    /// Reads <c>YYYY-MM-DD</c> dates as local midnights in the IANA zone
    /// <paramref name="timeZoneId"/>, which is required. Fails on a malformed date, a missing
    /// or unknown zone, or a range that does not end after it starts.
    /// </summary>
    public static bool TryParse(
        string? from,
        string? to,
        string? timeZoneId,
        out StatsRange range,
        [NotNullWhen(false)] out string? error)
    {
        range = default;

        if (string.IsNullOrWhiteSpace(timeZoneId))
        {
            error = "'tz' is required.";
            return false;
        }

        if (!TimeZoneInfo.TryFindSystemTimeZoneById(timeZoneId, out var zone))
        {
            error = $"'{timeZoneId}' is not a known time zone.";
            return false;
        }

        if (!TryStartOfDay(from, zone, out var start))
        {
            error = "'from' must be a date in YYYY-MM-DD form.";
            return false;
        }

        if (!TryStartOfDay(to, zone, out var end))
        {
            error = "'to' must be a date in YYYY-MM-DD form.";
            return false;
        }

        if (start >= end)
        {
            error = "'from' must be before 'to'.";
            return false;
        }

        range = new StatsRange(start, end);
        error = null;
        return true;
    }

    /// <summary>
    /// The instant local midnight of <paramref name="value"/> happens in <paramref name="zone"/>.
    /// A midnight skipped by a daylight-saving jump resolves to the first instant after the
    /// gap; one that happens twice resolves to the earlier, so the day starts when it first can.
    /// </summary>
    private static bool TryStartOfDay(string? value, TimeZoneInfo zone, out DateTime? instant)
    {
        instant = null;

        if (value is null) return true;

        if (!DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day))
        {
            return false;
        }

        var local = day.ToDateTime(TimeOnly.MinValue);

        while (zone.IsInvalidTime(local))
        {
            local = local.AddMinutes(1);
        }

        instant = zone.IsAmbiguousTime(local)
            ? DateTime.SpecifyKind(local - zone.GetAmbiguousTimeOffsets(local).Max(), DateTimeKind.Utc)
            : TimeZoneInfo.ConvertTimeToUtc(local, zone);

        return true;
    }
}
