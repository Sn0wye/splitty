namespace Splitty.DTO.Internal;

public class GroupDTO
{
    public int Id { get; init; }
    
    public string Name { get; set; }
    
    public string? Description { get; set; }
    
    public Decimal NetBalance { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public virtual ICollection<MemberDTO> Members { get; set; } = new List<MemberDTO>();
}
