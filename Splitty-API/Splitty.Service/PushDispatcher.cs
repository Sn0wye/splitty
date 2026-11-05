using Microsoft.EntityFrameworkCore;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

/// <summary>
/// Turns one notice into pushes: checks the recipient still wants it, writes it in each
/// signed-in device's language, sends it, and forgets a device Apple no longer knows. Run by
/// the push worker, one notice at a time.
/// </summary>
public sealed class PushDispatcher(
    ApplicationDbContext context,
    IPushDeviceRepository pushDeviceRepository,
    IPushSender pushSender
)
{
    public async Task DispatchAsync(Notice notice, CancellationToken cancellationToken = default)
    {
        var recipient = await context.User.AsNoTracking()
            .Where(u => u.Id == notice.RecipientId && u.DeletedAt == null && u.DeactivatedAt == null)
            .Select(u => new { u.NotificationsEnabled, u.MutedNotifications })
            .FirstOrDefaultAsync(cancellationToken);

        if (recipient is null || !recipient.NotificationsEnabled || recipient.MutedNotifications.Contains(notice.Kind))
        {
            return;
        }

        var devices = await pushDeviceRepository.GetSignedInAsync(notice.RecipientId);

        if (devices.Count == 0)
        {
            return;
        }

        // Gone when the last members left before the worker got here.
        var group = await context.Group.AsNoTracking()
            .Where(g => g.Id == notice.GroupId)
            .Select(g => new { g.Name, g.Currency })
            .FirstOrDefaultAsync(cancellationToken);

        if (group is null)
        {
            return;
        }

        int[] people = notice.PeerId is { } peer ? [notice.ActorId, peer] : [notice.ActorId];
        var names = await context.User.AsNoTracking()
            .Where(u => people.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Name, cancellationToken);

        foreach (var device in devices)
        {
            var (title, body) = PushCopy.Render(notice, device.Language, group.Name, group.Currency, names);
            var result = await pushSender.SendAsync(
                device, new Push(title, body, notice.GroupId, notice.ExpenseId), cancellationToken);

            if (result == PushResult.Unregistered)
            {
                await pushDeviceRepository.DeleteAsync(device.Id);
            }
        }
    }
}
