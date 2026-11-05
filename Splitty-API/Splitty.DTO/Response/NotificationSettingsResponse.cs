using Splitty.Domain.Entities;

namespace Splitty.DTO.Response;

/// <summary>
/// The in-app notification switches. <c>Enabled</c> is the main switch; <c>Muted</c> lists
/// the kinds switched off and survives the main switch going off and on again.
/// </summary>
public class NotificationSettingsResponse
{
    public bool Enabled { get; init; }

    public List<NotificationKind> Muted { get; init; } = [];
}
