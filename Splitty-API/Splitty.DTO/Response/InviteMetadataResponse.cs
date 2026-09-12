namespace Splitty.DTO.Response;

/// Describes what an invite code is for, without spending it. Deliberately carries
/// no group id: the group behind a code is derived from the code alone, on accept.
public class InviteMetadataResponse
{
    public string GroupName { get; init; } = string.Empty;
    public int MemberCount { get; init; }
    public string CreatedByName { get; init; } = string.Empty;
    public bool AlreadyMember { get; init; }
}
