using System.ComponentModel.DataAnnotations;
using Splitty.Domain.Entities;

namespace Splitty.DTO.Request;

public class RegisterPushDeviceRequest
{
    /// The APNs device token, hex-encoded as the app reads it.
    [Required, RegularExpression("^[0-9a-fA-F]{64,200}$")]
    public string Token { get; set; } = string.Empty;

    [Required]
    public ApnsEnvironment? Environment { get; set; }

    /// The language picked in the app: `en`, `pt-BR`, `es` or `fr`.
    [Required]
    public string Language { get; set; } = string.Empty;
}
