using System.Collections.Concurrent;
using Splitty.Service.Interfaces;

namespace Splitty.API.Tests;

/// <summary>
/// Stands in for the one component that would otherwise reach Cloudflare. A test states
/// what "is in the bucket" by calling <see cref="PutObject"/>; nothing here signs or
/// transfers anything.
/// </summary>
public sealed class FakeAvatarStorage : IAvatarStorage
{
    private readonly ConcurrentDictionary<string, StoredAvatar> _objects = new();
    private readonly ConcurrentBag<string> _deleted = [];

    public const string PublicBase = "https://avatars.splitty.test";

    public string ContentType => "image/jpeg";

    public long MaxBytes => 2 * 1024 * 1024;

    /// Every key this fake has been asked to presign, oldest first.
    public IReadOnlyCollection<string> Presigned => _presigned;

    private readonly List<string> _presigned = [];

    public IReadOnlyCollection<string> Deleted => _deleted;

    /// When set, the next delete throws. Proves a failed cleanup does not fail a request.
    public bool FailDeletes { get; set; }

    public Task<PresignedAvatarUpload> CreateUploadAsync(int userId, CancellationToken cancellationToken = default)
    {
        var key = $"avatars/{userId}/{Guid.NewGuid():N}.jpg";
        lock (_presigned) _presigned.Add(key);

        return Task.FromResult(new PresignedAvatarUpload(
            key,
            $"{PublicBase}/upload/{key}?signature=fake",
            ContentType,
            DateTime.UtcNow.AddMinutes(10)));
    }

    public Task<StoredAvatar?> HeadAsync(string key, CancellationToken cancellationToken = default) =>
        Task.FromResult(_objects.GetValueOrDefault(key));

    public Task DeleteAsync(string key, CancellationToken cancellationToken = default)
    {
        if (FailDeletes)
        {
            throw new InvalidOperationException("Storage is unavailable.");
        }

        _deleted.Add(key);
        _objects.TryRemove(key, out _);

        return Task.CompletedTask;
    }

    public string PublicUrl(string key) => $"{PublicBase}/{key}";

    /// Pretends the client finished its PUT.
    public void PutObject(string key, long contentLength = 60_000, string? contentType = null) =>
        _objects[key] = new StoredAvatar(contentLength, contentType ?? ContentType);

    public bool Contains(string key) => _objects.ContainsKey(key);

    public void Reset()
    {
        _objects.Clear();
        _deleted.Clear();
        lock (_presigned) _presigned.Clear();
        FailDeletes = false;
    }
}
