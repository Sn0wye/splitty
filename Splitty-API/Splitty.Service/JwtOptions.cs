using System.ComponentModel.DataAnnotations;

namespace Splitty.Service;

/// Bound from the `Jwt` section (`Jwt__*` environment variables; see `.env.example`) and
/// validated when the host starts, so a missing or weak key fails the boot rather than the
/// first request.
public sealed class JwtOptions
{
    public const string SectionName = "Jwt";

    /// 32 bytes is the HMAC-SHA256 minimum; a shorter key makes the token handler throw on
    /// every request instead.
    [Required, MinLength(32)]
    public string SecretKey { get; init; } = string.Empty;

    public string? Issuer { get; init; }

    [Range(1, int.MaxValue)]
    public int ExpiryDays { get; init; } = 30;
}
