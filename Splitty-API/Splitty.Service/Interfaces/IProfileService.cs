using Splitty.DTO.Request;
using Splitty.DTO.Response;

namespace Splitty.Service.Interfaces;

public interface IProfileService
{
    Task<ProfileResponse> GetAsync(int userId);

    /// <summary>
    /// A peer's profile. Throws <see cref="KeyNotFoundException"/> when the two do not
    /// share a group — membership is the only authorization boundary in the system, and a
    /// 404 does not confirm the account exists.
    /// </summary>
    Task<ProfileResponse> GetPeerAsync(int callerId, int peerId);

    Task<ProfileResponse> UpdateAsync(int userId, UpdateProfileRequest request, CancellationToken cancellationToken = default);

    Task<AvatarUploadResponse> CreateAvatarUploadAsync(int userId, CancellationToken cancellationToken = default);
}
