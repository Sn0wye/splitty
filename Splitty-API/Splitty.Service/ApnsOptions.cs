using System.ComponentModel.DataAnnotations;

namespace Splitty.Service;

/// Bound from the `Apns__*` environment variables; see `.env.example`.
public sealed class ApnsOptions
{
    public const string SectionName = "Apns";

    /// The Apple Developer team id, the `iss` of the provider token.
    [Required]
    public string TeamId { get; init; } = string.Empty;

    /// The id of the APNs auth key (.p8), the `kid` of the provider token.
    [Required]
    public string KeyId { get; init; } = string.Empty;

    /// The app's bundle id, sent as `apns-topic`.
    [Required]
    public string BundleId { get; init; } = string.Empty;

    /// The contents of the .p8 file: the PEM text, or only its base64 body when the
    /// environment cannot hold newlines.
    [Required]
    public string PrivateKey { get; init; } = string.Empty;

    public bool IsConfigured => !string.IsNullOrWhiteSpace(PrivateKey);
}
