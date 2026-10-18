using Splitty.Domain.Entities;

namespace Splitty.DTO.Request;

public class UpdateGroupRequest
{
    public string? Name { get; set; }
    public string? Description { get; set; }
    /// Relabels every amount in the group; nothing is converted (ADR 0007).
    public Currency? Currency { get; set; }
}
