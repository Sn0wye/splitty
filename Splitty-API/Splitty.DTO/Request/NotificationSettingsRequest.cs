using System.ComponentModel.DataAnnotations;
using Splitty.Domain.Entities;

namespace Splitty.DTO.Request;

/// The whole state, not a patch: the settings screen always knows every switch.
public class NotificationSettingsRequest
{
    [Required]
    public bool? Enabled { get; set; }

    [Required]
    public List<NotificationKind>? Muted { get; set; }
}
