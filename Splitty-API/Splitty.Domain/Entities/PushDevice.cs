using System.ComponentModel.DataAnnotations.Schema;

namespace Splitty.Domain.Entities;

/// Which APNs host a device token belongs to. Debug builds get sandbox tokens; TestFlight
/// and App Store builds get production ones, and neither host accepts the other's.
public enum ApnsEnvironment
{
    Sandbox,
    Production
}

/// <summary>
/// One device that receives push notifications. Bound to the refresh token family of the
/// sign-in that registered it, so a push only goes to a device that is still signed in as
/// its user: logging out, reuse detection, deactivation and expiry all end the family.
/// </summary>
[Table("PushDevice")]
public class PushDevice
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }

    /// The APNs device token, hex-encoded. Unique: when a second user signs in on the same
    /// device, the row moves to them.
    public required string Token { get; set; }

    public int UserId { get; set; }

    public Guid FamilyId { get; set; }

    public ApnsEnvironment Environment { get; set; }

    /// The language picked inside the app, which iOS does not know about, so the server
    /// writes the text in it. One of the app's four language codes.
    public required string Language { get; set; }

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
