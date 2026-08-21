using Splitty.Service.Interfaces;

namespace Splitty.API.Tests;

/// Stands in for the one component that would otherwise call Google. The auth code is
/// the identity, pipe-encoded, so a test states exactly what Google "returned" without
/// any shared setup between the client and the host.
public sealed class FakeGoogleTokenExchanger : IGoogleTokenExchanger
{
    public const string RejectedCode = "rejected";

    public static string Encode(string subject, string email, bool emailVerified, string name, string picture = "") =>
        string.Join('|', subject, email, emailVerified, name, picture);

    public Task<GoogleIdentity> ExchangeAsync(string authCode, CancellationToken cancellationToken = default)
    {
        if (authCode == RejectedCode)
        {
            throw new UnauthorizedAccessException("Google rejected the authorization code.");
        }

        var parts = authCode.Split('|');

        return Task.FromResult(new GoogleIdentity(
            parts[0],
            parts[1],
            bool.Parse(parts[2]),
            parts[3],
            parts.Length > 4 ? parts[4] : string.Empty));
    }
}
