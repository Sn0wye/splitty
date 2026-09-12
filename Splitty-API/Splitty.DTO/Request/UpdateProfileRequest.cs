using Splitty.DTO.Json;

namespace Splitty.DTO.Request;

/// <summary>
/// Partial by construction: a field left out of the body is unchanged. An explicit
/// <c>"avatarKey": null</c> removes the uploaded image and falls back to the provider
/// picture, then to the generated one.
/// </summary>
public class UpdateProfileRequest
{
    public Patch<string> Name { get; init; }

    public Patch<string> AvatarKey { get; init; }
}
