using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IRefreshTokenRepository
{
    Task CreateAsync(RefreshToken token);

    /// With the user loaded, so a rotation can issue the access token without a second read.
    Task<RefreshToken?> GetByHashAsync(string tokenHash);

    /// Inserts the replacement and revokes the current row as a single unit, provided the
    /// current row is still unrevoked. Returns false, having written nothing, when another
    /// request revoked it first.
    Task<bool> TryRotateAsync(Guid currentId, RefreshToken replacement);

    /// Revokes every row in the family that is not revoked already.
    Task RevokeFamilyAsync(Guid familyId);

    /// Revokes every live row the user holds, across all their families.
    Task RevokeAllForUserAsync(int userId);
}
