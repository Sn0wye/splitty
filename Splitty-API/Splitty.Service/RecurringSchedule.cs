using Splitty.Domain.Entities;

namespace Splitty.Service;

/// <summary>
/// The days a recurring expense comes due. Every day is computed from the start date, never
/// from the previous one, so a monthly expense started on the 31st clamps to the last day of
/// a shorter month and returns to the 31st after it, and one started on 29 February lands on
/// 28 February outside leap years.
/// </summary>
internal static class RecurringSchedule
{
    /// The <paramref name="n"/>th due day after <paramref name="start"/>, which is the 0th.
    public static DateOnly DueDay(DateOnly start, RepeatFrequency frequency, int n) => frequency switch
    {
        RepeatFrequency.Weekly => start.AddDays(7 * n),
        RepeatFrequency.Fortnightly => start.AddDays(14 * n),
        // Both clamp to the last day of the month, which is the rule.
        RepeatFrequency.Monthly => start.AddMonths(n),
        RepeatFrequency.Yearly => start.AddYears(n),
        _ => throw new ArgumentOutOfRangeException(nameof(frequency), frequency, null)
    };

    /// Every due day later than <paramref name="after"/>, up to and including <paramref name="through"/>.
    public static IEnumerable<DateOnly> DueDaysBetween(
        DateOnly start,
        RepeatFrequency frequency,
        DateOnly after,
        DateOnly through)
    {
        for (var n = 1; ; n++)
        {
            var day = DueDay(start, frequency, n);

            if (day > through) yield break;
            if (day > after) yield return day;
        }
    }
}
