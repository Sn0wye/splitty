namespace Splitty.DTO.Request;

/// Unlike <see cref="RefreshTokenRequest"/>, the token is optional: logout answers 204
/// whether or not there is anything to revoke.
public class LogoutRequest
{
    public string? RefreshToken { get; set; }
}
