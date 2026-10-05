using System.ComponentModel.DataAnnotations.Schema;

namespace Splitty.Domain.Entities;

[Table("User")]
public class User
{
    /// The name a deleted user's row is rewritten to. The iOS client renders exactly this
    /// string as "Removed member", so no live user may take it.
    public const string TombstoneName = "[removed]";

    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    
    public required string Name { get; set; }
    
    public required string Email { get; set; }
    
    /// The picture the identity provider supplied, written once at user creation and never
    /// overwritten. Empty for a provider that sends none.
    public string AvatarUrl { get; set; } = string.Empty;

    /// The object key of the image the user uploaded, or null when they have not uploaded
    /// one. A key rather than an absolute URL, so the storage host can move without
    /// rewriting rows.
    public string? AvatarKey { get; set; }
    
    /// Set while the account is switched off. Signing in again clears it. A user is live
    /// when this and <see cref="DeletedAt"/> are both null.
    public DateTime? DeactivatedAt { get; set; }

    /// Set when the user deleted their account. The row is then a tombstone named
    /// `[removed]`, kept only so shared expense history and unsettled balances still point
    /// at someone. See docs/adr/0004-account-closure.md.
    public DateTime? DeletedAt { get; set; }

    /// Stamped into every token as a claim and bumped on deactivation, so reactivating
    /// does not bring back the sessions deactivating ended.
    public int TokenVersion { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
