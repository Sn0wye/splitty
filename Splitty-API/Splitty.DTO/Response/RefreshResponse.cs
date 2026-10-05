namespace Splitty.DTO.Response;

public class RefreshResponse
{
    public required string Token { get; set; }
    public required string RefreshToken { get; set; }
}
