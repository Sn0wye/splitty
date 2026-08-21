using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

public enum OAuthProvider
{
    Google,
    Apple
}

/// One provider identity linked to one user. A user can hold several of these;
/// signing in through any of them lands on the same <see cref="User"/>.
[Table("OAuthAccount")]
public class OAuthAccount
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }

    public int UserId { get; init; }

    public OAuthProvider Provider { get; init; }

    /// The provider's stable user id (`sub`). This is the identity key, not the email:
    /// an email can be reassigned, a subject cannot.
    public string Subject { get; init; } = string.Empty;

    /// The address as the provider gave it, kept denormalized on purpose — when a
    /// linking bug shows up, "what did Google actually send" is otherwise unanswerable.
    /// `User.Email` stays canonical.
    public string Email { get; init; } = string.Empty;

    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;

    [JsonIgnore]
    public virtual User User { get; init; }
}
