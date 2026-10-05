using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using Splitty.Domain.Entities;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class RefreshTokenService(
    IRefreshTokenRepository refreshTokenRepository,
    IJwtTokenIssuer tokenIssuer,
    IOptions<JwtOptions> options
) : IRefreshTokenService
{
    private const int TokenBytes = 32;

    public async Task<string> IssueAsync(User user)
    {
        var (raw, token) = Create(user.Id, Guid.NewGuid());

        await refreshTokenRepository.CreateAsync(token);

        return raw;
    }

    public async Task<TokenPair?> RotateAsync(string rawToken)
    {
        var current = await refreshTokenRepository.GetByHashAsync(Hash(rawToken));

        if (current is null || current.ExpiresAt <= DateTime.UtcNow)
        {
            return null;
        }

        if (current.RevokedAt is null)
        {
            var (raw, replacement) = Create(current.UserId, current.FamilyId);

            if (await refreshTokenRepository.TryRotateAsync(current.Id, replacement))
            {
                return new TokenPair(tokenIssuer.Issue(current.User), raw);
            }

            // Lost the race to a concurrent refresh with the same token. The client sends
            // one refresh at a time, so two in flight is treated as the reuse it looks like.
        }

        // A token that was already used came back: either the client or someone holding a
        // copy is replaying it, and the server cannot tell which. Ending the family stops
        // both.
        await refreshTokenRepository.RevokeFamilyAsync(current.FamilyId);

        return null;
    }

    public async Task RevokeFamilyAsync(string rawToken)
    {
        var token = await refreshTokenRepository.GetByHashAsync(Hash(rawToken));

        if (token is not null)
        {
            await refreshTokenRepository.RevokeFamilyAsync(token.FamilyId);
        }
    }

    private (string raw, RefreshToken token) Create(int userId, Guid familyId)
    {
        var raw = Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(TokenBytes));
        var now = DateTime.UtcNow;

        return (raw, new RefreshToken
        {
            UserId = userId,
            FamilyId = familyId,
            TokenHash = Hash(raw),
            CreatedAt = now,
            // Sliding: every rotation starts the idle window again.
            ExpiresAt = now.AddDays(options.Value.RefreshTokenDays)
        });
    }

    /// Unsalted on purpose: the input is 32 random bytes, not a guessable secret, and the
    /// hash has to be deterministic to be looked up.
    private static string Hash(string raw) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(raw)));
}
