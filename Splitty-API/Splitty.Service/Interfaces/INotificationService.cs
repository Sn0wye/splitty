using Splitty.DTO.Request;
using Splitty.DTO.Response;

namespace Splitty.Service.Interfaces;

public enum ReminderStatus
{
    Sent,
    DebtorNotAMember,
    BalancesPending,
    NothingOwed,
    TooSoon
}

public interface INotificationService
{
    /// Registers the device for the sign-in <paramref name="familyId"/> belongs to. Throws
    /// <see cref="ArgumentException"/> for a language the app does not ship.
    Task RegisterDeviceAsync(int userId, Guid familyId, RegisterPushDeviceRequest request);

    Task<NotificationSettingsResponse> GetSettingsAsync(int userId);

    Task<NotificationSettingsResponse> UpdateSettingsAsync(int userId, NotificationSettingsRequest request);

    /// <summary>
    /// Asks <paramref name="debtorId"/> to pay what they owe the caller in the group, from the
    /// stored simplified debts. Once a day per pair and group. A debtor who switched reminders
    /// off is not told, and the caller is not told that they did.
    /// </summary>
    Task<ReminderStatus> RemindAsync(int groupId, int callerId, int debtorId);
}
