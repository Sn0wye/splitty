using Splitty.Domain.Entities;
using Splitty.DTO.Request;
using Splitty.DTO.Response;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class NotificationService(
    IPushDeviceRepository pushDeviceRepository,
    IUserRepository userRepository,
    IBalanceRepository balanceRepository,
    IGroupReadModel readModel,
    IGroupLedger groupLedger,
    ReminderCooldown reminderCooldown,
    INotifier notifier
) : INotificationService
{
    public async Task RegisterDeviceAsync(int userId, Guid familyId, RegisterPushDeviceRequest request)
    {
        if (!PushCopy.Languages.Contains(request.Language))
        {
            throw new ArgumentException($"Language must be one of {string.Join(", ", PushCopy.Languages)}.");
        }

        await pushDeviceRepository.UpsertAsync(new PushDevice
        {
            Token = request.Token.ToLowerInvariant(),
            UserId = userId,
            FamilyId = familyId,
            Environment = request.Environment ?? ApnsEnvironment.Production,
            Language = request.Language,
            UpdatedAt = DateTime.UtcNow
        });
    }

    public async Task<NotificationSettingsResponse> GetSettingsAsync(int userId) =>
        ToResponse(await RequireUserAsync(userId));

    public async Task<NotificationSettingsResponse> UpdateSettingsAsync(int userId, NotificationSettingsRequest request)
    {
        var user = await RequireUserAsync(userId);

        // The enum converter also binds bare integers, so a number outside the list reaches here.
        if (request.Muted!.Any(kind => !Enum.IsDefined(kind)))
        {
            throw new ArgumentException("Unknown notification kind.");
        }

        user.NotificationsEnabled = request.Enabled!.Value;
        user.MutedNotifications = request.Muted!.Distinct().Order().ToList();
        user.UpdatedAt = DateTime.UtcNow;
        await userRepository.UpdateAsync(user);

        return ToResponse(user);
    }

    public async Task<ReminderStatus> RemindAsync(int groupId, int callerId, int debtorId)
    {
        if (debtorId == callerId) return ReminderStatus.NothingOwed;

        if (!await readModel.IsMemberAsync(groupId, debtorId)) return ReminderStatus.DebtorNotAMember;

        var debts = await groupLedger.ReadAsync(groupId, () => balanceRepository.GetSimplifiedDebtsAsync(groupId));

        // The amount in the reminder must be one the debtor sees in the app too.
        if (debts.Pending) return ReminderStatus.BalancesPending;

        var owed = debts.Value.FirstOrDefault(d => d.FromUserId == debtorId && d.ToUserId == callerId);

        if (owed is null || owed.Amount <= 0) return ReminderStatus.NothingOwed;

        if (!reminderCooldown.TryClaim(groupId, callerId, debtorId)) return ReminderStatus.TooSoon;

        notifier.Notify([new Notice(debtorId, NoticeMessage.PaymentReminder, groupId, callerId) { Amount = owed.Amount }]);

        return ReminderStatus.Sent;
    }

    private async Task<User> RequireUserAsync(int userId) =>
        await userRepository.GetByIdAsync(userId) ?? throw new KeyNotFoundException("User not found.");

    private static NotificationSettingsResponse ToResponse(User user) => new()
    {
        Enabled = user.NotificationsEnabled,
        Muted = user.MutedNotifications
    };
}
