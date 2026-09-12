using Microsoft.Extensions.Logging;
using Splitty.Domain.Entities;
using Splitty.DTO.Request;
using Splitty.DTO.Response;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class ProfileService(
    IUserRepository userRepository,
    IGroupMembershipRepository groupMembershipRepository,
    IAvatarStorage avatarStorage,
    IAvatarResolver avatarResolver,
    ILogger<ProfileService> logger
) : IProfileService
{
    private const int MaxNameLength = 60;

    public async Task<ProfileResponse> GetAsync(int userId) => ToResponse(await RequireUserAsync(userId));

    public async Task<ProfileResponse> GetPeerAsync(int callerId, int peerId)
    {
        if (callerId == peerId)
        {
            return await GetAsync(callerId);
        }

        if (!await groupMembershipRepository.SharesGroupAsync(callerId, peerId))
        {
            throw new KeyNotFoundException("User not found.");
        }

        return ToResponse(await RequireUserAsync(peerId));
    }

    public async Task<ProfileResponse> UpdateAsync(
        int userId,
        UpdateProfileRequest request,
        CancellationToken cancellationToken = default)
    {
        var user = await RequireUserAsync(userId);

        if (!request.Name.IsSet && !request.AvatarKey.IsSet)
        {
            return ToResponse(user);
        }

        // Captured before the write: the object behind it is only orphaned once the row
        // stops pointing at it.
        var previousKey = user.AvatarKey;

        if (request.Name.IsSet)
        {
            user.Name = NormalizeName(request.Name.Value);
        }

        if (request.AvatarKey.IsSet)
        {
            user.AvatarKey = request.AvatarKey.Value is null
                ? null
                : await CommitAvatarKeyAsync(userId, request.AvatarKey.Value, cancellationToken);
        }

        user.UpdatedAt = DateTime.UtcNow;
        await userRepository.UpdateAsync(user);

        if (previousKey is not null && previousKey != user.AvatarKey)
        {
            await DiscardAsync(previousKey, cancellationToken);
        }

        return ToResponse(user);
    }

    public async Task<AvatarUploadResponse> CreateAvatarUploadAsync(
        int userId,
        CancellationToken cancellationToken = default)
    {
        await RequireUserAsync(userId);

        var upload = await avatarStorage.CreateUploadAsync(userId, cancellationToken);

        return new AvatarUploadResponse
        {
            Key = upload.Key,
            UploadUrl = upload.UploadUrl,
            ContentType = upload.ContentType,
            MaxBytes = avatarStorage.MaxBytes,
            ExpiresAt = upload.ExpiresAt
        };
    }

    /// <summary>
    /// Confirms the object is really there before the key is committed, so a client that
    /// crashed mid-upload cannot leave a user pointing at a 404. The size and type checks
    /// live here rather than in the presigned URL because an S3 PUT signature cannot bound
    /// a body whose length is unknown at signing time.
    /// </summary>
    private async Task<string> CommitAvatarKeyAsync(int userId, string key, CancellationToken cancellationToken)
    {
        // The key is client-supplied. Without the owner prefix check, anyone could point
        // their row at an object the API minted for someone else.
        if (!key.StartsWith($"avatars/{userId}/", StringComparison.Ordinal))
        {
            throw new InvalidOperationException("Avatar key was not issued for this user.");
        }

        var stored = await avatarStorage.HeadAsync(key, cancellationToken)
            ?? throw new InvalidOperationException("No uploaded image was found for this key.");

        if (stored.ContentLength > avatarStorage.MaxBytes)
        {
            await DiscardAsync(key, cancellationToken);

            throw new InvalidOperationException($"Avatar exceeds the {avatarStorage.MaxBytes} byte limit.");
        }

        if (!string.Equals(stored.ContentType, avatarStorage.ContentType, StringComparison.OrdinalIgnoreCase))
        {
            await DiscardAsync(key, cancellationToken);

            throw new InvalidOperationException($"Avatar must be {avatarStorage.ContentType}.");
        }

        return key;
    }

    /// Best effort: an object left behind is litter, not a failed request.
    private async Task DiscardAsync(string key, CancellationToken cancellationToken)
    {
        try
        {
            await avatarStorage.DeleteAsync(key, cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to delete avatar object {AvatarKey}.", key);
        }
    }

    private static string NormalizeName(string? name)
    {
        var trimmed = name?.Trim();

        if (string.IsNullOrEmpty(trimmed))
        {
            throw new ArgumentException("Name cannot be empty.", nameof(name));
        }

        if (trimmed.Length > MaxNameLength)
        {
            throw new ArgumentException($"Name cannot exceed {MaxNameLength} characters.", nameof(name));
        }

        return trimmed;
    }

    private async Task<User> RequireUserAsync(int userId) =>
        await userRepository.GetByIdAsync(userId) ?? throw new KeyNotFoundException("User not found.");

    private ProfileResponse ToResponse(User user) => new()
    {
        Id = user.Id,
        Name = user.Name,
        // Matches what `MemberDTO` already exposes to co-members; not a new disclosure.
        Email = user.Email,
        AvatarUrl = avatarResolver.Resolve(user)
    };
}
