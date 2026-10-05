using Splitty.Domain.Entities;

namespace Splitty.DTO.Response;

public class LoginResponse
{
    /// The short-lived access token. Named `token` from when it was the only credential,
    /// so clients that predate refresh tokens decode it unchanged.
    public required string Token { get; set; }
    public required string RefreshToken { get; set; }
    public required User User { get; set; }
}