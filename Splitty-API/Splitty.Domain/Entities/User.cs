using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

[Table("User")]
public class User
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    
    public string Name { get; set; }
    
    public string Email { get; set; }
    
    [JsonIgnore]
    public string Password { get; set; }
    
    public string AvatarUrl { get; set; } = string.Empty;
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}