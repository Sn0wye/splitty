using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

[Table("Group")]
public class Group
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    
    public required string Name { get; set; }
    
    public string? Description { get; set; }

    public int CreatedBy { get; set; }
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Set whenever a balance recomputation is enqueued, cleared by the worker once a replay
    /// has seen every write made so far (see <see cref="BalancesPendingGeneration"/>).
    /// Covers pairwise and simplified debts; pending groups refuse settlements.
    /// </summary>
    public bool BalancesPending { get; set; }

    /// <summary>
    /// Bumped each time the group is marked pending. The worker reads it before a replay and
    /// clears <see cref="BalancesPending"/> only if it is unchanged afterwards, so a replay
    /// that started before a newer write leaves the flag for that write's own replay.
    /// Internal bookkeeping, never sent to clients.
    /// </summary>
    public int BalancesPendingGeneration { get; set; }
    
    public virtual User CreatedByUser { get; set; } = null!;
    
    public virtual ICollection<GroupMembership> Members { get; set; } = new List<GroupMembership>();
    [JsonIgnore]
    public virtual ICollection<Balance> Balances { get; set; } = new List<Balance>();
}