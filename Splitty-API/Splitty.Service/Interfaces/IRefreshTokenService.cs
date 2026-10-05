using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

/// What a successful refresh hands back: a new access token and the refresh token that
/// replaces the one presented.
public sealed record TokenPair(string Token, string RefreshToken);

/// Owns the refresh token lifecycle. Raw tokens exist only on the way in and out of this
/// service; the database sees their hashes.
public interface IRefreshTokenService
{
    /// Starts a new family for one sign-in and returns its first raw token.
    Task<string> IssueAsync(User user);

    /// Trades a refresh token for a new pair. Null when the token is unknown, expired,
    /// revoked or reused; the caller must answer all four the same way. Presenting a token
    /// that was already revoked revokes the rest of its family.
    Task<TokenPair?> RotateAsync(string rawToken);

    /// Ends the sign-in the token belongs to. Does nothing for a token it never issued.
    Task RevokeFamilyAsync(string rawToken);
}
