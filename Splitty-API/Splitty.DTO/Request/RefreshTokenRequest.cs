using System.ComponentModel.DataAnnotations;

namespace Splitty.DTO.Request;

public class RefreshTokenRequest
{
    [Required(ErrorMessage = "Refresh token is required.")]
    public string RefreshToken { get; set; } = string.Empty;
}
