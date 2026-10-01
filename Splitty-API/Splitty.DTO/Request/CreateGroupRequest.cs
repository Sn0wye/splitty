using System.ComponentModel.DataAnnotations;

namespace Splitty.DTO.Request;

public class CreateGroupRequest
{
    [Required(ErrorMessage = "Group name is required.")]
    public required string Name { get; set; }
    public string? Description { get; set; }
}
