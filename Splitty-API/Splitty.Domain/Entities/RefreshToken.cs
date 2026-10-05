using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

/// One refresh token the API handed out. Each row is used once: a refresh revokes it and
/// inserts its replacement in the same family. See
/// docs/adr/0004-short-access-tokens-with-rotating-refresh-tokens.md.
[Table("RefreshToken")]
public class RefreshToken
{
    public Guid Id { get; init; } = Guid.NewGuid();

    public int UserId { get; init; }

    /// One sign-in on one device. Every rotation stays in the family its sign-in started,
    /// so reuse or logout can revoke the whole chain at once.
    public Guid FamilyId { get; init; }

    /// SHA-256 of the raw token, hex-encoded. The raw token is never stored, so a database
    /// leak hands out nothing that can be presented.
    public string TokenHash { get; init; } = string.Empty;

    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;

    /// The idle cutoff. Each rotation sets the replacement's to now plus
    /// `Jwt:RefreshTokenDays`, so a sign-in in regular use never reaches it.
    public DateTime ExpiresAt { get; init; }

    public DateTime? RevokedAt { get; init; }

    /// The row this one was rotated into. Null on the newest row of a live family, and on
    /// rows revoked by reuse detection or logout rather than by rotation.
    public Guid? ReplacedById { get; init; }

    [JsonIgnore]
    public virtual User User { get; init; } = null!;
}
