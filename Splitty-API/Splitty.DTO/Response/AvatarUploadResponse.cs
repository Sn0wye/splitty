namespace Splitty.DTO.Response;

/// <summary>
/// A presigned slot for exactly one image. The bytes go straight to storage; the client
/// then sends <see cref="Key"/> back to the API to commit it.
/// </summary>
public class AvatarUploadResponse
{
    public string Key { get; init; } = string.Empty;

    public string UploadUrl { get; init; } = string.Empty;

    /// The content type the URL is signed for. A PUT with anything else is rejected.
    public string ContentType { get; init; } = string.Empty;

    public long MaxBytes { get; init; }

    public DateTime ExpiresAt { get; init; }
}
