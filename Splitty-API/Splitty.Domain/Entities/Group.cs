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

    /// <summary>
    /// Set whenever a balance recomputation is enqueued, cleared by the worker once it replays.
    /// A display hint only: nothing branches on it for correctness.
    /// </summary>
    public bool BalancesPending { get; set; }
    
    public virtual User CreatedByUser { get; set; }
    
    public virtual ICollection<GroupMembership> Members { get; set; } = new List<GroupMembership>();
    public virtual ICollection<Balance> Balances { get; set; } = new List<Balance>();
}