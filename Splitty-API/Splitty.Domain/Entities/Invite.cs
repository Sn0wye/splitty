using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

[Table("Invite")]
public class Invite
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }

    public int GroupId { get; init; }

    public string Code { get; init; } = string.Empty;

    public int CreatedBy { get; init; }

    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;

    public DateTime ExpiresAt { get; init; }

    public int? MaxUses { get; init; }

    public int UsedCount { get; set; }

    [JsonIgnore]
    public virtual Group Group { get; init; }

    [JsonIgnore]
    public virtual User CreatedByUser { get; init; }
}
