using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

[Table("Group")]
public class Group
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    
    public string Name { get; set; }
    
    public string? Description { get; set; }

    public int CreatedBy { get; set; }
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public virtual User CreatedByUser { get; set; }
    
    public virtual ICollection<GroupMembership> Members { get; set; } = new List<GroupMembership>();
    public virtual ICollection<Balance> Balances { get; set; } = new List<Balance>();
}