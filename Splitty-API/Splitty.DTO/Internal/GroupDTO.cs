namespace Splitty.DTO.Internal;

public class GroupDTO
{
    public int Id { get; init; }
    
    public required string Name { get; set; }
    
    public string? Description { get; set; }
    
    public Decimal NetBalance { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// The newest row's <c>Date ?? CreatedAt</c>, settlements included. Null for a group with
    /// no rows. Clients order a group picker by it.
    /// </summary>
    public DateTime? LastActivityAt { get; set; }
    
    public virtual ICollection<MemberDTO> Members { get; set; } = new List<MemberDTO>();
}
