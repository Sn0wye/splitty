using System.ComponentModel.DataAnnotations.Schema;

namespace Splitty.Domain.Entities;

[Table("User")]
public class User
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    
    public string Name { get; set; }
    
    public string Email { get; set; }
    
    /// The picture the identity provider supplied, written once at user creation and never
    /// overwritten. Empty for a provider that sends none.
    public string AvatarUrl { get; set; } = string.Empty;

    /// The object key of the image the user uploaded, or null when they have not uploaded
    /// one. A key rather than an absolute URL, so the storage host can move without
    /// rewriting rows.
    public string? AvatarKey { get; set; }
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
