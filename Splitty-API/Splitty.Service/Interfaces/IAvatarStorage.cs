namespace Splitty.Service.Interfaces;

/// A presigned slot for exactly one upload, plus the key the API will be asked to commit.
public sealed record PresignedAvatarUpload(string Key, string UploadUrl, string ContentType, DateTime ExpiresAt);

/// What storage reports about an object that is already there.
public sealed record StoredAvatar(long ContentLength, string ContentType);

/// <summary>
/// The only seam in the codebase that talks to the object store, mirroring what
/// <see cref="IGoogleTokenExchanger"/> is for Google. Everything above it — resolution
/// order, commit rules, cleanup — is testable without a network.
/// </summary>
public interface IAvatarStorage
{
    /// The upload content type every presigned URL is pinned to.
    string ContentType { get; }

    /// The largest object the API will commit. Enforced on commit, since an S3 presigned
    /// PUT cannot bound a body whose length is unknown at signing time.
    long MaxBytes { get; }

    Task<PresignedAvatarUpload> CreateUploadAsync(int userId, CancellationToken cancellationToken = default);

    /// Null when no object exists at <paramref name="key"/>.
    Task<StoredAvatar?> HeadAsync(string key, CancellationToken cancellationToken = default);

    Task DeleteAsync(string key, CancellationToken cancellationToken = default);

    /// The absolute, publicly readable URL for a committed key.
    string PublicUrl(string key);
}
