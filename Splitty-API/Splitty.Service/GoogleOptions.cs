using System.ComponentModel.DataAnnotations;

namespace Splitty.Service;

/// Bound from the `Google__*` environment variables; see `.env.example`. The web OAuth
/// client, not the iOS one: an iOS client has no secret and cannot perform the code exchange.
public sealed class GoogleOptions
{
    public const string SectionName = "Google";

    [Required]
    public string ClientId { get; init; } = string.Empty;

    [Required]
    public string ClientSecret { get; init; } = string.Empty;
}
