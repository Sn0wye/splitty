using System.ComponentModel.DataAnnotations;
using Splitty.Domain.Entities;

namespace Splitty.DTO.Request;

public class CreateGroupRequest
{
    [Required(ErrorMessage = "Group name is required.")]
    public required string Name { get; set; }
    public string? Description { get; set; }
    /// Omitted means <see cref="Currency.USD"/>.
    public Currency? Currency { get; set; }
}
