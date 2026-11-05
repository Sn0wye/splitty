using System.Collections.Concurrent;

namespace Splitty.Service;

/// <summary>
/// One reminder per creditor, debtor and group a day.
/// ponytail: in memory, so a restart forgets the last day and two API instances would each
/// allow one. Move it to a table if the API ever runs more than one instance.
/// </summary>
public sealed class ReminderCooldown(TimeProvider timeProvider)
{
    public static readonly TimeSpan Window = TimeSpan.FromHours(24);

    private readonly ConcurrentDictionary<(int GroupId, int CreditorId, int DebtorId), DateTimeOffset> _sent = new();

    /// True, and starts the day, when no reminder for the pair went out in the last day.
    public bool TryClaim(int groupId, int creditorId, int debtorId)
    {
        var key = (groupId, creditorId, debtorId);
        var now = timeProvider.GetUtcNow();

        while (true)
        {
            if (!_sent.TryGetValue(key, out var last))
            {
                if (_sent.TryAdd(key, now)) return true;
                continue;
            }

            if (now - last < Window) return false;
            if (_sent.TryUpdate(key, now, last)) return true;
        }
    }
}
