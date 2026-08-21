namespace Splitty.Service.Interfaces;

/// The identity Google vouched for, as read from a validated `id_token`.
public sealed record GoogleIdentity(
    string Subject,
    string Email,
    bool EmailVerified,
    string Name,
    string Picture);

/// The only seam in the codebase that talks to Google over the network. Everything
/// above it — linking rules, user creation, token minting — is testable without it.
public interface IGoogleTokenExchanger
{
    /// Exchanges a one-time authorization code for an identity.
    /// Throws <see cref="UnauthorizedAccessException"/> when Google rejects the code
    /// or the returned `id_token` fails validation.
    Task<GoogleIdentity> ExchangeAsync(string authCode, CancellationToken cancellationToken = default);
}
