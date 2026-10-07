namespace Splitty.Service;

/// <summary>Calendar days in an IANA zone, and the instants they start at.</summary>
internal static class LocalCalendar
{
    /// <summary>
    /// The instant local midnight of <paramref name="day"/> happens in <paramref name="zone"/>.
    /// A midnight skipped by a daylight-saving jump resolves to the first instant after the
    /// gap; one that happens twice resolves to the earlier, so the day starts when it first can.
    /// </summary>
    public static DateTime MidnightUtc(DateOnly day, TimeZoneInfo zone)
    {
        var local = day.ToDateTime(TimeOnly.MinValue);

        while (zone.IsInvalidTime(local))
        {
            local = local.AddMinutes(1);
        }

        return zone.IsAmbiguousTime(local)
            ? DateTime.SpecifyKind(local - zone.GetAmbiguousTimeOffsets(local).Max(), DateTimeKind.Utc)
            : TimeZoneInfo.ConvertTimeToUtc(local, zone);
    }

    /// The calendar day <paramref name="instant"/> falls on in <paramref name="zone"/>.
    public static DateOnly DayOf(DateTimeOffset instant, TimeZoneInfo zone) =>
        DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(instant, zone).DateTime);

    /// Reads <paramref name="utc"/> as UTC whatever its kind, like <see cref="ExpenseDate"/>.
    public static DateOnly DayOf(DateTime utc, TimeZoneInfo zone) =>
        DayOf(new DateTimeOffset(DateTime.SpecifyKind(utc, DateTimeKind.Utc)), zone);
}
