namespace Splitty.DTO.Internal;

public class MemberDTO
{
    public int Id { get; init; }
    public int UserId { get; set; }
    public required String Name { get; set; }
    public required String Email { get; set; }
    
    public String AvatarUrl { get; set; } = string.Empty;
}