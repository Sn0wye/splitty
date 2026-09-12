namespace Splitty.Service;

/// Bound from the `R2__*` environment variables; see `.env.example`.
public sealed class R2Options
{
    public string AccountId { get; init; } = string.Empty;

    public string AccessKeyId { get; init; } = string.Empty;

    public string SecretAccessKey { get; init; } = string.Empty;

    public string BucketName { get; init; } = string.Empty;

    /// <summary>
    /// The host that *serves* the images — a custom domain bound to the bucket — not the
    /// S3 API endpoint the SDK signs against, which is derived from
    /// <see cref="AccountId"/> and is not publicly readable.
    /// </summary>
    public string PublicBaseUrl { get; init; } = string.Empty;

    public TimeSpan UploadUrlLifetime => TimeSpan.FromMinutes(10);

    /// 2 MB. A 512x512 JPEG at quality 0.8 is around 60 KB, so this is headroom that still
    /// refuses a video.
    public long MaxAvatarBytes => 2 * 1024 * 1024;
}
