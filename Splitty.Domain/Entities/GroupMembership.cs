using System.ComponentModel.DataAnnotations.Schema;

namespace Splitty.Domain.Entities;

[Table("GroupMembership")]
public class GroupMembership
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    
    public int UserId { get; init; }
    
    public int GroupId { get; init; }
    
    public DateTime JoinedAt { get; init; } = DateTime.UtcNow;
    
    public virtual User User { get; init; }
    
    public virtual Group Group { get; init; }
}