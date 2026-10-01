namespace Splitty.DTO.Internal;

public class MemberDTO
{
    public int Id { get; init; }
    public int UserId { get; set; }
    public String Name { get; set; } = string.Empty;
    public String Email { get; set; } = string.Empty;
    
    public String AvatarUrl { get; set; } = string.Empty;
}