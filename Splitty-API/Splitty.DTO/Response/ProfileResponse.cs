namespace Splitty.DTO.Response;

/// <summary>
/// A DTO rather than the <c>User</c> entity, so adding a column is not automatically an
/// API change. <c>AvatarUrl</c> is always resolved and always absolute — the client never
/// learns whether it got the uploaded image, the provider's, or a generated one.
/// </summary>
public class ProfileResponse
{
    public int Id { get; init; }

    public string Name { get; init; } = string.Empty;

    public string Email { get; init; } = string.Empty;

    public string AvatarUrl { get; init; } = string.Empty;
}
